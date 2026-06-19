-- ============================================================
--  MRKK-32 CPU  —  Pipeline Inter-Stage Registers
--  Two latches:
--    IF_ID  : Fetch -> Decode/Execute
--    ID_WB  : Decode/Execute -> Writeback
--
--  Each register:
--    · Clocked on rising edge
--    · Synchronous reset clears to NOP/zero
--    · flush  -> same as reset (inject bubble)
--    · stall  -> hold current value
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;

-- ── IF/ID register ──────────────────────────────────────────
entity if_id_reg is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        flush    : in  std_logic;
        stall    : in  std_logic;
        -- inputs from fetch
        in_pc       : in  std_logic_vector(31 downto 0);
        in_pc_plus4 : in  std_logic_vector(31 downto 0);
        in_instr    : in  std_logic_vector(31 downto 0);
        -- outputs to decode/execute
        out_pc       : out std_logic_vector(31 downto 0);
        out_pc_plus4 : out std_logic_vector(31 downto 0);
        out_instr    : out std_logic_vector(31 downto 0)
    );
end entity if_id_reg;

architecture rtl of if_id_reg is
    constant NOP : std_logic_vector(31 downto 0) := x"00000013";
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush = '1' then
                out_pc       <= (others => '0');
                out_pc_plus4 <= (others => '0');
                out_instr    <= NOP;
            elsif stall = '0' then
                out_pc       <= in_pc;
                out_pc_plus4 <= in_pc_plus4;
                out_instr    <= in_instr;
            end if;
        end if;
    end process;
end architecture rtl;


-- ── ID/WB register ──────────────────────────────────────────
library ieee;
use ieee.std_logic_1164.all;

entity id_wb_reg is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        flush    : in  std_logic;
        stall    : in  std_logic;
        -- inputs from decode/execute
        in_pc_plus4  : in  std_logic_vector(31 downto 0);
        in_alu_result: in  std_logic_vector(31 downto 0);
        in_rs2_data  : in  std_logic_vector(31 downto 0);
        in_rd_addr   : in  std_logic_vector(4  downto 0);
        in_reg_wr    : in  std_logic;
        in_mem_rd    : in  std_logic;
        in_mem_wr    : in  std_logic;
        in_mem_sz    : in  std_logic_vector(1  downto 0);
        in_mem_sx    : in  std_logic;
        in_lui_result: in  std_logic_vector(31 downto 0);
        in_is_lui    : in  std_logic;
        in_is_jump   : in  std_logic;
        -- outputs to writeback
        out_pc_plus4  : out std_logic_vector(31 downto 0);
        out_alu_result: out std_logic_vector(31 downto 0);
        out_rs2_data  : out std_logic_vector(31 downto 0);
        out_rd_addr   : out std_logic_vector(4  downto 0);
        out_reg_wr    : out std_logic;
        out_mem_rd    : out std_logic;
        out_mem_wr    : out std_logic;
        out_mem_sz    : out std_logic_vector(1  downto 0);
        out_mem_sx    : out std_logic;
        out_lui_result: out std_logic_vector(31 downto 0);
        out_is_lui    : out std_logic;
        out_is_jump   : out std_logic
    );
end entity id_wb_reg;

architecture rtl of id_wb_reg is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush = '1' then
                out_pc_plus4   <= (others => '0');
                out_alu_result <= (others => '0');
                out_rs2_data   <= (others => '0');
                out_rd_addr    <= (others => '0');
                out_reg_wr     <= '0';
                out_mem_rd     <= '0';
                out_mem_wr     <= '0';
                out_mem_sz     <= "10";
                out_mem_sx     <= '1';
                out_lui_result <= (others => '0');
                out_is_lui     <= '0';
                out_is_jump    <= '0';
            elsif stall = '0' then
                out_pc_plus4   <= in_pc_plus4;
                out_alu_result <= in_alu_result;
                out_rs2_data   <= in_rs2_data;
                out_rd_addr    <= in_rd_addr;
                out_reg_wr     <= in_reg_wr;
                out_mem_rd     <= in_mem_rd;
                out_mem_wr     <= in_mem_wr;
                out_mem_sz     <= in_mem_sz;
                out_mem_sx     <= in_mem_sx;
                out_lui_result <= in_lui_result;
                out_is_lui     <= in_is_lui;
                out_is_jump    <= in_is_jump;
            end if;
        end if;
    end process;
end architecture rtl;