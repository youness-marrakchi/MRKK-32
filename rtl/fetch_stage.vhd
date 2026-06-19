-- ============================================================
--  MRKK-32 CPU  —  Stage 1: Fetch
--  Responsibilities:
--    · Holds the Program Counter (PC)
--    · Drives instruction memory address
--    · Computes PC+4 (default next PC)
--    · Accepts branch/jump target to redirect PC
--    · Inserts a NOP bubble on flush (branch taken)
--
--  PC update priority (highest first):
--    1. rst           -> PC = 0x00000000
--    2. stall         -> PC unchanged (hold)
--    3. branch_taken  -> PC = branch_target
--    4. default       -> PC = PC + 4
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fetch_stage is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;

        -- pipeline control
        stall         : in  std_logic;
        flush         : in  std_logic;

        -- branch / jump redirect
        branch_taken  : in  std_logic;
        branch_target : in  std_logic_vector(31 downto 0);

        -- to instruction memory
        imem_addr     : out std_logic_vector(31 downto 0);

        -- from instruction memory
        imem_data     : in  std_logic_vector(31 downto 0);

        -- outputs to IF/ID pipeline register
        pc_out        : out std_logic_vector(31 downto 0);
        pc_plus4_out  : out std_logic_vector(31 downto 0);
        instr_out     : out std_logic_vector(31 downto 0)
    );
end entity fetch_stage;

architecture rtl of fetch_stage is

    signal pc_reg  : std_logic_vector(31 downto 0) := (others => '0');
    signal pc_next : std_logic_vector(31 downto 0);

    -- RV32I NOP = ADDI x0, x0, 0
    constant NOP : std_logic_vector(31 downto 0) := x"00000013";

begin

    -- Combinational: next PC select
    pc_next <=
        branch_target when branch_taken = '1' else
        std_logic_vector(unsigned(pc_reg) + 4);

    -- Sequential: PC register
    pc_proc: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pc_reg <= (others => '0');
            elsif stall = '0' then
                pc_reg <= pc_next;
            end if;
        end if;
    end process;

    -- Instruction memory address
    imem_addr <= pc_reg;

    -- Outputs — inject NOP bubble on flush or reset
    pc_out       <= pc_reg;
    pc_plus4_out <= std_logic_vector(unsigned(pc_reg) + 4);
    instr_out    <= NOP when (flush = '1' or rst = '1') else imem_data;

end architecture rtl;