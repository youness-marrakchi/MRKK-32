-- ============================================================
--  MRKK-32  --  Full System Testbench
--  Strategy: wrap mrkk32_top, override instr_memory with a
--  simulation model that has the Fibonacci program pre-loaded.
--
--  Fibonacci program (RV32I hand-assembled):
--    Computes fib(0)..fib(9), stores to data memory 0x00-0x24
--    Expected: 0,1,1,2,3,5,8,13,21,34
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ── Simulation instruction memory with Fibonacci ROM ─────────
entity sim_imem is
    port (
        clk   : in  std_logic;
        addr  : in  std_logic_vector(31 downto 0);
        instr : out std_logic_vector(31 downto 0)
    );
end entity sim_imem;

architecture sim of sim_imem is
    type rom_t is array (0 to 255) of std_logic_vector(31 downto 0);
    signal rom : rom_t := (
        --  addi x1, x0, 0
        0  => x"00000093",
        --  addi x2, x0, 1
        1  => x"00100113",
        --  addi x4, x0, 8
        2  => x"00800213",
        --  addi x5, x0, 8
        3  => x"00800293",
        --  sw x1, 0(x0)
        4  => x"00102023",
        --  sw x2, 4(x0)
        5  => x"00202223",
        -- LOOP (word 6 = byte 0x18):
        --  add x3, x1, x2
        6  => x"002081B3",
        --  sw x3, 0(x5)
        7  => x"0032A023",
        --  addi x1, x2, 0
        8  => x"00010093",
        --  addi x2, x3, 0
        9  => x"00018113",
        --  addi x5, x5, 4
        10 => x"00428293",
        --  addi x4, x4, -1
        11 => x"FFF20213",
        --  bne x4, x0, -24  (back to word 6)
        12 => x"FE021463",
        --  nop
        13 => x"00000013",
        --  jal x0, -4  (spin on nop)
        14 => x"FFDFF06F",
        others => x"00000013"
    );
    signal word_idx : integer range 0 to 255;
begin
    word_idx <= to_integer(unsigned(addr(31 downto 2))) mod 256;
    process(clk)
    begin
        if rising_edge(clk) then
            instr <= rom(word_idx);
        end if;
    end process;
end architecture sim;


-- ── Simulation top: CPU with sim_imem wired in ───────────────
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mrkk32 is end entity;

architecture sim of tb_mrkk32 is

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal gpio_in       : std_logic_vector(7 downto 0) := (others=>'0');
    signal gpio_out      : std_logic_vector(7 downto 0);
    signal gpio_dir      : std_logic_vector(7 downto 0);
    signal irq_lines     : std_logic_vector(3 downto 0) := "0000";
    signal uart_tx_byte  : std_logic_vector(7 downto 0);
    signal uart_tx_valid : std_logic;

    -- Internal wiring (replicate mrkk32_top relevant paths)
    signal stall         : std_logic;
    signal flush         : std_logic;
    signal branch_taken  : std_logic;
    signal branch_target : std_logic_vector(31 downto 0);
    signal fetch_pc      : std_logic_vector(31 downto 0);
    signal fetch_pc_plus4: std_logic_vector(31 downto 0);
    signal fetch_instr   : std_logic_vector(31 downto 0);
    signal imem_addr     : std_logic_vector(31 downto 0);
    signal imem_data     : std_logic_vector(31 downto 0);
    signal icache_stall  : std_logic;
    signal icache_data   : std_logic_vector(31 downto 0);
    signal icache_mem_addr: std_logic_vector(31 downto 0);
    signal icache_mem_rd : std_logic;
    signal if_id_pc      : std_logic_vector(31 downto 0);
    signal if_id_pc_plus4: std_logic_vector(31 downto 0);
    signal if_id_instr   : std_logic_vector(31 downto 0);
    signal dex_pc_plus4  : std_logic_vector(31 downto 0);
    signal dex_alu_result: std_logic_vector(31 downto 0);
    signal dex_rs2_data  : std_logic_vector(31 downto 0);
    signal dex_rd_addr   : std_logic_vector(4  downto 0);
    signal dex_reg_wr    : std_logic;
    signal dex_mem_rd    : std_logic;
    signal dex_mem_wr    : std_logic;
    signal dex_mem_sz    : std_logic_vector(1  downto 0);
    signal dex_mem_sx    : std_logic;
    signal dex_lui_result: std_logic_vector(31 downto 0);
    signal dex_is_lui    : std_logic;
    signal dex_is_jump   : std_logic;
    signal wb_pc_plus4   : std_logic_vector(31 downto 0);
    signal wb_alu_result : std_logic_vector(31 downto 0);
    signal wb_rs2_data   : std_logic_vector(31 downto 0);
    signal wb_rd_addr    : std_logic_vector(4  downto 0);
    signal wb_reg_wr     : std_logic;
    signal wb_mem_rd     : std_logic;
    signal wb_mem_wr     : std_logic;
    signal wb_mem_sz     : std_logic_vector(1  downto 0);
    signal wb_mem_sx     : std_logic;
    signal wb_lui_result : std_logic_vector(31 downto 0);
    signal wb_is_lui     : std_logic;
    signal wb_is_jump    : std_logic;
    signal rf_wr_en      : std_logic;
    signal rf_rd_addr    : std_logic_vector(4  downto 0);
    signal rf_wr_data    : std_logic_vector(31 downto 0);
    signal wb_dmem_addr  : std_logic_vector(31 downto 0);
    signal wb_dmem_wrdata: std_logic_vector(31 downto 0);
    signal wb_dmem_wr_en : std_logic;
    signal wb_dmem_rd_en : std_logic;
    signal wb_dmem_sz    : std_logic_vector(1  downto 0);
    signal wb_dmem_rddata: std_logic_vector(31 downto 0);
    signal mmio_dmem_addr  : std_logic_vector(31 downto 0);
    signal mmio_dmem_wr_en : std_logic;
    signal mmio_dmem_rd_en : std_logic;
    signal mmio_dmem_wrdata: std_logic_vector(31 downto 0);
    signal mmio_dmem_rddata: std_logic_vector(31 downto 0);
    signal dcache_mem_addr : std_logic_vector(31 downto 0);
    signal dcache_mem_rd   : std_logic;
    signal dcache_mem_wr   : std_logic;
    signal dcache_mem_wrdat: std_logic_vector(31 downto 0);
    signal dcache_mem_sz   : std_logic_vector(1  downto 0);
    signal dcache_mem_rddat: std_logic_vector(31 downto 0);
    signal dcache_cpu_rddat: std_logic_vector(31 downto 0);
    signal dcache_stall    : std_logic;
    signal uart_addr       : std_logic_vector(2 downto 0);
    signal uart_wr_en      : std_logic;
    signal uart_wr_data    : std_logic_vector(31 downto 0);
    signal uart_rd_data    : std_logic_vector(31 downto 0);
    signal gpio_addr_s     : std_logic_vector(1 downto 0);
    signal gpio_wr_en_s    : std_logic;
    signal gpio_wr_data_s  : std_logic_vector(31 downto 0);
    signal gpio_rd_data_s  : std_logic_vector(31 downto 0);
    signal gpio_irq_s      : std_logic;
    signal timer_addr_s    : std_logic_vector(1 downto 0);
    signal timer_wr_en_s   : std_logic;
    signal timer_wr_data_s : std_logic_vector(31 downto 0);
    signal timer_rd_data_s : std_logic_vector(31 downto 0);
    signal timer_irq_s     : std_logic;
    signal irqc_addr_s     : std_logic_vector(1 downto 0);
    signal irqc_wr_en_s    : std_logic;
    signal irqc_wr_data_s  : std_logic_vector(3 downto 0);
    signal irqc_rd_data_s  : std_logic_vector(3 downto 0);
    signal all_irq_lines   : std_logic_vector(3 downto 0);
    signal irq_taken       : std_logic;
    signal irq_mepc_out    : std_logic_vector(31 downto 0);
    signal irq_mcause      : std_logic_vector(31 downto 0);
    signal irq_mtvec       : std_logic_vector(31 downto 0);
    signal mie_s           : std_logic := '1';
    signal total_stall     : std_logic;
    signal total_flush     : std_logic;
    signal final_taken     : std_logic;
    signal final_target    : std_logic_vector(31 downto 0);

    constant CLK_P : time := 10 ns;

    -- Fibonacci golden results
    type fib_t is array (0 to 9) of integer;
    constant FIB : fib_t := (0,1,1,2,3,5,8,13,21,34);

begin
    clk <= not clk after CLK_P/2;

    all_irq_lines <= irq_lines or ("000" & timer_irq_s) or ("00" & gpio_irq_s & "0");
    final_taken   <= branch_taken or irq_taken;
    final_target  <= irq_mtvec when irq_taken='1' else branch_target;
    total_stall   <= stall or icache_stall or dcache_stall;
    total_flush   <= flush or irq_taken;
    mmio_dmem_rddata <= dcache_cpu_rddat;

    u_fetch: entity work.fetch_stage
        port map(clk=>clk, rst=>rst, stall=>total_stall, flush=>total_flush,
                 branch_taken=>final_taken, branch_target=>final_target,
                 imem_addr=>imem_addr, imem_data=>icache_data,
                 pc_out=>fetch_pc, pc_plus4_out=>fetch_pc_plus4, instr_out=>fetch_instr);

    u_icache: entity work.icache
        port map(clk=>clk, rst=>rst, cpu_addr=>imem_addr, cpu_rd_en=>'1',
                 cpu_data=>icache_data, stall_req=>icache_stall,
                 mem_addr=>icache_mem_addr, mem_rd_en=>icache_mem_rd, mem_data=>imem_data);

    u_imem: entity work.sim_imem
        port map(clk=>clk, addr=>icache_mem_addr, instr=>imem_data);

    u_if_id: entity work.if_id_reg
        port map(clk=>clk, rst=>rst, flush=>total_flush, stall=>total_stall,
                 in_pc=>fetch_pc, in_pc_plus4=>fetch_pc_plus4, in_instr=>fetch_instr,
                 out_pc=>if_id_pc, out_pc_plus4=>if_id_pc_plus4, out_instr=>if_id_instr);

    u_dex: entity work.decode_exec_stage
        port map(clk=>clk, rst=>rst,
                 if_pc=>if_id_pc, if_pc_plus4=>if_id_pc_plus4, if_instr=>if_id_instr,
                 wb_rd_addr=>rf_rd_addr, wb_wr_data=>rf_wr_data, wb_wr_en=>rf_wr_en,
                 branch_taken=>branch_taken, branch_target=>branch_target,
                 pc_plus4_out=>dex_pc_plus4, alu_result_out=>dex_alu_result,
                 rs2_data_out=>dex_rs2_data, rd_addr_out=>dex_rd_addr,
                 reg_wr_out=>dex_reg_wr, mem_rd_out=>dex_mem_rd, mem_wr_out=>dex_mem_wr,
                 mem_sz_out=>dex_mem_sz, mem_sx_out=>dex_mem_sx,
                 lui_result_out=>dex_lui_result, is_lui_out=>dex_is_lui, is_jump_out=>dex_is_jump);

    u_hazard: entity work.hazard_flush
        port map(id_ex_mem_rd=>dex_mem_rd, id_ex_rd_addr=>dex_rd_addr,
                 if_rs1_addr=>if_id_instr(19 downto 15),
                 if_rs2_addr=>if_id_instr(24 downto 20),
                 branch_taken=>branch_taken, stall=>stall, flush=>flush);

    u_id_wb: entity work.id_wb_reg
        port map(clk=>clk, rst=>rst, flush=>total_flush, stall=>total_stall,
                 in_pc_plus4=>dex_pc_plus4, in_alu_result=>dex_alu_result,
                 in_rs2_data=>dex_rs2_data, in_rd_addr=>dex_rd_addr,
                 in_reg_wr=>dex_reg_wr, in_mem_rd=>dex_mem_rd, in_mem_wr=>dex_mem_wr,
                 in_mem_sz=>dex_mem_sz, in_mem_sx=>dex_mem_sx,
                 in_lui_result=>dex_lui_result, in_is_lui=>dex_is_lui, in_is_jump=>dex_is_jump,
                 out_pc_plus4=>wb_pc_plus4, out_alu_result=>wb_alu_result,
                 out_rs2_data=>wb_rs2_data, out_rd_addr=>wb_rd_addr,
                 out_reg_wr=>wb_reg_wr, out_mem_rd=>wb_mem_rd, out_mem_wr=>wb_mem_wr,
                 out_mem_sz=>wb_mem_sz, out_mem_sx=>wb_mem_sx,
                 out_lui_result=>wb_lui_result, out_is_lui=>wb_is_lui, out_is_jump=>wb_is_jump);

    u_wb: entity work.writeback_stage
        port map(pc_plus4=>wb_pc_plus4, alu_result=>wb_alu_result, rs2_data=>wb_rs2_data,
                 rd_addr=>wb_rd_addr, reg_wr=>wb_reg_wr, mem_rd=>wb_mem_rd,
                 mem_wr=>wb_mem_wr, mem_sz=>wb_mem_sz, mem_sx=>wb_mem_sx,
                 lui_result=>wb_lui_result, is_lui=>wb_is_lui, is_jump=>wb_is_jump,
                 dmem_addr=>wb_dmem_addr, dmem_wr_data=>wb_dmem_wrdata,
                 dmem_wr_en=>wb_dmem_wr_en, dmem_rd_en=>wb_dmem_rd_en,
                 dmem_sz=>wb_dmem_sz, dmem_rd_data=>wb_dmem_rddata,
                 rf_wr_en=>rf_wr_en, rf_rd_addr=>rf_rd_addr, rf_wr_data=>rf_wr_data);

    u_mmio: entity work.mmio_bus
        port map(clk=>clk, rst=>rst,
                 cpu_addr=>wb_dmem_addr, cpu_wr_en=>wb_dmem_wr_en, cpu_rd_en=>wb_dmem_rd_en,
                 cpu_wr_data=>wb_dmem_wrdata, cpu_rd_data=>wb_dmem_rddata,
                 dmem_addr=>mmio_dmem_addr, dmem_wr_en=>mmio_dmem_wr_en,
                 dmem_rd_en=>mmio_dmem_rd_en, dmem_wr_data=>mmio_dmem_wrdata,
                 dmem_rd_data=>mmio_dmem_rddata,
                 uart_addr=>uart_addr, uart_wr_en=>uart_wr_en,
                 uart_wr_data=>uart_wr_data, uart_rd_data=>uart_rd_data,
                 gpio_addr=>gpio_addr_s, gpio_wr_en=>gpio_wr_en_s,
                 gpio_wr_data=>gpio_wr_data_s, gpio_rd_data=>gpio_rd_data_s,
                 timer_addr=>timer_addr_s, timer_wr_en=>timer_wr_en_s,
                 timer_wr_data=>timer_wr_data_s, timer_rd_data=>timer_rd_data_s,
                 irqc_addr=>irqc_addr_s, irqc_wr_en=>irqc_wr_en_s,
                 irqc_wr_data=>irqc_wr_data_s, irqc_rd_data=>irqc_rd_data_s);

    u_dcache: entity work.dcache
        port map(clk=>clk, rst=>rst,
                 cpu_addr=>mmio_dmem_addr, cpu_rd_en=>mmio_dmem_rd_en,
                 cpu_wr_en=>mmio_dmem_wr_en, cpu_wr_data=>mmio_dmem_wrdata,
                 cpu_sz=>wb_dmem_sz, cpu_rd_data=>dcache_cpu_rddat, stall_req=>dcache_stall,
                 mem_addr=>dcache_mem_addr, mem_rd_en=>dcache_mem_rd,
                 mem_wr_en=>dcache_mem_wr, mem_wr_data=>dcache_mem_wrdat,
                 mem_sz=>dcache_mem_sz, mem_rd_data=>dcache_mem_rddat);

    u_dmem: entity work.data_memory
        port map(clk=>clk, wr_en=>dcache_mem_wr, addr=>dcache_mem_addr,
                 wr_data=>dcache_mem_wrdat, sz=>dcache_mem_sz,
                 rd_en=>dcache_mem_rd, rd_data=>dcache_mem_rddat);

    u_uart: entity work.uart_periph
        port map(clk=>clk, rst=>rst, addr=>uart_addr, wr_en=>uart_wr_en,
                 wr_data=>uart_wr_data, rd_data=>uart_rd_data,
                 tx_irq=>open, rx_irq=>open,
                 tx_byte=>uart_tx_byte, tx_valid=>uart_tx_valid);

    u_gpio: entity work.gpio_periph
        port map(clk=>clk, rst=>rst, addr=>gpio_addr_s, wr_en=>gpio_wr_en_s,
                 wr_data=>gpio_wr_data_s, rd_data=>gpio_rd_data_s,
                 gpio_out=>gpio_out, gpio_in=>gpio_in,
                 gpio_dir=>gpio_dir, gpio_irq=>gpio_irq_s);

    u_timer: entity work.timer_periph
        port map(clk=>clk, rst=>rst, addr=>timer_addr_s, wr_en=>timer_wr_en_s,
                 wr_data=>timer_wr_data_s, rd_data=>timer_rd_data_s, timer_irq=>timer_irq_s);

    u_irqc: entity work.interrupt_ctrl
        port map(clk=>clk, rst=>rst, irq_lines=>all_irq_lines, mie=>mie_s,
                 mepc_in=>fetch_pc, mepc_out=>irq_mepc_out, mcause_out=>irq_mcause,
                 reg_addr=>irqc_addr_s, reg_wr_en=>irqc_wr_en_s,
                 reg_wr_data=>irqc_wr_data_s, reg_rd_data=>irqc_rd_data_s,
                 irq_taken=>irq_taken, mtvec=>irq_mtvec);

    -- ── Stimulus ─────────────────────────────────────────────
    stim: process
        variable cycle_count : integer := 0;
    begin
        report "============================================" severity note;
        report "  MRKK-32 Full System Simulation" severity note;
        report "  Program: Fibonacci fib(0)..fib(9)" severity note;
        report "============================================" severity note;

        rst <= '1';
        for i in 1 to 4 loop
            wait until rising_edge(clk); wait for 1 ns;
        end loop;
        rst <= '0';
        report ">> Reset released. CPU executing." severity note;

        -- Run 400 cycles (more than enough for 10 fib iterations)
        for i in 1 to 400 loop
            wait until rising_edge(clk); wait for 1 ns;
            cycle_count := cycle_count + 1;
        end loop;

        report ">> " & integer'image(cycle_count) & " cycles elapsed." severity note;

        -- Verify: watch that stores happened by monitoring data memory writes
        -- (The write monitor below catches these live during simulation)
        report "============================================" severity note;
        report "  Simulation complete. Check STORE log above." severity note;
        report "============================================" severity note;
        wait;
    end process;

    -- ── Execution monitor: watch register file writes ──────────
    -- x2 = current fib value (b), x3 = temp (a+b)
    -- Each time x3 is written we have a new Fibonacci number
    exec_monitor: process(clk)
        variable val : integer;
    begin
        if rising_edge(clk) then
            if rf_wr_en = '1' and rf_rd_addr = "00011" then  -- x3 written
                val := to_integer(unsigned(rf_wr_data));
                report "COMPUTE: x3 (fib temp) = " & integer'image(val) severity note;
            end if;
            -- Also watch x5 (store pointer) advancing
            -- and SW completions via rf not written (stores don't write RF)
            -- Primary check: catch ADD x3,x1,x2 result via RF write
        end if;
    end process;

    -- ── Store checker: unique per address using a latch flag ───
    store_checker: process
        type seen_t is array(0 to 9) of boolean;
        variable seen : seen_t := (others => false);
        variable addr_i : integer;
        variable val_i  : integer;
        variable exp_i  : integer;

        

    begin
        wait until rising_edge(clk);
        -- wait for reset done
        loop
            wait until rising_edge(clk);
            if rst = '0' and wb_dmem_wr_en = '1'
               and to_integer(unsigned(wb_alu_result)) < 40 then
                addr_i := to_integer(unsigned(wb_alu_result));
                val_i  := to_integer(unsigned(wb_rs2_data));
                if (addr_i mod 4) = 0 then
                    exp_i := addr_i / 4;
                    if exp_i <= 9 and not seen(exp_i) then
                        seen(exp_i) := true;
                        if val_i = FIB(exp_i) then
                            report "CORRECT: SW mem[" & integer'image(addr_i) &
                                "] = fib(" & integer'image(exp_i) & ") = " &
                                integer'image(val_i) severity note;
                        else
                            report "WRONG: SW mem[" & integer'image(addr_i) &
                                "] = " & integer'image(val_i) &
                                " expected " & integer'image(FIB(exp_i))
                                severity error;
                        end if;
                    end if;
                end if;
            end if;
        end loop;
    end process;

end architecture sim;