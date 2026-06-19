-- ============================================================
--  MRKK-32 CPU  —  Data Memory (Harvard D-port)
--  · Byte-addressable RAM, synchronous write, sync read
--  · Supports byte / half-word / word access (sz field)
--  · 1KB default = 1024 bytes
--  · Write mask applied per sz so surrounding bytes untouched
--  · Read returns full 32-bit word; writeback stage
--    performs sign/zero extension on the result
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_memory is
    generic (
        DEPTH : integer := 1024    -- bytes
    );
    port (
        clk      : in  std_logic;
        -- write port
        wr_en    : in  std_logic;
        addr     : in  std_logic_vector(31 downto 0);
        wr_data  : in  std_logic_vector(31 downto 0);
        sz       : in  std_logic_vector(1 downto 0);  -- 00=byte 01=half 10=word
        -- read port
        rd_en    : in  std_logic;
        rd_data  : out std_logic_vector(31 downto 0)
    );
end entity data_memory;

architecture rtl of data_memory is

    type byte_array is array (0 to DEPTH-1) of std_logic_vector(7 downto 0);
    signal mem : byte_array := (others => x"00");

    signal byte_idx : integer;

begin

    byte_idx <= to_integer(unsigned(addr)) mod DEPTH;

    -- ── Synchronous write ─────────────────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if wr_en = '1' then
                case sz is
                    when "00" =>   -- SB: write 1 byte
                        mem(byte_idx) <= wr_data(7 downto 0);

                    when "01" =>   -- SH: write 2 bytes (little-endian)
                        mem(byte_idx)   <= wr_data(7  downto 0);
                        mem(byte_idx+1) <= wr_data(15 downto 8);

                    when others => -- SW: write 4 bytes (little-endian)
                        mem(byte_idx)   <= wr_data(7  downto 0);
                        mem(byte_idx+1) <= wr_data(15 downto 8);
                        mem(byte_idx+2) <= wr_data(23 downto 16);
                        mem(byte_idx+3) <= wr_data(31 downto 24);
                end case;
            end if;
        end if;
    end process;

    -- ── Synchronous read ──────────────────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if rd_en = '1' then
                rd_data <=
                    mem(byte_idx+3) &
                    mem(byte_idx+2) &
                    mem(byte_idx+1) &
                    mem(byte_idx);
            end if;
        end if;
    end process;

end architecture rtl;