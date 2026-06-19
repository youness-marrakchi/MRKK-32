-- ============================================================
--  MRKK-32  —  Register File Testbench
--  Tests: basic write/read, x0 hardwiring, dual-port,
--         write-then-read forwarding, full bank walk
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_register_file is
end entity tb_register_file;

architecture sim of tb_register_file is

    signal clk      : std_logic := '0';
    signal wr_en    : std_logic := '0';
    signal rd_addr  : std_logic_vector(4 downto 0) := (others => '0');
    signal wr_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal rs1_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal rs2_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal rs1_data : std_logic_vector(31 downto 0);
    signal rs2_data : std_logic_vector(31 downto 0);

    constant CLK_P : time := 10 ns;

    procedure check32(
        signal   sig  : in std_logic_vector(31 downto 0);
        constant exp  : in std_logic_vector(31 downto 0);
        constant name : in string) is
    begin
        assert sig = exp
            report "FAIL: " & name
            severity error;
        report "PASS: " & name severity note;
    end procedure;

begin

    clk <= not clk after CLK_P / 2;

    dut: entity work.register_file
        port map(
            clk      => clk,
            wr_en    => wr_en,
            rd_addr  => rd_addr,
            wr_data  => wr_data,
            rs1_addr => rs1_addr,
            rs2_addr => rs2_addr,
            rs1_data => rs1_data,
            rs2_data => rs2_data
        );

    stim: process
    begin
        report "=== MRKK-32 REGISTER FILE TESTBENCH START ===" severity note;

        -- ── x0 always reads 0, even after write attempt ────
        wr_en   <= '1';
        rd_addr <= "00000";
        wr_data <= x"DEADBEEF";
        wait until rising_edge(clk); wait for 1 ns;
        wr_en <= '0';
        rs1_addr <= "00000";
        rs2_addr <= "00000";
        wait for 1 ns;
        check32(rs1_data, x"00000000", "x0 always 0 after write attempt (rs1)");
        check32(rs2_data, x"00000000", "x0 always 0 after write attempt (rs2)");

        -- ── Basic write to x1 then read back ──────────────
        wr_en   <= '1';
        rd_addr <= "00001";
        wr_data <= x"AABBCCDD";
        wait until rising_edge(clk); wait for 1 ns;
        wr_en <= '0';
        rs1_addr <= "00001";
        wait for 1 ns;
        check32(rs1_data, x"AABBCCDD", "write x1=0xAABBCCDD, read rs1");

        -- ── Write x2, read both x1 and x2 simultaneously ──
        wr_en   <= '1';
        rd_addr <= "00010";
        wr_data <= x"11223344";
        wait until rising_edge(clk); wait for 1 ns;
        wr_en    <= '0';
        rs1_addr <= "00001";
        rs2_addr <= "00010";
        wait for 1 ns;
        check32(rs1_data, x"AABBCCDD", "dual port: rs1=x1 correct");
        check32(rs2_data, x"11223344", "dual port: rs2=x2 correct");

        -- ── Write-then-read forwarding ─────────────────────
        -- Write x3=0x55667788 and simultaneously read x3 on rs1
        wr_en    <= '1';
        rd_addr  <= "00011";
        wr_data  <= x"55667788";
        rs1_addr <= "00011";                -- rs1 reads x3 same cycle as write
        rs2_addr <= "00001";                -- rs2 reads x1 (unchanged)
        wait for 1 ns;                      -- async read, no clock needed
        check32(rs1_data, x"55667788", "write-then-read forward on rs1");
        check32(rs2_data, x"AABBCCDD", "rs2 unaffected by x3 write");
        wait until rising_edge(clk); wait for 1 ns;
        wr_en <= '0';

        -- ── Write all registers x1–x31, verify each ───────
        report "--- Walking all 31 writable registers ---" severity note;
        for i in 1 to 31 loop
            wr_en   <= '1';
            rd_addr <= std_logic_vector(to_unsigned(i, 5));
            wr_data <= std_logic_vector(to_unsigned(i, 32));
            wait until rising_edge(clk); wait for 1 ns;
            wr_en <= '0';
        end loop;

        for i in 1 to 31 loop
            rs1_addr <= std_logic_vector(to_unsigned(i, 5));
            wait for 1 ns;
            assert rs1_data = std_logic_vector(to_unsigned(i, 32))
                report "FAIL: bank walk reg x" & integer'image(i)
                severity error;
        end loop;
        report "PASS: full register bank walk x1-x31" severity note;

        -- ── x0 still 0 after bank walk ─────────────────────
        rs1_addr <= "00000";
        wait for 1 ns;
        check32(rs1_data, x"00000000", "x0 still 0 after full bank walk");

        report "=== MRKK-32 REGISTER FILE TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;

end architecture sim;