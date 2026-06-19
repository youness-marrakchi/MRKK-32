-- ============================================================
--  MRKK-32 CPU  —  Instruction Decoder
--  Decodes every RV32I opcode + RV32M (MUL/DIV) into
--  control signals consumed by the pipeline stages.
--
--  Control signal bus (decoded outputs):
--    alu_sel    [2:0]  ALU operation select (funct3)
--    alu_sub         '1' for SUB / SRA
--    alu_arith       '1' for arithmetic shift right
--    alu_src         '0' = rs2,  '1' = immediate
--    imm_sel    [2:0]  immediate format (→ immediate_gen)
--    reg_wr          register file write enable
--    mem_rd          data memory read (load)
--    mem_wr          data memory write (store)
--    mem_sz     [1:0]  00=byte  01=half  10=word
--    mem_sx          sign-extend loaded byte/half
--    branch          instruction is a branch
--    jump            instruction is JAL/JALR
--    pc_src          '1' = take jump/branch target
--    lui             LUI: bypass ALU, write upper imm
--    auipc           AUIPC: add PC + upper imm
--    mul_op          MUL/DIV operation (RV32M)
--    csr_op          CSR operation (for interrupt support)
--    illegal         unrecognised/illegal opcode
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;

entity decoder is
    port (
        instr     : in  std_logic_vector(31 downto 0);

        -- ALU control
        alu_sel   : out std_logic_vector(2 downto 0);
        alu_sub   : out std_logic;
        alu_arith : out std_logic;
        alu_src   : out std_logic;   -- '1' = immediate operand

        -- Immediate
        imm_sel   : out std_logic_vector(2 downto 0);

        -- Register file
        reg_wr    : out std_logic;

        -- Memory
        mem_rd    : out std_logic;
        mem_wr    : out std_logic;
        mem_sz    : out std_logic_vector(1 downto 0);
        mem_sx    : out std_logic;   -- sign-extend load

        -- Branch / jump
        branch    : out std_logic;
        jump      : out std_logic;

        -- Special datapath
        lui       : out std_logic;
        auipc     : out std_logic;

        -- RV32M
        mul_op    : out std_logic;

        -- CSR (for interrupt mepc/mcause)
        csr_op    : out std_logic;

        -- Error
        illegal   : out std_logic
    );
end entity decoder;

architecture rtl of decoder is

    -- Opcode field (bits 6:0)
    alias opcode  : std_logic_vector(6 downto 0) is instr(6 downto 0);
    alias funct3  : std_logic_vector(2 downto 0) is instr(14 downto 12);
    alias funct7  : std_logic_vector(6 downto 0) is instr(31 downto 25);

    -- RV32I opcode constants
    constant OP_LUI    : std_logic_vector(6 downto 0) := "0110111";
    constant OP_AUIPC  : std_logic_vector(6 downto 0) := "0010111";
    constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant OP_BRANCH : std_logic_vector(6 downto 0) := "1100011";
    constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";
    constant OP_IMM    : std_logic_vector(6 downto 0) := "0010011"; -- ALU-immediate
    constant OP_REG    : std_logic_vector(6 downto 0) := "0110011"; -- ALU-register
    constant OP_MISC   : std_logic_vector(6 downto 0) := "0001111"; -- FENCE
    constant OP_SYS    : std_logic_vector(6 downto 0) := "1110011"; -- ECALL/CSR

    -- funct7 qualifiers
    constant F7_SUB_SRA : std_logic_vector(6 downto 0) := "0100000";
    constant F7_MULDIV  : std_logic_vector(6 downto 0) := "0000001";

    -- immediate format constants (must match immediate_gen)
    constant IMM_I : std_logic_vector(2 downto 0) := "000";
    constant IMM_S : std_logic_vector(2 downto 0) := "001";
    constant IMM_B : std_logic_vector(2 downto 0) := "010";
    constant IMM_U : std_logic_vector(2 downto 0) := "011";
    constant IMM_J : std_logic_vector(2 downto 0) := "100";

begin

    decode_proc: process(opcode, funct3, funct7, instr)
    begin
        -- ── Safe defaults (all signals deasserted) ─────────
        alu_sel   <= funct3;
        alu_sub   <= '0';
        alu_arith <= '0';
        alu_src   <= '0';
        imm_sel   <= IMM_I;
        reg_wr    <= '0';
        mem_rd    <= '0';
        mem_wr    <= '0';
        mem_sz    <= "10";   -- word default
        mem_sx    <= '1';    -- sign-extend default
        branch    <= '0';
        jump      <= '0';
        lui       <= '0';
        auipc     <= '0';
        mul_op    <= '0';
        csr_op    <= '0';
        illegal   <= '0';

        case opcode is

            -- ── LUI ────────────────────────────────────────
            when OP_LUI =>
                reg_wr  <= '1';
                imm_sel <= IMM_U;
                lui     <= '1';

            -- ── AUIPC ──────────────────────────────────────
            when OP_AUIPC =>
                reg_wr  <= '1';
                imm_sel <= IMM_U;
                auipc   <= '1';

            -- ── JAL ────────────────────────────────────────
            when OP_JAL =>
                reg_wr  <= '1';
                imm_sel <= IMM_J;
                jump    <= '1';

            -- ── JALR ───────────────────────────────────────
            when OP_JALR =>
                reg_wr  <= '1';
                alu_src <= '1';
                imm_sel <= IMM_I;
                jump    <= '1';

            -- ── BRANCH (BEQ, BNE, BLT, BGE, BLTU, BGEU) ──
            when OP_BRANCH =>
                imm_sel <= IMM_B;
                branch  <= '1';
                alu_sub <= '1';   -- ALU computes rs1-rs2 for comparison

            -- ── LOAD (LB, LH, LW, LBU, LHU) ───────────────
            when OP_LOAD =>
                reg_wr  <= '1';
                alu_src <= '1';
                imm_sel <= IMM_I;
                mem_rd  <= '1';
                -- funct3 encodes size and sign
                case funct3 is
                    when "000" => mem_sz <= "00"; mem_sx <= '1';  -- LB
                    when "001" => mem_sz <= "01"; mem_sx <= '1';  -- LH
                    when "010" => mem_sz <= "10"; mem_sx <= '1';  -- LW
                    when "100" => mem_sz <= "00"; mem_sx <= '0';  -- LBU
                    when "101" => mem_sz <= "01"; mem_sx <= '0';  -- LHU
                    when others => illegal <= '1';
                end case;

            -- ── STORE (SB, SH, SW) ─────────────────────────
            when OP_STORE =>
                alu_src <= '1';
                imm_sel <= IMM_S;
                mem_wr  <= '1';
                case funct3 is
                    when "000" => mem_sz <= "00";  -- SB
                    when "001" => mem_sz <= "01";  -- SH
                    when "010" => mem_sz <= "10";  -- SW
                    when others => illegal <= '1';
                end case;

            -- ── ALU-IMMEDIATE (ADDI, SLTI, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
            when OP_IMM =>
                reg_wr  <= '1';
                alu_src <= '1';
                imm_sel <= IMM_I;
                alu_sel <= funct3;
                -- SRLI vs SRAI distinguished by funct7[5]
                if funct3 = "101" and funct7(5) = '1' then
                    alu_arith <= '1';
                end if;

            -- ── ALU-REGISTER (ADD,SUB,SLL,SLT,XOR,SRL,SRA,OR,AND + RV32M)
            when OP_REG =>
                reg_wr  <= '1';
                alu_sel <= funct3;

                if funct7 = F7_MULDIV then
                    -- ── RV32M: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
                    mul_op <= '1';
                else
                    -- ── RV32I register ops
                    -- SUB: funct3=000, funct7[5]=1
                    if funct3 = "000" and funct7(5) = '1' then
                        alu_sub <= '1';
                    end if;
                    -- SRA: funct3=101, funct7[5]=1
                    if funct3 = "101" and funct7(5) = '1' then
                        alu_arith <= '1';
                    end if;
                end if;

            -- ── MISC-MEM (FENCE — treated as NOP here) ─────
            when OP_MISC =>
                null;   -- single-core, no cache coherence needed

            -- ── SYSTEM (ECALL, EBREAK, CSR*) ───────────────
            when OP_SYS =>
                csr_op <= '1';
                if funct3 /= "000" then
                    reg_wr <= '1';   -- CSR read-modify-write writes rd
                end if;

            when others =>
                illegal <= '1';

        end case;
    end process;

end architecture rtl;