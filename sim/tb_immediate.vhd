-- ============================================================
--  MRKK-32  —  Immediate Generator Testbench
--  Uses real RV32I instruction encodings for each format.
--  Expected values hand-verified against the ISA spec.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_immediate_gen is
end entity tb_immediate_gen;

architecture sim of tb_immediate_gen is

    signal instr   : std_logic_vector(31 downto 0) := (others => '0');
    signal imm_sel : std_logic_vector(2 downto 0)  := "000";
    signal imm_out : std_logic_vector(31 downto 0);

    function slv_to_string(slv : std_logic_vector) return string is
    variable result : string(1 to slv'length);
    variable idx    : integer := 1;
    begin
        for i in slv'reverse_range loop
            result(idx) := std_logic'image(slv(i))(2);
            idx := idx + 1;
        end loop;
        return result;
    end function;

    procedure check(
        signal   sig  : in std_logic_vector(31 downto 0);
        constant exp  : in std_logic_vector(31 downto 0);
        constant name : in string) is
    begin
        assert sig = exp
            report "FAIL: " & name &
                " got=" & slv_to_string(sig) &
                " exp=" & slv_to_string(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;

begin

    dut: entity work.immediate_gen
        port map(instr => instr, imm_sel => imm_sel, imm_out => imm_out);

    stim: process
    begin
        report "=== MRKK-32 IMMEDIATE GEN TESTBENCH START ===" severity note;
        wait for 5 ns;

        -- ────────────────────────────────────────────────────
        -- I-TYPE  :  ADDI x1, x0, 5    → imm = +5
        --   instr = 0000_0000_0101_0000_0000_0000_1001_0011
        --           imm[11:0]=0x005  rs1=x0  funct3=000  rd=x1  op=0010011
        -- ────────────────────────────────────────────────────
        imm_sel <= "000";
        instr   <= x"00500093";
        wait for 5 ns;
        check(imm_out, x"00000005", "I-type ADDI x1,x0,5  imm=+5");

        -- I-TYPE negative:  ADDI x1, x0, -1  → imm = -1
        --   imm[11:0] = 0xFFF  → sign-extend to 0xFFFFFFFF
        instr <= x"FFF00093";
        wait for 5 ns;
        check(imm_out, x"FFFFFFFF", "I-type ADDI x1,x0,-1 imm=-1");

        -- I-TYPE max positive:  imm = 2047 (0x7FF)
        instr <= x"7FF00093";
        wait for 5 ns;
        check(imm_out, x"000007FF", "I-type max positive imm=+2047");

        -- I-TYPE max negative:  imm = -2048 (0x800)
        instr <= x"80000093";
        wait for 5 ns;
        check(imm_out, x"FFFFF800", "I-type max negative imm=-2048");

        -- ────────────────────────────────────────────────────
        -- S-TYPE  :  SW x2, 8(x1)    → imm = +8
        --   instr = 0000_0000_0010_0000_1010_0100_0010_0011
        --           imm[11:5]=0x00  rs2=x2  rs1=x1  funct3=010  imm[4:0]=01000  op=0100011
        -- ────────────────────────────────────────────────────
        imm_sel <= "001";
        instr   <= x"0020A423";
        wait for 5 ns;
        check(imm_out, x"00000008", "S-type SW  x2,8(x1)  imm=+8");

        -- S-TYPE negative:  SW x2, -4(x1)  → imm = -4
        --   imm = 0xFFC  split: [11:5]=1111111  [4:0]=11100
        instr <= x"FE20AE23";
        wait for 5 ns;
        check(imm_out, x"FFFFFFFC", "S-type SW  x2,-4(x1) imm=-4");

        -- ────────────────────────────────────────────────────
        -- B-TYPE  :  BEQ x1, x2, +8   → imm = +8
        --   offset +8: bit[12]=0 bit[11]=0 bits[10:5]=000001 bits[4:1]=0000
        --   instr = 0000_0000_0010_0000_1000_0100_0110_0011
        -- ────────────────────────────────────────────────────
        imm_sel <= "010";
        instr   <= x"00208463";
        wait for 5 ns;
        check(imm_out, x"00000008", "B-type BEQ x1,x2,+8  imm=+8");

        -- B-TYPE negative:  BNE x0, x0, -4  → imm = -4
        --   offset -4 = 0x1FFC: bit[12]=1 bit[11]=1 bits[10:5]=111111 bits[4:1]=1110
        --   instr: 31=1,30:25=111111,24:20=00000,19:15=00000,14:12=001,11:8=1110,7=1,6:0=1100011
        instr <= x"FE000EE3";
        wait for 5 ns;
        check(imm_out, x"FFFFFFFC", "B-type BNE x0,x0,-4  imm=-4");

        -- ────────────────────────────────────────────────────
        -- U-TYPE  :  LUI x1, 0xABCDE   → imm = 0xABCDE000
        --   instr = 1010_1011_1100_1101_1110_0000_1011_0111
        -- ────────────────────────────────────────────────────
        imm_sel <= "011";
        instr   <= x"ABCDE0B7";
        wait for 5 ns;
        check(imm_out, x"ABCDE000", "U-type LUI x1,0xABCDE imm=0xABCDE000");

        -- U-TYPE zero:  LUI x1, 0
        instr <= x"000000B7";
        wait for 5 ns;
        check(imm_out, x"00000000", "U-type LUI x1,0       imm=0");

        -- ────────────────────────────────────────────────────
        -- J-TYPE  :  JAL x0, +4       → imm = +4
        --   offset +4: all zero except bit[2]=1
        --   bit mapping: [31]=0 [19:12]=00000000 [20]=0 [30:21]=0000000010
        --   instr = 0000_0000_0100_0000_0000_0000_0110_1111
        -- ────────────────────────────────────────────────────
        imm_sel <= "100";
        instr   <= x"0040006F";
        wait for 5 ns;
        check(imm_out, x"00000004", "J-type JAL x0,+4      imm=+4");

        -- J-TYPE negative:  JAL x0, -4  → imm = -4 = 0xFFFFFFFC
        --   [31]=1 [19:12]=11111111 [20]=1 [30:21]=1111111110
        instr <= x"FFDFF06F";
        wait for 5 ns;
        check(imm_out, x"FFFFFFFC", "J-type JAL x0,-4      imm=-4");

        report "=== MRKK-32 IMMEDIATE GEN TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;

end architecture sim;