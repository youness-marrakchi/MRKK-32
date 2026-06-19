-- ============================================================
--  MRKK-32 CPU  —  L1 Instruction Cache
--  · Direct-mapped, write-through (read-only from CPU side)
--  · 32 cache lines x 32-byte (8 words) per line = 1 KB
--  · Tag = addr[31:10],  Index = addr[9:5],  Offset = addr[4:2]
--  · Single-cycle hit; miss stalls the pipeline (stall_req='1')
--    and fetches a full cache line from instruction memory
--
--  State machine:
--    IDLE   : check tag + valid
--    MISS   : fetch 8 words from imem, one per cycle
--    FILL   : write refilled line, deassert stall
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity icache is
    generic (
        NUM_LINES  : integer := 32;     -- number of cache lines
        WORDS_LINE : integer := 8       -- words per cache line (32 bytes)
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;

        -- CPU side
        cpu_addr   : in  std_logic_vector(31 downto 0);
        cpu_rd_en  : in  std_logic;
        cpu_data   : out std_logic_vector(31 downto 0);
        stall_req  : out std_logic;     -- '1' = miss, pipeline must stall

        -- Memory side (to instruction memory)
        mem_addr   : out std_logic_vector(31 downto 0);
        mem_rd_en  : out std_logic;
        mem_data   : in  std_logic_vector(31 downto 0)
    );
end entity icache;

architecture rtl of icache is

    -- Cache storage
    type line_data  is array (0 to WORDS_LINE-1) of std_logic_vector(31 downto 0);
    type cache_data is array (0 to NUM_LINES-1)  of line_data;
    type tag_array  is array (0 to NUM_LINES-1)  of std_logic_vector(21 downto 0);
    type valid_array is array (0 to NUM_LINES-1) of std_logic;

    signal data_store  : cache_data  := (others => (others => (others => '0')));
    signal tag_store   : tag_array   := (others => (others => '0'));
    signal valid_store : valid_array := (others => '0');

    -- Address decomposition
    signal tag    : std_logic_vector(21 downto 0);  -- bits [31:10]
    signal index  : integer range 0 to NUM_LINES-1;
    signal offset : integer range 0 to WORDS_LINE-1;

    -- FSM
    type state_t is (IDLE, MISS, FILL);
    signal state      : state_t := IDLE;
    signal fill_word  : integer range 0 to WORDS_LINE-1 := 0;
    signal fill_base  : std_logic_vector(31 downto 0);  -- line-aligned base addr
    signal fill_buf   : line_data;
    signal hit        : std_logic;

begin

    tag    <= cpu_addr(31 downto 10);
    index  <= to_integer(unsigned(cpu_addr(9 downto 5)));
    offset <= to_integer(unsigned(cpu_addr(4 downto 2)));

    hit <= '1' when (valid_store(index) = '1' and tag_store(index) = tag) else '0';

    -- ── CPU read output (combinational on hit) ────────────────
    cpu_data  <= data_store(index)(offset) when hit = '1' else (others => '0');
    stall_req <= '0' when (hit = '1' or cpu_rd_en = '0') else '1';

    -- ── Fill state machine ────────────────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                valid_store <= (others => '0');
                state       <= IDLE;
                mem_rd_en   <= '0';
                mem_addr    <= (others => '0');
            else
                case state is
                    when IDLE =>
                        if cpu_rd_en = '1' and hit = '0' then
                            -- cache miss: start line fill
                            fill_base <= cpu_addr(31 downto 5) & "00000";
                            fill_word <= 0;
                            mem_addr  <= cpu_addr(31 downto 5) & "00000";
                            mem_rd_en <= '1';
                            state     <= MISS;
                        else
                            mem_rd_en <= '0';
                        end if;

                    when MISS =>
                        -- collect one word per cycle from imem
                        fill_buf(fill_word) <= mem_data;
                        if fill_word = WORDS_LINE-1 then
                            mem_rd_en <= '0';
                            state     <= FILL;
                        else
                            fill_word <= fill_word + 1;
                            mem_addr  <= std_logic_vector(
                                unsigned(fill_base) + to_unsigned((fill_word+1)*4, 32));
                        end if;

                    when FILL =>
                        -- write refilled line into cache
                        data_store(index)  <= fill_buf;
                        tag_store(index)   <= tag;
                        valid_store(index) <= '1';
                        state              <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;