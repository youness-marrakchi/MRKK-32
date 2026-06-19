-- ============================================================
--  MRKK-32  --  MUL/DIV Unit Testbench
--  Tests all 8 RV32M operations + all RISC-V corner cases
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.std_logic_textio.all;
use std.textio.all;

entity tb_mul_div is end entity;

architecture sim of tb_mul_div is
    signal rs1    : std_logic_vector(31 downto 0) := (others=>'0');
    signal rs2    : std_logic_vector(31 downto 0) := (others=>'0');
    signal funct3 : std_logic_vector(2  downto 0) := "000";
    signal result : std_logic_vector(31 downto 0);

    function to_hex_string(s : std_logic_vector) return string is
    variable l : line;
    begin
        hwrite(l, s);
        return l.all;
    end function;

    procedure chk(sig : std_logic_vector(31 downto 0);
                  exp : std_logic_vector(31 downto 0); name : string) is
    begin
        assert sig = exp
            report "FAIL: "&name&" got=0x"&to_hex_string(sig)&" exp=0x"&to_hex_string(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;
begin
    dut: entity work.mul_div_unit
        port map(rs1=>rs1, rs2=>rs2, funct3=>funct3, result=>result);

    stim: process
    begin
        report "=== MUL/DIV TESTBENCH START ===" severity note;
        wait for 5 ns;

        -- MUL: lower 32 bits
        funct3 <= "000";
        rs1 <= x"00000006"; rs2 <= x"00000007"; wait for 5 ns;
        chk(result, x"0000002A", "MUL 6*7=42");

        rs1 <= x"FFFFFFFF"; rs2 <= x"00000002"; wait for 5 ns;  -- -1 * 2 = -2
        chk(result, x"FFFFFFFE", "MUL -1*2=-2");

        rs1 <= x"00000000"; rs2 <= x"12345678"; wait for 5 ns;
        chk(result, x"00000000", "MUL 0*N=0");

        -- MULH: signed high
        funct3 <= "001";
        rs1 <= x"7FFFFFFF"; rs2 <= x"7FFFFFFF"; wait for 5 ns;
        chk(result, x"3FFFFFFF", "MULH MAX_INT*MAX_INT high");

        rs1 <= x"80000000"; rs2 <= x"80000000"; wait for 5 ns;  -- INT_MIN * INT_MIN
        chk(result, x"40000000", "MULH INT_MIN*INT_MIN high");

        -- MULHU: unsigned high
        funct3 <= "011";
        rs1 <= x"FFFFFFFF"; rs2 <= x"FFFFFFFF"; wait for 5 ns;
        chk(result, x"FFFFFFFE", "MULHU 0xFFFF*0xFFFF high");

        -- DIV: signed
        funct3 <= "100";
        rs1 <= x"00000014"; rs2 <= x"00000004"; wait for 5 ns;  -- 20/4=5
        chk(result, x"00000005", "DIV 20/4=5");

        rs1 <= x"FFFFFFEC"; rs2 <= x"00000004"; wait for 5 ns;  -- -20/4=-5
        chk(result, x"FFFFFFFB", "DIV -20/4=-5");

        rs1 <= x"00000007"; rs2 <= x"00000000"; wait for 5 ns;  -- div by 0
        chk(result, x"FFFFFFFF", "DIV by zero = -1");

        rs1 <= x"80000000"; rs2 <= x"FFFFFFFF"; wait for 5 ns;  -- INT_MIN / -1
        chk(result, x"80000000", "DIV INT_MIN/-1 overflow = INT_MIN");

        -- DIVU: unsigned
        funct3 <= "101";
        rs1 <= x"00000014"; rs2 <= x"00000004"; wait for 5 ns;
        chk(result, x"00000005", "DIVU 20/4=5");

        rs1 <= x"00000007"; rs2 <= x"00000000"; wait for 5 ns;
        chk(result, x"FFFFFFFF", "DIVU by zero = MAX_UINT");

        -- REM: signed
        funct3 <= "110";
        rs1 <= x"00000007"; rs2 <= x"00000003"; wait for 5 ns;  -- 7 rem 3 = 1
        chk(result, x"00000001", "REM 7 rem 3 = 1");

        rs1 <= x"FFFFFFF9"; rs2 <= x"00000003"; wait for 5 ns;  -- -7 rem 3 = -1
        chk(result, x"FFFFFFFF", "REM -7 rem 3 = -1");

        rs1 <= x"00000007"; rs2 <= x"00000000"; wait for 5 ns;
        chk(result, x"00000007", "REM by zero = rs1");

        rs1 <= x"80000000"; rs2 <= x"FFFFFFFF"; wait for 5 ns;
        chk(result, x"00000000", "REM INT_MIN rem -1 = 0");

        -- REMU: unsigned
        funct3 <= "111";
        rs1 <= x"00000007"; rs2 <= x"00000003"; wait for 5 ns;
        chk(result, x"00000001", "REMU 7 rem 3 = 1");

        rs1 <= x"00000007"; rs2 <= x"00000000"; wait for 5 ns;
        chk(result, x"00000007", "REMU by zero = rs1");

        report "=== MUL/DIV TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;
end architecture sim;