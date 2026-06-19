-- ============================================================
--  MRKK-32 CPU  —  Immediate Generator
--  Decodes all 5 RV32I immediate formats from the instruction
--
--  Format   Instructions              imm bits from instr
--  ──────   ────────────────────────  ───────────────────────
--  I-type   ADDI, LW, JALR, etc.     [31:20]
--  S-type   SW, SH, SB               [31:25] [11:7]
--  B-type   BEQ, BNE, BLT, etc.      [31][7][30:25][11:8]
--  U-type   LUI, AUIPC               [31:12]
--  J-type   JAL                      [31][19:12][20][30:21]
--
--  All immediates are sign-extended to 32 bits.
--  imm_sel driven by the decoder control unit.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;

entity immediate_gen is
    port (
        instr   : in  std_logic_vector(31 downto 0);  -- full instruction word
        imm_sel : in  std_logic_vector(2 downto 0);   -- format select
        imm_out : out std_logic_vector(31 downto 0)   -- sign-extended immediate
    );
end entity immediate_gen;

architecture rtl of immediate_gen is

    -- imm_sel encoding
    constant IMM_I : std_logic_vector(2 downto 0) := "000";
    constant IMM_S : std_logic_vector(2 downto 0) := "001";
    constant IMM_B : std_logic_vector(2 downto 0) := "010";
    constant IMM_U : std_logic_vector(2 downto 0) := "011";
    constant IMM_J : std_logic_vector(2 downto 0) := "100";

    signal sign : std_logic;  -- sign bit = instr(31) always

begin

    sign <= instr(31);

    process(instr, imm_sel, sign)
    begin
        case imm_sel is

            -- ── I-type: bits [31:20], sign-extend ──────────
            when IMM_I =>
                imm_out <= (31 downto 12 => sign) & instr(31 downto 20);

            -- ── S-type: [31:25][11:7], sign-extend ─────────
            when IMM_S =>
                imm_out <= (31 downto 12 => sign)
                         & instr(31 downto 25)
                         & instr(11 downto 7);

            -- ── B-type: [31][7][30:25][11:8] << 1 ──────────
            -- bit 0 is always 0 (2-byte aligned branch offset)
            when IMM_B =>
                imm_out <= (31 downto 13 => sign)
                         & sign
                         & instr(7)
                         & instr(30 downto 25)
                         & instr(11 downto 8)
                         & '0';

            -- ── U-type: [31:12] << 12, zero low 12 bits ────
            when IMM_U =>
                imm_out <= instr(31 downto 12) & (11 downto 0 => '0');

            -- ── J-type: [31][19:12][20][30:21] << 1 ─────────
            -- bit 0 always 0 (2-byte aligned jump offset)
            when IMM_J =>
                imm_out <= (31 downto 21 => sign)
                         & sign
                         & instr(19 downto 12)
                         & instr(20)
                         & instr(30 downto 21)
                         & '0';

            when others =>
                imm_out <= (others => '0');

        end case;
    end process;

end architecture rtl;