-- ============================================================
--  MRKK-32 CPU  —  Stage 3: Writeback
--  Responsibilities:
--    · Reads data memory (loads)
--    · Writes data memory (stores)
--    · Selects write-back data source:
--        - ALU result   (arithmetic/logic)
--        - Memory load  (LW/LH/LB/LHU/LBU)
--        - LUI result   (upper immediate)
--        - PC+4         (JAL/JALR return address)
--    · Drives register file write port
--    · Sign/zero extends byte and half-word loads
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity writeback_stage is
    port (
        -- from ID/WB register
        pc_plus4    : in  std_logic_vector(31 downto 0);
        alu_result  : in  std_logic_vector(31 downto 0);
        rs2_data    : in  std_logic_vector(31 downto 0);  -- store data
        rd_addr     : in  std_logic_vector(4  downto 0);
        reg_wr      : in  std_logic;
        mem_rd      : in  std_logic;
        mem_wr      : in  std_logic;
        mem_sz      : in  std_logic_vector(1  downto 0);  -- 00=byte 01=half 10=word
        mem_sx      : in  std_logic;                       -- sign-extend
        lui_result  : in  std_logic_vector(31 downto 0);
        is_lui      : in  std_logic;
        is_jump     : in  std_logic;

        -- data memory port (Harvard D-port)
        dmem_addr   : out std_logic_vector(31 downto 0);
        dmem_wr_data: out std_logic_vector(31 downto 0);
        dmem_wr_en  : out std_logic;
        dmem_rd_en  : out std_logic;
        dmem_sz     : out std_logic_vector(1  downto 0);
        dmem_rd_data: in  std_logic_vector(31 downto 0);

        -- register file write port
        rf_wr_en    : out std_logic;
        rf_rd_addr  : out std_logic_vector(4  downto 0);
        rf_wr_data  : out std_logic_vector(31 downto 0)
    );
end entity writeback_stage;

architecture rtl of writeback_stage is

    signal load_data : std_logic_vector(31 downto 0);
    signal wb_data   : std_logic_vector(31 downto 0);

begin

    -- ── Data memory drive ────────────────────────────────────
    dmem_addr    <= alu_result;   -- effective address from ALU
    dmem_wr_data <= rs2_data;
    dmem_wr_en   <= mem_wr;
    dmem_rd_en   <= mem_rd;
    dmem_sz      <= mem_sz;

    -- ── Load data sign/zero extension ────────────────────────
    process(dmem_rd_data, mem_sz, mem_sx)
    begin
        case mem_sz is
            when "00" =>   -- byte
                if mem_sx = '1' then
                    load_data <= (31 downto 8 => dmem_rd_data(7)) & dmem_rd_data(7 downto 0);
                else
                    load_data <= (31 downto 8 => '0') & dmem_rd_data(7 downto 0);
                end if;
            when "01" =>   -- half-word
                if mem_sx = '1' then
                    load_data <= (31 downto 16 => dmem_rd_data(15)) & dmem_rd_data(15 downto 0);
                else
                    load_data <= (31 downto 16 => '0') & dmem_rd_data(15 downto 0);
                end if;
            when others => -- word
                load_data <= dmem_rd_data;
        end case;
    end process;

    -- ── Writeback data mux ────────────────────────────────────
    -- Priority: jump (PC+4) > LUI > load > ALU
    wb_data <=
        pc_plus4   when is_jump = '1'  else
        lui_result when is_lui  = '1'  else
        load_data  when mem_rd  = '1'  else
        alu_result;

    -- ── Register file write ──────────────────────────────────
    rf_wr_en   <= reg_wr;
    rf_rd_addr <= rd_addr;
    rf_wr_data <= wb_data;

end architecture rtl;