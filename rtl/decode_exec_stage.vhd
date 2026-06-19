-- ============================================================
--  MRKK-32 CPU  —  Stage 2: Decode / Execute
--  Responsibilities:
--    · Instantiates decoder, immediate_gen, register_file, ALU
--    · Resolves branch condition and target address
--    · Resolves jump (JAL/JALR) target address
--    · Handles LUI and AUIPC datapaths
--    · Drives branch_taken + branch_target back to fetch
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decode_exec_stage is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- from IF/ID register
        if_pc        : in  std_logic_vector(31 downto 0);
        if_pc_plus4  : in  std_logic_vector(31 downto 0);
        if_instr     : in  std_logic_vector(31 downto 0);

        -- writeback forwarding (from WB stage)
        wb_rd_addr   : in  std_logic_vector(4  downto 0);
        wb_wr_data   : in  std_logic_vector(31 downto 0);
        wb_wr_en     : in  std_logic;

        -- branch/jump redirect to fetch
        branch_taken  : out std_logic;
        branch_target : out std_logic_vector(31 downto 0);

        -- outputs to ID/WB register
        pc_plus4_out  : out std_logic_vector(31 downto 0);
        alu_result_out: out std_logic_vector(31 downto 0);
        rs2_data_out  : out std_logic_vector(31 downto 0);
        rd_addr_out   : out std_logic_vector(4  downto 0);
        reg_wr_out    : out std_logic;
        mem_rd_out    : out std_logic;
        mem_wr_out    : out std_logic;
        mem_sz_out    : out std_logic_vector(1  downto 0);
        mem_sx_out    : out std_logic;
        lui_result_out: out std_logic_vector(31 downto 0);
        is_lui_out    : out std_logic;
        is_jump_out   : out std_logic
    );
end entity decode_exec_stage;

architecture rtl of decode_exec_stage is

    -- ── Decoder outputs ──────────────────────────────────────
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
    signal is_branch : std_logic;
    signal is_jump   : std_logic;
    signal is_lui    : std_logic;
    signal is_auipc  : std_logic;
    signal mul_op    : std_logic;
    signal csr_op    : std_logic;
    signal illegal   : std_logic;

    -- ── Immediate ────────────────────────────────────────────
    signal imm       : std_logic_vector(31 downto 0);

    -- ── Register file ────────────────────────────────────────
    signal rs1_addr  : std_logic_vector(4 downto 0);
    signal rs2_addr  : std_logic_vector(4 downto 0);
    signal rd_addr   : std_logic_vector(4 downto 0);
    signal rs1_data  : std_logic_vector(31 downto 0);
    signal rs2_data  : std_logic_vector(31 downto 0);

    -- ── ALU ──────────────────────────────────────────────────
    signal alu_a     : std_logic_vector(31 downto 0);
    signal alu_b     : std_logic_vector(31 downto 0);
    signal alu_result: std_logic_vector(31 downto 0);
    signal alu_zero  : std_logic;
    signal alu_neg   : std_logic;
    signal alu_ov    : std_logic;

    -- ── Branch logic ─────────────────────────────────────────
    signal branch_cond : std_logic;

begin

    -- ── Field extraction ────────────────────────────────────
    rs1_addr <= if_instr(19 downto 15);
    rs2_addr <= if_instr(24 downto 20);
    rd_addr  <= if_instr(11 downto  7);

    -- ── Decoder ─────────────────────────────────────────────
    u_dec: entity work.decoder
        port map(
            instr     => if_instr,
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
            branch    => is_branch,
            jump      => is_jump,
            lui       => is_lui,
            auipc     => is_auipc,
            mul_op    => mul_op,
            csr_op    => csr_op,
            illegal   => illegal
        );

    -- ── Immediate generator ──────────────────────────────────
    u_imm: entity work.immediate_gen
        port map(
            instr   => if_instr,
            imm_sel => imm_sel,
            imm_out => imm
        );

    -- ── Register file ────────────────────────────────────────
    u_rf: entity work.register_file
        port map(
            clk      => clk,
            wr_en    => wb_wr_en,
            rd_addr  => wb_rd_addr,
            wr_data  => wb_wr_data,
            rs1_addr => rs1_addr,
            rs1_data => rs1_data,
            rs2_addr => rs2_addr,
            rs2_data => rs2_data
        );

    -- ── ALU input mux ────────────────────────────────────────
    -- AUIPC: A = PC,   B = imm
    -- ALU-imm / load / store: A = rs1, B = imm
    -- ALU-reg: A = rs1, B = rs2
    alu_a <= if_pc   when is_auipc = '1' else rs1_data;
    alu_b <= imm     when (alu_src = '1' or is_auipc = '1') else rs2_data;

    -- ── ALU ─────────────────────────────────────────────────
    u_alu: entity work.alu
        port map(
            a         => alu_a,
            b         => alu_b,
            alu_sel   => alu_sel,
            alu_sub   => alu_sub,
            alu_arith => alu_arith,
            result    => alu_result,
            zero      => alu_zero,
            negative  => alu_neg,
            overflow  => alu_ov
        );

    -- ── Branch condition resolve ──────────────────────────────
    -- Uses funct3 to pick the correct comparison
    process(is_branch, if_instr, alu_zero, alu_neg, alu_ov, rs1_data, rs2_data)
        variable f3 : std_logic_vector(2 downto 0);
    begin
        f3 := if_instr(14 downto 12);
        branch_cond <= '0';
        if is_branch = '1' then
            case f3 is
                when "000" => branch_cond <= alu_zero;
                when "001" => branch_cond <= not alu_zero;
                when "100" => branch_cond <= alu_neg xor alu_ov;
                when "101" => branch_cond <= not (alu_neg xor alu_ov);

                when "110" =>
                    if unsigned(rs1_data) < unsigned(rs2_data) then
                        branch_cond <= '1';
                    else
                        branch_cond <= '0';
                    end if;

                when "111" =>
                    if unsigned(rs1_data) >= unsigned(rs2_data) then
                        branch_cond <= '1';
                    else
                        branch_cond <= '0';
                    end if;

                when others =>
                    branch_cond <= '0';
            end case;
        end if;
    end process;

    -- ── Branch / jump target address ─────────────────────────
    -- Branch target : PC + B-imm
    -- JAL target    : PC + J-imm
    -- JALR target   : (rs1 + I-imm) AND NOT 1  (clear bit 0)
    branch_target <=
        std_logic_vector(unsigned(rs1_data) + unsigned(imm)) and x"FFFFFFFE"
            when (is_jump = '1' and if_instr(6 downto 0) = "1100111") else  -- JALR
        std_logic_vector(unsigned(if_pc) + unsigned(imm));                   -- JAL / branch

    branch_taken <= branch_cond or is_jump;

    -- ── LUI result (bypasses ALU entirely) ───────────────────
    lui_result_out <= imm;   -- U-type immediate already has zeros in [11:0]

    -- ── Outputs to ID/WB register ────────────────────────────
    pc_plus4_out   <= if_pc_plus4;
    alu_result_out <= alu_result;
    rs2_data_out   <= rs2_data;
    rd_addr_out    <= rd_addr;
    reg_wr_out     <= reg_wr;
    mem_rd_out     <= mem_rd;
    mem_wr_out     <= mem_wr;
    mem_sz_out     <= mem_sz;
    mem_sx_out     <= mem_sx;
    is_lui_out     <= is_lui;
    is_jump_out    <= is_jump;

end architecture rtl;