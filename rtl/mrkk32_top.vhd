-- ============================================================
--  MRKK-32  --  Top Level
--  Wires all 17 modules into one complete CPU entity.
--
--  Signal flow:
--    fetch_stage
--      -> if_id_reg
--        -> decode_exec_stage  (+ alu, decoder, regfile, immgen, muldiv)
--          -> id_wb_reg
--            -> writeback_stage
--              -> mmio_bus
--                -> data_memory / dcache / peripherals
--    hazard_flush -> stall/flush -> fetch + pipeline regs
--    interrupt_ctrl -> irq redirect -> fetch
--
--  External ports  (what the chip exposes to the outside world):
--    clk, rst
--    gpio_in[7:0], gpio_out[7:0], gpio_dir[7:0]
--    irq_lines[3:0]
--    uart_tx_byte[7:0], uart_tx_valid   (observable in simulation)
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mrkk32_top is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        -- GPIO
        gpio_in      : in  std_logic_vector(7 downto 0);
        gpio_out     : out std_logic_vector(7 downto 0);
        gpio_dir     : out std_logic_vector(7 downto 0);
        -- External interrupts
        irq_lines    : in  std_logic_vector(3 downto 0);
        -- UART (observable)
        uart_tx_byte : out std_logic_vector(7 downto 0);
        uart_tx_valid: out std_logic
    );
end entity mrkk32_top;

architecture rtl of mrkk32_top is

    -- ── Pipeline control ──────────────────────────────────────
    signal stall         : std_logic;
    signal flush         : std_logic;
    signal branch_taken  : std_logic;
    signal branch_target : std_logic_vector(31 downto 0);

    -- ── Fetch stage outputs ───────────────────────────────────
    signal fetch_pc       : std_logic_vector(31 downto 0);
    signal fetch_pc_plus4 : std_logic_vector(31 downto 0);
    signal fetch_instr    : std_logic_vector(31 downto 0);

    -- ── Instruction memory / I-cache ─────────────────────────
    signal imem_addr      : std_logic_vector(31 downto 0);
    signal imem_data      : std_logic_vector(31 downto 0);
    signal icache_mem_addr: std_logic_vector(31 downto 0);
    signal icache_mem_rd  : std_logic;
    signal icache_stall   : std_logic;
    signal icache_data    : std_logic_vector(31 downto 0);

    -- ── IF/ID register outputs ───────────────────────────────
    signal if_id_pc       : std_logic_vector(31 downto 0);
    signal if_id_pc_plus4 : std_logic_vector(31 downto 0);
    signal if_id_instr    : std_logic_vector(31 downto 0);

    -- ── Decode/Execute outputs ────────────────────────────────
    signal dex_pc_plus4   : std_logic_vector(31 downto 0);
    signal dex_alu_result : std_logic_vector(31 downto 0);
    signal dex_rs2_data   : std_logic_vector(31 downto 0);
    signal dex_rd_addr    : std_logic_vector(4  downto 0);
    signal dex_reg_wr     : std_logic;
    signal dex_mem_rd     : std_logic;
    signal dex_mem_wr     : std_logic;
    signal dex_mem_sz     : std_logic_vector(1  downto 0);
    signal dex_mem_sx     : std_logic;
    signal dex_lui_result : std_logic_vector(31 downto 0);
    signal dex_is_lui     : std_logic;
    signal dex_is_jump    : std_logic;

    -- ── ID/WB register outputs ────────────────────────────────
    signal wb_pc_plus4    : std_logic_vector(31 downto 0);
    signal wb_alu_result  : std_logic_vector(31 downto 0);
    signal wb_rs2_data    : std_logic_vector(31 downto 0);
    signal wb_rd_addr     : std_logic_vector(4  downto 0);
    signal wb_reg_wr      : std_logic;
    signal wb_mem_rd      : std_logic;
    signal wb_mem_wr      : std_logic;
    signal wb_mem_sz      : std_logic_vector(1  downto 0);
    signal wb_mem_sx      : std_logic;
    signal wb_lui_result  : std_logic_vector(31 downto 0);
    signal wb_is_lui      : std_logic;
    signal wb_is_jump     : std_logic;

    -- ── Writeback -> register file ────────────────────────────
    signal rf_wr_en       : std_logic;
    signal rf_rd_addr     : std_logic_vector(4  downto 0);
    signal rf_wr_data     : std_logic_vector(31 downto 0);

    -- ── Writeback -> memory/MMIO ──────────────────────────────
    signal wb_dmem_addr   : std_logic_vector(31 downto 0);
    signal wb_dmem_wrdata : std_logic_vector(31 downto 0);
    signal wb_dmem_wr_en  : std_logic;
    signal wb_dmem_rd_en  : std_logic;
    signal wb_dmem_sz     : std_logic_vector(1  downto 0);
    signal wb_dmem_rddata : std_logic_vector(31 downto 0);

    -- ── MMIO bus -> data memory / D-cache ────────────────────
    signal mmio_dmem_addr   : std_logic_vector(31 downto 0);
    signal mmio_dmem_wr_en  : std_logic;
    signal mmio_dmem_rd_en  : std_logic;
    signal mmio_dmem_wrdata : std_logic_vector(31 downto 0);
    signal mmio_dmem_rddata : std_logic_vector(31 downto 0);

    -- ── D-cache -> data memory ────────────────────────────────
    signal dcache_mem_addr  : std_logic_vector(31 downto 0);
    signal dcache_mem_rd    : std_logic;
    signal dcache_mem_wr    : std_logic;
    signal dcache_mem_wrdat : std_logic_vector(31 downto 0);
    signal dcache_mem_sz    : std_logic_vector(1  downto 0);
    signal dcache_mem_rddat : std_logic_vector(31 downto 0);
    signal dcache_cpu_rddat : std_logic_vector(31 downto 0);
    signal dcache_stall     : std_logic;

    -- ── MMIO peripheral ports ─────────────────────────────────
    signal uart_addr      : std_logic_vector(2 downto 0);
    signal uart_wr_en     : std_logic;
    signal uart_wr_data   : std_logic_vector(31 downto 0);
    signal uart_rd_data   : std_logic_vector(31 downto 0);

    signal gpio_addr      : std_logic_vector(1 downto 0);
    signal gpio_wr_en     : std_logic;
    signal gpio_wr_data   : std_logic_vector(31 downto 0);
    signal gpio_rd_data   : std_logic_vector(31 downto 0);
    signal gpio_irq       : std_logic;

    signal timer_addr     : std_logic_vector(1 downto 0);
    signal timer_wr_en    : std_logic;
    signal timer_wr_data  : std_logic_vector(31 downto 0);
    signal timer_rd_data  : std_logic_vector(31 downto 0);
    signal timer_irq      : std_logic;

    signal irqc_addr      : std_logic_vector(1 downto 0);
    signal irqc_wr_en     : std_logic;
    signal irqc_wr_data   : std_logic_vector(3 downto 0);
    signal irqc_rd_data   : std_logic_vector(3 downto 0);

    -- ── Interrupt controller ──────────────────────────────────
    signal all_irq_lines  : std_logic_vector(3 downto 0);
    signal mie            : std_logic := '1';  -- machine interrupt enable
    signal irq_taken      : std_logic;
    signal irq_mepc_out   : std_logic_vector(31 downto 0);
    signal irq_mcause     : std_logic_vector(31 downto 0);
    signal irq_mtvec      : std_logic_vector(31 downto 0);

    -- ── Combined stall (cache miss OR load-use) ───────────────
    signal total_stall    : std_logic;
    signal total_flush    : std_logic;
    signal final_branch_taken  : std_logic;
    signal final_branch_target : std_logic_vector(31 downto 0);

begin

    -- ── Aggregate IRQ sources ─────────────────────────────────
    all_irq_lines <= irq_lines or
                     ("000" & timer_irq) or
                     ("000" & gpio_irq & "00");

    -- ── Interrupt overrides branch when accepted ──────────────
    final_branch_taken  <= branch_taken or irq_taken;
    final_branch_target <= irq_mtvec when irq_taken = '1' else branch_target;

    -- ── Total stall = cache miss stalls ──────────────────────
    total_stall <= stall or icache_stall or dcache_stall;
    total_flush <= flush or irq_taken;

    -- ─────────────────────────────────────────────────────────
    --  FETCH STAGE
    -- ─────────────────────────────────────────────────────────
    u_fetch: entity work.fetch_stage
        port map(
            clk           => clk,
            rst           => rst,
            stall         => total_stall,
            flush         => total_flush,
            branch_taken  => final_branch_taken,
            branch_target => final_branch_target,
            imem_addr     => imem_addr,
            imem_data     => icache_data,
            pc_out        => fetch_pc,
            pc_plus4_out  => fetch_pc_plus4,
            instr_out     => fetch_instr
        );

    -- ─────────────────────────────────────────────────────────
    --  I-CACHE
    -- ─────────────────────────────────────────────────────────
    u_icache: entity work.icache
        port map(
            clk        => clk,
            rst        => rst,
            cpu_addr   => imem_addr,
            cpu_rd_en  => '1',
            cpu_data   => icache_data,
            stall_req  => icache_stall,
            mem_addr   => icache_mem_addr,
            mem_rd_en  => icache_mem_rd,
            mem_data   => imem_data
        );

    -- ─────────────────────────────────────────────────────────
    --  INSTRUCTION MEMORY
    -- ─────────────────────────────────────────────────────────
    u_imem: entity work.instr_memory
        port map(
            clk   => clk,
            addr  => icache_mem_addr,
            instr => imem_data
        );

    -- ─────────────────────────────────────────────────────────
    --  IF/ID PIPELINE REGISTER
    -- ─────────────────────────────────────────────────────────
    u_if_id: entity work.if_id_reg
        port map(
            clk          => clk,
            rst          => rst,
            flush        => total_flush,
            stall        => total_stall,
            in_pc        => fetch_pc,
            in_pc_plus4  => fetch_pc_plus4,
            in_instr     => fetch_instr,
            out_pc       => if_id_pc,
            out_pc_plus4 => if_id_pc_plus4,
            out_instr    => if_id_instr
        );

    -- ─────────────────────────────────────────────────────────
    --  DECODE / EXECUTE STAGE
    -- ─────────────────────────────────────────────────────────
    u_dex: entity work.decode_exec_stage
        port map(
            clk            => clk,
            rst            => rst,
            if_pc          => if_id_pc,
            if_pc_plus4    => if_id_pc_plus4,
            if_instr       => if_id_instr,
            wb_rd_addr     => rf_rd_addr,
            wb_wr_data     => rf_wr_data,
            wb_wr_en       => rf_wr_en,
            branch_taken   => branch_taken,
            branch_target  => branch_target,
            pc_plus4_out   => dex_pc_plus4,
            alu_result_out => dex_alu_result,
            rs2_data_out   => dex_rs2_data,
            rd_addr_out    => dex_rd_addr,
            reg_wr_out     => dex_reg_wr,
            mem_rd_out     => dex_mem_rd,
            mem_wr_out     => dex_mem_wr,
            mem_sz_out     => dex_mem_sz,
            mem_sx_out     => dex_mem_sx,
            lui_result_out => dex_lui_result,
            is_lui_out     => dex_is_lui,
            is_jump_out    => dex_is_jump
        );

    -- ─────────────────────────────────────────────────────────
    --  HAZARD / FLUSH CONTROL
    -- ─────────────────────────────────────────────────────────
    u_hazard: entity work.hazard_flush
        port map(
            id_ex_mem_rd  => dex_mem_rd,
            id_ex_rd_addr => dex_rd_addr,
            if_rs1_addr   => if_id_instr(19 downto 15),
            if_rs2_addr   => if_id_instr(24 downto 20),
            branch_taken  => branch_taken,
            stall         => stall,
            flush         => flush
        );

    -- ─────────────────────────────────────────────────────────
    --  ID/WB PIPELINE REGISTER
    -- ─────────────────────────────────────────────────────────
    u_id_wb: entity work.id_wb_reg
        port map(
            clk            => clk,
            rst            => rst,
            flush          => total_flush,
            stall          => total_stall,
            in_pc_plus4    => dex_pc_plus4,
            in_alu_result  => dex_alu_result,
            in_rs2_data    => dex_rs2_data,
            in_rd_addr     => dex_rd_addr,
            in_reg_wr      => dex_reg_wr,
            in_mem_rd      => dex_mem_rd,
            in_mem_wr      => dex_mem_wr,
            in_mem_sz      => dex_mem_sz,
            in_mem_sx      => dex_mem_sx,
            in_lui_result  => dex_lui_result,
            in_is_lui      => dex_is_lui,
            in_is_jump     => dex_is_jump,
            out_pc_plus4   => wb_pc_plus4,
            out_alu_result => wb_alu_result,
            out_rs2_data   => wb_rs2_data,
            out_rd_addr    => wb_rd_addr,
            out_reg_wr     => wb_reg_wr,
            out_mem_rd     => wb_mem_rd,
            out_mem_wr     => wb_mem_wr,
            out_mem_sz     => wb_mem_sz,
            out_mem_sx     => wb_mem_sx,
            out_lui_result => wb_lui_result,
            out_is_lui     => wb_is_lui,
            out_is_jump    => wb_is_jump
        );

    -- ─────────────────────────────────────────────────────────
    --  WRITEBACK STAGE
    -- ─────────────────────────────────────────────────────────
    u_wb: entity work.writeback_stage
        port map(
            pc_plus4     => wb_pc_plus4,
            alu_result   => wb_alu_result,
            rs2_data     => wb_rs2_data,
            rd_addr      => wb_rd_addr,
            reg_wr       => wb_reg_wr,
            mem_rd       => wb_mem_rd,
            mem_wr       => wb_mem_wr,
            mem_sz       => wb_mem_sz,
            mem_sx       => wb_mem_sx,
            lui_result   => wb_lui_result,
            is_lui       => wb_is_lui,
            is_jump      => wb_is_jump,
            dmem_addr    => wb_dmem_addr,
            dmem_wr_data => wb_dmem_wrdata,
            dmem_wr_en   => wb_dmem_wr_en,
            dmem_rd_en   => wb_dmem_rd_en,
            dmem_sz      => wb_dmem_sz,
            dmem_rd_data => wb_dmem_rddata,
            rf_wr_en     => rf_wr_en,
            rf_rd_addr   => rf_rd_addr,
            rf_wr_data   => rf_wr_data
        );

    -- ─────────────────────────────────────────────────────────
    --  MMIO BUS
    -- ─────────────────────────────────────────────────────────
    u_mmio: entity work.mmio_bus
        port map(
            clk          => clk,
            rst          => rst,
            cpu_addr     => wb_dmem_addr,
            cpu_wr_en    => wb_dmem_wr_en,
            cpu_rd_en    => wb_dmem_rd_en,
            cpu_wr_data  => wb_dmem_wrdata,
            cpu_rd_data  => wb_dmem_rddata,
            dmem_addr    => mmio_dmem_addr,
            dmem_wr_en   => mmio_dmem_wr_en,
            dmem_rd_en   => mmio_dmem_rd_en,
            dmem_wr_data => mmio_dmem_wrdata,
            dmem_rd_data => mmio_dmem_rddata,
            uart_addr    => uart_addr,
            uart_wr_en   => uart_wr_en,
            uart_wr_data => uart_wr_data,
            uart_rd_data => uart_rd_data,
            gpio_addr    => gpio_addr,
            gpio_wr_en   => gpio_wr_en,
            gpio_wr_data => gpio_wr_data,
            gpio_rd_data => gpio_rd_data,
            timer_addr   => timer_addr,
            timer_wr_en  => timer_wr_en,
            timer_wr_data=> timer_wr_data,
            timer_rd_data=> timer_rd_data,
            irqc_addr    => irqc_addr,
            irqc_wr_en   => irqc_wr_en,
            irqc_wr_data => irqc_wr_data,
            irqc_rd_data => irqc_rd_data
        );

    -- ─────────────────────────────────────────────────────────
    --  D-CACHE
    -- ─────────────────────────────────────────────────────────
    u_dcache: entity work.dcache
        port map(
            clk          => clk,
            rst          => rst,
            cpu_addr     => mmio_dmem_addr,
            cpu_rd_en    => mmio_dmem_rd_en,
            cpu_wr_en    => mmio_dmem_wr_en,
            cpu_wr_data  => mmio_dmem_wrdata,
            cpu_sz       => wb_dmem_sz,
            cpu_rd_data  => dcache_cpu_rddat,
            stall_req    => dcache_stall,
            mem_addr     => dcache_mem_addr,
            mem_rd_en    => dcache_mem_rd,
            mem_wr_en    => dcache_mem_wr,
            mem_wr_data  => dcache_mem_wrdat,
            mem_sz       => dcache_mem_sz,
            mem_rd_data  => dcache_mem_rddat
        );

    mmio_dmem_rddata <= dcache_cpu_rddat;

    -- ─────────────────────────────────────────────────────────
    --  DATA MEMORY
    -- ─────────────────────────────────────────────────────────
    u_dmem: entity work.data_memory
        port map(
            clk      => clk,
            wr_en    => dcache_mem_wr,
            addr     => dcache_mem_addr,
            wr_data  => dcache_mem_wrdat,
            sz       => dcache_mem_sz,
            rd_en    => dcache_mem_rd,
            rd_data  => dcache_mem_rddat
        );

    -- ─────────────────────────────────────────────────────────
    --  PERIPHERALS
    -- ─────────────────────────────────────────────────────────
    u_uart: entity work.uart_periph
        port map(
            clk      => clk,
            rst      => rst,
            addr     => uart_addr,
            wr_en    => uart_wr_en,
            wr_data  => uart_wr_data,
            rd_data  => uart_rd_data,
            tx_irq   => open,
            rx_irq   => open,
            tx_byte  => uart_tx_byte,
            tx_valid => uart_tx_valid
        );

    u_gpio: entity work.gpio_periph
        port map(
            clk      => clk,
            rst      => rst,
            addr     => gpio_addr,
            wr_en    => gpio_wr_en,
            wr_data  => gpio_wr_data,
            rd_data  => gpio_rd_data,
            gpio_out => gpio_out,
            gpio_in  => gpio_in,
            gpio_dir => gpio_dir,
            gpio_irq => gpio_irq
        );

    u_timer: entity work.timer_periph
        port map(
            clk       => clk,
            rst       => rst,
            addr      => timer_addr,
            wr_en     => timer_wr_en,
            wr_data   => timer_wr_data,
            rd_data   => timer_rd_data,
            timer_irq => timer_irq
        );

    -- ─────────────────────────────────────────────────────────
    --  INTERRUPT CONTROLLER
    -- ─────────────────────────────────────────────────────────
    u_irqc: entity work.interrupt_ctrl
        port map(
            clk         => clk,
            rst         => rst,
            irq_lines   => all_irq_lines,
            mie         => mie,
            mepc_in     => fetch_pc,
            mepc_out    => irq_mepc_out,
            mcause_out  => irq_mcause,
            reg_addr    => irqc_addr,
            reg_wr_en   => irqc_wr_en,
            reg_wr_data => irqc_wr_data,
            reg_rd_data => irqc_rd_data,
            irq_taken   => irq_taken,
            mtvec       => irq_mtvec
        );

end architecture rtl;