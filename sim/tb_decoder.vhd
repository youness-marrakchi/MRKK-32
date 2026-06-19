-- ============================================================
--  MRKK-32  —  Decoder Testbench
--  One real encoded instruction per opcode group.
--  Verifies the key control signals for each.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_decoder is
end entity tb_decoder;

architecture sim of tb_decoder is

    signal instr     : std_logic_vector(31 downto 0) := (others => '0');
    signal alu_sel   : std_logic_vector(2 downto 0);
    signal alu_sub   : std_logic;
    signal alu_arith : std_logic;
    signal alu_src   : std_logic;
    signal imm_sel   : std_logic_vector(2 downto 0);
    signal reg_wr    : std_logic;
    signal mem_rd    : std_logic;
    signal mem_wr    : std_logic;
    signal mem_sz    : std_logic_vector(1 downto 0);
    signal mem_sx    : std_logic;
    signal branch    : std_logic;
    signal jump      : std_logic;
    signal lui       : std_logic;
    signal auipc     : std_logic;
    signal mul_op    : std_logic;
    signal csr_op    : std_logic;
    signal illegal   : std_logic;

    -- helper: check a single std_logic
    procedure chk1(sig : std_logic; exp : std_logic; name : string) is
    begin
        assert sig = exp
            report "FAIL: " & name & "  got=" & std_logic'image(sig) &
                   "  exp=" & std_logic'image(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;

    function slv_to_string(slv : std_logic_vector) return string is
    variable result : string(1 to slv'length);
    variable idx    : integer := 1;
    begin
        for i in slv'reverse_range loop
            result(idx) := std_logic'image(slv(i))(2);
            idx := idx + 1;
        end loop;
        return result;
    end;

    procedure chk3(sig : std_logic_vector(2 downto 0);
                   exp : std_logic_vector(2 downto 0); name : string) is
    begin
        assert sig = exp
            report "FAIL: " & name &
                " got=" & slv_to_string(sig) &
                " exp=" & slv_to_string(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;

begin

    dut: entity work.decoder
        port map(
            instr     => instr,
            alu_sel   => alu_sel,
            alu_sub   => alu_sub,
            alu_arith => alu_arith,
            alu_src   => alu_src,
            imm_sel   => imm_sel,
            reg_wr    => reg_wr,
            mem_rd    => mem_rd,
            mem_wr    => mem_wr,
            mem_sz    => mem_sz,
            mem_sx    => mem_sx,
            branch    => branch,
            jump      => jump,
            lui       => lui,
            auipc     => auipc,
            mul_op    => mul_op,
            csr_op    => csr_op,
            illegal   => illegal
        );

    stim: process
    begin
        report "=== MRKK-32 DECODER TESTBENCH START ===" severity note;
        wait for 5 ns;

        -- ── LUI x1, 0x12345 ──────────────────────────────
        -- 0001_0010_0011_0100_0101_0000_1011_0111
        instr <= x"123450B7"; wait for 5 ns;
        report "-- LUI --" severity note;
        chk1(lui,    '1', "LUI: lui flag");
        chk1(reg_wr, '1', "LUI: reg_wr");
        chk1(illegal,'0', "LUI: not illegal");
        chk3(imm_sel,"011","LUI: imm_sel=U");

        -- ── AUIPC x1, 0x10000 ────────────────────────────
        -- AUIPC x1, 1  → 0x00001097
        instr <= x"00001097"; wait for 5 ns;
        report "-- AUIPC --" severity note;
        chk1(auipc,  '1', "AUIPC: auipc flag");
        chk1(reg_wr, '1', "AUIPC: reg_wr");
        chk3(imm_sel,"011","AUIPC: imm_sel=U");

        -- ── JAL x1, +4 ───────────────────────────────────
        -- JAL x1(rd=00001) offset=+4: 0x004000EF
        instr <= x"004000EF"; wait for 5 ns;
        report "-- JAL --" severity note;
        chk1(jump,   '1', "JAL: jump flag");
        chk1(reg_wr, '1', "JAL: reg_wr (saves PC+4)");
        chk3(imm_sel,"100","JAL: imm_sel=J");
        chk1(illegal,'0', "JAL: not illegal");

        -- ── JALR x0, x1, 0 ───────────────────────────────
        -- 0000_0000_0000_0000_1000_0000_0110_0111
        instr <= x"00008067"; wait for 5 ns;
        report "-- JALR --" severity note;
        chk1(jump,   '1', "JALR: jump flag");
        chk1(alu_src,'1', "JALR: alu_src=imm");
        chk3(imm_sel,"000","JALR: imm_sel=I");

        -- ── BEQ x1, x2, +8 ───────────────────────────────
        instr <= x"00208463"; wait for 5 ns;
        report "-- BEQ --" severity note;
        chk1(branch, '1', "BEQ: branch flag");
        chk1(reg_wr, '0', "BEQ: no reg_wr");
        chk1(alu_sub,'1', "BEQ: alu_sub for compare");
        chk3(imm_sel,"010","BEQ: imm_sel=B");

        -- ── LW x3, 0(x1) ─────────────────────────────────
        -- 0000_0000_0000_0000_1010_0001_1000_0011
        instr <= x"0000A183"; wait for 5 ns;
        report "-- LW --" severity note;
        chk1(mem_rd, '1', "LW: mem_rd");
        chk1(reg_wr, '1', "LW: reg_wr");
        chk1(alu_src,'1', "LW: alu_src=imm");
        chk3(imm_sel,"000","LW: imm_sel=I");
        chk1(illegal,'0', "LW: not illegal");

        -- ── LB x3, 0(x1) — byte, sign-extend ─────────────
        instr <= x"00008183"; wait for 5 ns;
        report "-- LB --" severity note;
        chk1(mem_rd, '1', "LB: mem_rd");
        chk1(mem_sx, '1', "LB: mem_sx sign-extend");

        -- ── LBU x3, 0(x1) — byte, zero-extend ────────────
        instr <= x"0000C183"; wait for 5 ns;
        report "-- LBU --" severity note;
        chk1(mem_rd, '1', "LBU: mem_rd");
        chk1(mem_sx, '0', "LBU: mem_sx zero-extend");

        -- ── SW x2, 0(x1) ─────────────────────────────────
        -- 0000_0000_0010_0000_1010_0000_0010_0011
        instr <= x"0020A023"; wait for 5 ns;
        report "-- SW --" severity note;
        chk1(mem_wr, '1', "SW: mem_wr");
        chk1(reg_wr, '0', "SW: no reg_wr");
        chk1(alu_src,'1', "SW: alu_src=imm");
        chk3(imm_sel,"001","SW: imm_sel=S");

        -- ── ADDI x1, x0, 5 ───────────────────────────────
        instr <= x"00500093"; wait for 5 ns;
        report "-- ADDI --" severity note;
        chk1(reg_wr, '1', "ADDI: reg_wr");
        chk1(alu_src,'1', "ADDI: alu_src=imm");
        chk3(alu_sel,"000","ADDI: alu_sel=ADD");
        chk1(alu_sub,'0', "ADDI: not sub");

        -- ── SRAI x1, x1, 2 ───────────────────────────────
        -- funct7=0100000 funct3=101 → arithmetic right shift
        instr <= x"4020D093"; wait for 5 ns;
        report "-- SRAI --" severity note;
        chk1(alu_arith,'1',"SRAI: alu_arith");
        chk3(alu_sel,"101",  "SRAI: alu_sel=101");

        -- ── ADD x3, x1, x2 ───────────────────────────────
        instr <= x"002081B3"; wait for 5 ns;
        report "-- ADD --" severity note;
        chk1(reg_wr, '1', "ADD: reg_wr");
        chk1(alu_src,'0', "ADD: alu_src=reg");
        chk3(alu_sel,"000","ADD: alu_sel=ADD");
        chk1(alu_sub,'0', "ADD: not sub");
        chk1(mul_op, '0', "ADD: not mul");

        -- ── SUB x3, x1, x2 ───────────────────────────────
        -- funct7=0100000 funct3=000
        instr <= x"402081B3"; wait for 5 ns;
        report "-- SUB --" severity note;
        chk1(alu_sub,'1', "SUB: alu_sub");
        chk1(mul_op, '0', "SUB: not mul");

        -- ── MUL x3, x1, x2 (RV32M) ───────────────────────
        -- funct7=0000001 funct3=000
        instr <= x"022081B3"; wait for 5 ns;
        report "-- MUL --" severity note;
        chk1(mul_op, '1', "MUL: mul_op");
        chk1(reg_wr, '1', "MUL: reg_wr");
        chk1(illegal,'0', "MUL: not illegal");

        -- ── DIV x3, x1, x2 (RV32M) ───────────────────────
        -- funct7=0000001 funct3=100
        instr <= x"022081B3";
        instr(14 downto 12) <= "100"; wait for 5 ns;
        report "-- DIV --" severity note;
        chk1(mul_op, '1', "DIV: mul_op");

        -- ── Illegal opcode ────────────────────────────────
        instr <= x"FFFFFFFF"; wait for 5 ns;
        report "-- Illegal --" severity note;
        chk1(illegal,'1', "Illegal: illegal flag set");

        -- ── FENCE (NOP) ───────────────────────────────────
        instr <= x"0FF0000F"; wait for 5 ns;
        report "-- FENCE --" severity note;
        chk1(illegal,'0', "FENCE: not illegal");
        chk1(mem_wr, '0', "FENCE: no mem_wr");
        chk1(reg_wr, '0', "FENCE: no reg_wr");

        -- ── ECALL ─────────────────────────────────────────
        instr <= x"00000073"; wait for 5 ns;
        report "-- ECALL --" severity note;
        chk1(csr_op, '1', "ECALL: csr_op");
        chk1(illegal,'0', "ECALL: not illegal");

        report "=== MRKK-32 DECODER TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;

end architecture sim;