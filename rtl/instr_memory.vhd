-- ============================================================
--  MRKK-32 CPU  —  Instruction Memory (Harvard I-port)
--  · Synchronous ROM, word-addressed (addr >> 2)
--  · Initializable from a .mem file (hex, one word/line)
--  · 1KB default = 256 x 32-bit words
--  · Read latency: 1 cycle (registered output)
--  · Out-of-range address returns NOP
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity instr_memory is
    generic (
        DEPTH     : integer := 256;          -- number of 32-bit words
        MEM_FILE  : string  := ""            -- optional .mem init file
    );
    port (
        clk       : in  std_logic;
        addr      : in  std_logic_vector(31 downto 0);  -- byte address
        instr     : out std_logic_vector(31 downto 0)
    );
end entity instr_memory;

architecture rtl of instr_memory is

    type mem_array is array (0 to DEPTH-1) of std_logic_vector(31 downto 0);

    -- Initialise with a simple default test program if no file given.
    -- Slots not covered stay as NOPs (x"00000013").
    -- Real programs load via the .mem file mechanism.
    signal mem : mem_array := (others => x"00000013");

    signal word_addr : integer range 0 to DEPTH-1;
    signal valid     : std_logic;

begin

    -- ── Word address decode ───────────────────────────────────
    word_addr <= to_integer(unsigned(addr(31 downto 2))) mod DEPTH;
    valid     <= '1' when to_integer(unsigned(addr)) < DEPTH*4 else '0';

    -- ── Synchronous read ─────────────────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if valid = '1' then
                instr <= mem(word_addr);
            else
                instr <= x"00000013";   -- NOP on out-of-range
            end if;
        end if;
    end process;

end architecture rtl;