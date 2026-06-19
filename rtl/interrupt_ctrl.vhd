-- ============================================================
--  MRKK-32 CPU  —  Fixed-Priority Interrupt Controller
--
--  4 external interrupt lines: IRQ0 (highest) > IRQ3 (lowest)
--
--  Registers (memory-mapped, see MMIO map):
--    IRQ_ENABLE  [3:0]  per-line enable mask
--    IRQ_PENDING [3:0]  set by hardware, cleared by SW write
--    IRQ_CAUSE   [1:0]  index of highest pending+enabled IRQ
--
--  CSR interface (minimal — mepc + mstatus.MIE):
--    mie         : machine interrupt enable (global)
--    mepc_in     : PC of interrupted instruction (from pipeline)
--    mepc_out    : saved PC for MRET
--    mcause_out  : interrupt cause (IRQ index, bit 31 set)
--
--  irq_taken    : '1' for one cycle when interrupt is accepted
--                 pipeline must flush and redirect PC to mtvec
--  mtvec        : fixed trap vector base address (0x00000100)
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interrupt_ctrl is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- External interrupt lines (active high, level)
        irq_lines   : in  std_logic_vector(3 downto 0);

        -- CSR / pipeline interface
        mie         : in  std_logic;                      -- global interrupt enable
        mepc_in     : in  std_logic_vector(31 downto 0);  -- PC to save on trap
        mepc_out    : out std_logic_vector(31 downto 0);  -- saved PC (for MRET)
        mcause_out  : out std_logic_vector(31 downto 0);  -- cause register

        -- MMIO register interface
        reg_addr    : in  std_logic_vector(1 downto 0);   -- 00=enable 01=pending 10=cause
        reg_wr_en   : in  std_logic;
        reg_wr_data : in  std_logic_vector(3 downto 0);
        reg_rd_data : out std_logic_vector(3 downto 0);

        -- Trap control
        irq_taken   : out std_logic;                      -- accept interrupt this cycle
        
        mtvec       : out std_logic_vector(31 downto 0)   -- trap handler address
    );
end entity interrupt_ctrl;

architecture rtl of interrupt_ctrl is

    signal irq_enable  : std_logic_vector(3 downto 0) := (others => '0');
    signal irq_pending : std_logic_vector(3 downto 0) := (others => '0');

    signal active      : std_logic_vector(3 downto 0);  -- enabled AND pending
    signal irq_cause   : integer range 0 to 3 := 0;
    signal any_active  : std_logic;
    signal mepc_reg    : std_logic_vector(31 downto 0) := (others => '0');

    -- Fixed trap vector
    constant MTVEC_ADDR : std_logic_vector(31 downto 0) := x"00000100";

    signal irq_taken_i : std_logic;

begin

    mtvec <= MTVEC_ADDR;

    -- ── Pending: set by hardware, cleared by SW write ─────────
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                irq_pending <= (others => '0');
                irq_enable  <= (others => '0');
                mepc_reg    <= (others => '0');
            else
                -- Hardware sets pending bits from IRQ lines
                irq_pending <= irq_pending or irq_lines;

                -- Software can clear pending bits (write 1 to clear)
                if reg_wr_en = '1' and reg_addr = "01" then
                    irq_pending <= (irq_pending or irq_lines) and (not reg_wr_data);
                end if;

                -- IRQ enable register write
                if reg_wr_en = '1' and reg_addr = "00" then
                    irq_enable <= reg_wr_data;
                end if;

                -- Save PC on interrupt acceptance
                if irq_taken_i = '1' then
                    mepc_reg <= mepc_in;
                end if;
            end if;
        end if;
    end process;

    -- ── Active = pending AND enabled ─────────────────────────
    active    <= irq_pending and irq_enable;
    any_active <= '1' when active /= "0000" else '0';

    -- ── Fixed priority encoder (IRQ0 = highest) ──────────────
    irq_cause <=
        0 when active(0) = '1' else
        1 when active(1) = '1' else
        2 when active(2) = '1' else
        3;

    -- ── Accept interrupt when globally enabled + active ───────
    irq_taken_i <= mie and any_active;
    irq_taken   <= irq_taken_i;

    -- ── CSR outputs ──────────────────────────────────────────
    mepc_out   <= mepc_reg;
    -- mcause: bit 31 set = interrupt, bits [1:0] = cause index
    mcause_out <= x"80000000" or
                  std_logic_vector(to_unsigned(irq_cause, 32));

    -- ── MMIO register reads ──────────────────────────────────
    with reg_addr select reg_rd_data <=
        irq_enable              when "00",
        irq_pending             when "01",
        "00" & std_logic_vector(to_unsigned(irq_cause, 2)) when "10",
        (others => '0')         when others;

end architecture rtl;