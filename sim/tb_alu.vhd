-- ============================================================
--  MRKK-32  —  ALU Testbench
--  Tests all 10 operations with corner cases
--  Expected results verified by assertion
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_alu is
end entity tb_alu;

architecture sim of tb_alu is

    -- DUT ports
    signal a, b      : std_logic_vector(31 downto 0) := (others => '0');
    signal alu_sel   : std_logic_vector(2 downto 0)  := "000";
    signal alu_sub   : std_logic := '0';
    signal alu_arith : std_logic := '0';
    signal result    : std_logic_vector(31 downto 0);
    signal zero      : std_logic;
    signal negative  : std_logic;
    signal overflow  : std_logic;

    -- test helpers
    procedure check(
        signal res  : in std_logic_vector(31 downto 0);
        expected    : in integer;
        test_name   : in string) is
    begin
        assert to_integer(signed(res)) = expected
            report "FAIL: " & test_name &
                   "  got=" & integer'image(to_integer(signed(res))) &
                   "  expected=" & integer'image(expected)
            severity error;
        report "PASS: " & test_name severity note;
    end procedure;

    procedure check_u(
        signal res  : in std_logic_vector(31 downto 0);
        expected    : in std_logic_vector(31 downto 0);
        test_name   : in string) is
    begin
        assert res = expected
            report "FAIL: " & test_name
            severity error;
        report "PASS: " & test_name severity note;
    end procedure;

begin

    -- ── Instantiate DUT ──────────────────────────────────────
    dut: entity work.alu
        port map(
            a         => a,
            b         => b,
            alu_sel   => alu_sel,
            alu_sub   => alu_sub,
            alu_arith => alu_arith,
            result    => result,
            zero      => zero,
            negative  => negative,
            overflow  => overflow
        );

    -- ── Stimulus ─────────────────────────────────────────────
    stim: process
    begin
        report "=== MRKK-32 ALU TESTBENCH START ===" severity note;
        wait for 10 ns;

        -- ── ADD ──────────────────────────────────────────────
        alu_sel <= "000"; alu_sub <= '0'; alu_arith <= '0';
        a <= x"00000005"; b <= x"00000003"; wait for 10 ns;
        check(result, 8,  "ADD  5+3=8");

        a <= x"7FFFFFFF"; b <= x"00000001"; wait for 10 ns;
        report "ADD overflow flag = " & std_logic'image(overflow) severity note;

        a <= x"FFFFFFFE"; b <= x"00000002"; wait for 10 ns;
        check(result, 0, "ADD wraps to 0");
        assert zero = '1' report "FAIL: zero flag on ADD wrap" severity error;

        -- ── SUB ──────────────────────────────────────────────
        alu_sel <= "000"; alu_sub <= '1';
        a <= x"0000000A"; b <= x"00000003"; wait for 10 ns;
        check(result, 7, "SUB  10-3=7");

        a <= x"00000000"; b <= x"00000001"; wait for 10 ns;
        check(result, -1, "SUB  0-1=-1 (wrap)");
        assert negative = '1' report "FAIL: negative flag on SUB" severity error;

        a <= x"00000005"; b <= x"00000005"; wait for 10 ns;
        assert zero = '1' report "FAIL: zero flag on SUB equal" severity error;
        report "PASS: SUB zero flag" severity note;

        -- ── SLL ──────────────────────────────────────────────
        alu_sel <= "001"; alu_sub <= '0';
        a <= x"00000001"; b <= x"00000004"; wait for 10 ns;
        check(result, 16, "SLL  1<<4=16");

        a <= x"00000001"; b <= x"0000001F"; wait for 10 ns;  -- shift by 31
        check_u(result, x"80000000", "SLL  1<<31");

        -- ── SLT (signed) ─────────────────────────────────────
        alu_sel <= "010";
        a <= x"00000001"; b <= x"00000002"; wait for 10 ns;
        check(result, 1, "SLT  1<2=1");

        a <= x"FFFFFFFF"; b <= x"00000001"; wait for 10 ns; -- -1 < 1
        check(result, 1, "SLT  -1<1=1 (signed)");

        a <= x"00000005"; b <= x"00000005"; wait for 10 ns;
        check(result, 0, "SLT  5<5=0");

        -- ── SLTU (unsigned) ──────────────────────────────────
        alu_sel <= "011";
        a <= x"FFFFFFFF"; b <= x"00000001"; wait for 10 ns; -- 0xFFFF... not < 1
        check(result, 0, "SLTU 0xFFFFFFFF < 1 = 0 (unsigned)");

        a <= x"00000001"; b <= x"FFFFFFFF"; wait for 10 ns;
        check(result, 1, "SLTU 1 < 0xFFFFFFFF = 1 (unsigned)");

        -- ── XOR ──────────────────────────────────────────────
        alu_sel <= "100";
        a <= x"FF00FF00"; b <= x"00FF00FF"; wait for 10 ns;
        check_u(result, x"FFFFFFFF", "XOR  FF00FF00^00FF00FF=FFFFFFFF");

        a <= x"ABCDEF12"; b <= x"ABCDEF12"; wait for 10 ns;
        assert zero = '1' report "FAIL: XOR self=0 zero flag" severity error;
        report "PASS: XOR self=0 zero flag" severity note;

        -- ── SRL ──────────────────────────────────────────────
        alu_sel <= "101"; alu_arith <= '0';
        a <= x"80000000"; b <= x"00000001"; wait for 10 ns;
        check_u(result, x"40000000", "SRL  0x80000000>>1=0x40000000 (logical)");

        -- ── SRA ──────────────────────────────────────────────
        alu_sel <= "101"; alu_arith <= '1';
        a <= x"80000000"; b <= x"00000001"; wait for 10 ns;
        check_u(result, x"C0000000", "SRA  0x80000000>>1=0xC0000000 (arith)");

        a <= x"7FFFFFFF"; b <= x"00000001"; wait for 10 ns;
        check_u(result, x"3FFFFFFF", "SRA  positive stays positive");

        -- ── OR ───────────────────────────────────────────────
        alu_sel <= "110"; alu_arith <= '0';
        a <= x"F0F0F0F0"; b <= x"0F0F0F0F"; wait for 10 ns;
        check_u(result, x"FFFFFFFF", "OR   F0F0|0F0F=FFFF");

        a <= x"00000000"; b <= x"00000000"; wait for 10 ns;
        assert zero = '1' report "FAIL: OR zero flag" severity error;
        report "PASS: OR zero flag" severity note;

        -- ── AND ──────────────────────────────────────────────
        alu_sel <= "111";
        a <= x"FF00FF00"; b <= x"F0F0F0F0"; wait for 10 ns;
        check_u(result, x"F000F000", "AND  FF00FF00&F0F0F0F0=F000F000");

        a <= x"FFFFFFFF"; b <= x"00000000"; wait for 10 ns;
        assert zero = '1' report "FAIL: AND zero flag" severity error;
        report "PASS: AND zero flag" severity note;

        report "=== MRKK-32 ALU TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;

end architecture sim;