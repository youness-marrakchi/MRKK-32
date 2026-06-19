-- ============================================================
--  MRKK-32 CPU  —  L1 Data Cache
--  · Direct-mapped, write-through
--  · 32 cache lines x 32-byte (8 words) = 1 KB
--  · Tag = addr[31:10], Index = addr[9:5], Offset = addr[4:2]
--
--  Write-through policy:
--    · Writes always go to data memory AND update cache if hit
--    · No dirty bits needed
--
--  Read miss: fetch full line from data memory (8 cycles)
--  Write miss: write-around (write to memory only, no fill)
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dcache is
    generic (
        NUM_LINES  : integer := 32;
        WORDS_LINE : integer := 8
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- CPU side
        cpu_addr     : in  std_logic_vector(31 downto 0);
        cpu_rd_en    : in  std_logic;
        cpu_wr_en    : in  std_logic;
        cpu_wr_data  : in  std_logic_vector(31 downto 0);
        cpu_sz       : in  std_logic_vector(1 downto 0);
        cpu_rd_data  : out std_logic_vector(31 downto 0);
        stall_req    : out std_logic;

        -- Memory side
        mem_addr     : out std_logic_vector(31 downto 0);
        mem_rd_en    : out std_logic;
        mem_wr_en    : out std_logic;
        mem_wr_data  : out std_logic_vector(31 downto 0);
        mem_sz       : out std_logic_vector(1 downto 0);
        mem_rd_data  : in  std_logic_vector(31 downto 0)
    );
end entity dcache;

architecture rtl of dcache is

    type line_data   is array (0 to WORDS_LINE-1) of std_logic_vector(31 downto 0);
    type cache_data  is array (0 to NUM_LINES-1)  of line_data;
    type tag_array   is array (0 to NUM_LINES-1)  of std_logic_vector(21 downto 0);
    type valid_array is array (0 to NUM_LINES-1)  of std_logic;

    signal data_store  : cache_data  := (others => (others => (others => '0')));
    signal tag_store   : tag_array   := (others => (others => '0'));
    signal valid_store : valid_array := (others => '0');

    signal tag    : std_logic_vector(21 downto 0);
    signal index  : integer range 0 to NUM_LINES-1;
    signal offset : integer range 0 to WORDS_LINE-1;
    signal hit    : std_logic;

    type state_t is (IDLE, FILL, READY);
    signal state     : state_t := IDLE;
    signal fill_word : integer range 0 to WORDS_LINE-1 := 0;
    signal fill_base : std_logic_vector(31 downto 0);
    signal fill_buf  : line_data;
    signal save_idx  : integer range 0 to NUM_LINES-1;
    signal save_tag  : std_logic_vector(21 downto 0);

begin

    tag    <= cpu_addr(31 downto 10);
    index  <= to_integer(unsigned(cpu_addr(9 downto 5)));
    offset <= to_integer(unsigned(cpu_addr(4 downto 2)));
    hit    <= '1' when (valid_store(index)='1' and tag_store(index)=tag) else '0';

    -- ── CPU read data (combinational on hit) ─────────────────
    cpu_rd_data <= data_store(index)(offset) when hit='1' else (others=>'0');

    -- ── Write-through: always forward writes to memory ───────
    mem_addr    <= cpu_addr;
    mem_wr_en   <= cpu_wr_en;
    mem_wr_data <= cpu_wr_data;
    mem_sz      <= cpu_sz;

    -- ── Stall only on read miss ───────────────────────────────
    stall_req <= '1' when (cpu_rd_en='1' and hit='0' and state=IDLE) else
                 '1' when (state=FILL or state=READY) else
                 '0';

    -- ── Read-miss fill FSM ────────────────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                valid_store <= (others=>'0');
                state       <= IDLE;
                mem_rd_en   <= '0';
            else
                case state is
                    when IDLE =>
                        if cpu_rd_en='1' and hit='0' then
                            fill_base <= cpu_addr(31 downto 5) & "00000";
                            fill_word <= 0;
                            save_idx  <= index;
                            save_tag  <= tag;
                            mem_rd_en <= '1';
                            mem_addr  <= cpu_addr(31 downto 5) & "00000";
                            state     <= FILL;
                        else
                            mem_rd_en <= '0';
                            -- Update cache on write hit
                            if cpu_wr_en='1' and hit='1' then
                                data_store(index)(offset) <= cpu_wr_data;
                            end if;
                        end if;

                    when FILL =>
                        fill_buf(fill_word) <= mem_rd_data;
                        if fill_word = WORDS_LINE-1 then
                            mem_rd_en <= '0';
                            state     <= READY;
                        else
                            fill_word <= fill_word + 1;
                            mem_addr  <= std_logic_vector(
                                unsigned(fill_base) + to_unsigned((fill_word+1)*4,32));
                        end if;

                    when READY =>
                        data_store(save_idx) <= fill_buf;
                        tag_store(save_idx)  <= save_tag;
                        valid_store(save_idx)<= '1';
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;