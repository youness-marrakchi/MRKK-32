-- ============================================================
--  MRKK-32 CPU  —  Register File
--  32 x 32-bit registers  (x0 – x31)
--  x0 is hardwired to 0 (writes ignored, reads always 0)
--  Dual async read ports, single sync write port
--  Write-then-read: if rs == rd on same cycle, new value wins
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity register_file is
    port (
        clk      : in  std_logic;
        -- write port
        wr_en    : in  std_logic;
        rd_addr  : in  std_logic_vector(4 downto 0);   -- destination register
        wr_data  : in  std_logic_vector(31 downto 0);
        -- read port A  (rs1)
        rs1_addr : in  std_logic_vector(4 downto 0);
        rs1_data : out std_logic_vector(31 downto 0);
        -- read port B  (rs2)
        rs2_addr : in  std_logic_vector(4 downto 0);
        rs2_data : out std_logic_vector(31 downto 0)
    );
end entity register_file;

architecture rtl of register_file is

    -- register bank — index 0 is never written (x0 = 0)
    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_array := (others => (others => '0'));

begin

    -- ── Synchronous write (x0 write silently ignored) ──────
    write_proc: process(clk)
    begin
        if rising_edge(clk) then
            if wr_en = '1' and rd_addr /= "00000" then
                regs(to_integer(unsigned(rd_addr))) <= wr_data;
            end if;
        end if;
    end process;

    -- ── Asynchronous read port A (rs1) ─────────────────────
    -- write-then-read forwarding: if reading the register being written
    -- this cycle, return the new value immediately
    rs1_data <=
        (others => '0')  when rs1_addr = "00000" else
        wr_data          when (wr_en = '1' and rs1_addr = rd_addr) else
        regs(to_integer(unsigned(rs1_addr)));

    -- ── Asynchronous read port B (rs2) ─────────────────────
    rs2_data <=
        (others => '0')  when rs2_addr = "00000" else
        wr_data          when (wr_en = '1' and rs2_addr = rd_addr) else
        regs(to_integer(unsigned(rs2_addr)));

end architecture rtl;