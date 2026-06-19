-- ============================================================
--  MRKK-32 CPU  —  Peripheral Package
--  Three peripherals in one file:
--
--  1. UART  (0xFFFF0000)
--     REG 0: TX_DATA  [7:0]   write byte to transmit
--     REG 1: RX_DATA  [7:0]   read received byte
--     REG 2: STATUS   [1:0]   bit0=TX_READY  bit1=RX_VALID
--     REG 3: CONTROL  [0]     bit0=UART_EN
--     (Simulation model: TX writes go to a shift register,
--      STATUS.TX_READY is always 1 in simulation)
--
--  2. GPIO  (0xFFFF0020)
--     REG 0: DATA_OUT [7:0]   drive output pins
--     REG 1: DATA_IN  [7:0]   read input pins
--     REG 2: DIR      [7:0]   bit=1 output, bit=0 input
--     REG 3: IRQ_MASK [7:0]   enable pin-change interrupts
--
--  3. TIMER (0xFFFF0030)
--     REG 0: COUNT    [31:0]  free-running 32-bit counter
--     REG 1: COMPARE  [31:0]  compare value (IRQ on match)
--     REG 2: CONTROL  [1:0]   bit0=EN  bit1=IRQ_EN
--     REG 3: STATUS   [0]     bit0=MATCH (write 1 to clear)
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ── UART ──────────────────────────────────────────────────────
entity uart_periph is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        addr      : in  std_logic_vector(2 downto 0);
        wr_en     : in  std_logic;
        wr_data   : in  std_logic_vector(31 downto 0);
        rd_data   : out std_logic_vector(31 downto 0);
        tx_irq    : out std_logic;
        rx_irq    : out std_logic;
        -- simulation TX port (observable)
        tx_byte   : out std_logic_vector(7 downto 0);
        tx_valid  : out std_logic
    );
end entity uart_periph;

architecture rtl of uart_periph is
    signal tx_data  : std_logic_vector(7 downto 0) := (others=>'0');
    signal rx_data  : std_logic_vector(7 downto 0) := (others=>'0');
    signal ctrl_en  : std_logic := '0';
    signal tx_pulse : std_logic := '0';
begin
    tx_byte  <= tx_data;
    tx_valid <= tx_pulse;
    tx_irq   <= '0';  -- simplified: no TX interrupt
    rx_irq   <= '0';  -- simplified: no RX in simulation

    process(clk)
    begin
        if rising_edge(clk) then
            tx_pulse <= '0';
            if rst = '1' then
                tx_data <= (others=>'0');
                ctrl_en <= '0';
            elsif wr_en = '1' then
                case addr is
                    when "000" =>
                        tx_data  <= wr_data(7 downto 0);
                        tx_pulse <= ctrl_en;   -- only TX if enabled
                    when "011" =>
                        ctrl_en <= wr_data(0);
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    with addr select rd_data <=
        x"000000" & tx_data  when "000",
        x"000000" & rx_data  when "001",
        x"00000001"          when "010",  -- TX always ready in sim
        x"0000000" & "000" & ctrl_en when "011",
        (others=>'0')        when others;
end architecture rtl;


-- ── GPIO ──────────────────────────────────────────────────────
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gpio_periph is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        addr     : in  std_logic_vector(1 downto 0);
        wr_en    : in  std_logic;
        wr_data  : in  std_logic_vector(31 downto 0);
        rd_data  : out std_logic_vector(31 downto 0);
        -- physical pins
        gpio_out : out std_logic_vector(7 downto 0);
        gpio_in  : in  std_logic_vector(7 downto 0);
        gpio_dir : out std_logic_vector(7 downto 0);
        gpio_irq : out std_logic
    );
end entity gpio_periph;

architecture rtl of gpio_periph is
    signal data_out  : std_logic_vector(7 downto 0) := (others=>'0');
    signal direction : std_logic_vector(7 downto 0) := (others=>'0');
    signal irq_mask  : std_logic_vector(7 downto 0) := (others=>'0');
    signal prev_in   : std_logic_vector(7 downto 0) := (others=>'0');
begin
    gpio_out <= data_out;
    gpio_dir <= direction;
    gpio_irq <= '1' when ((gpio_in xor prev_in) and irq_mask) /= x"00" else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            prev_in <= gpio_in;
            if rst = '1' then
                data_out  <= (others=>'0');
                direction <= (others=>'0');
                irq_mask  <= (others=>'0');
            elsif wr_en = '1' then
                case addr is
                    when "00" => data_out  <= wr_data(7 downto 0);
                    when "10" => direction <= wr_data(7 downto 0);
                    when "11" => irq_mask  <= wr_data(7 downto 0);
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    with addr select rd_data <=
        x"000000" & data_out  when "00",
        x"000000" & gpio_in   when "01",
        x"000000" & direction when "10",
        x"000000" & irq_mask  when "11",
        (others=>'0')         when others;
end architecture rtl;


-- ── TIMER ─────────────────────────────────────────────────────
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity timer_periph is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        addr     : in  std_logic_vector(1 downto 0);
        wr_en    : in  std_logic;
        wr_data  : in  std_logic_vector(31 downto 0);
        rd_data  : out std_logic_vector(31 downto 0);
        timer_irq: out std_logic
    );
end entity timer_periph;

architecture rtl of timer_periph is
    signal count   : unsigned(31 downto 0) := (others=>'0');
    signal compare : unsigned(31 downto 0) := x"FFFFFFFF";
    signal ctrl_en : std_logic := '0';
    signal irq_en  : std_logic := '0';
    signal match   : std_logic := '0';
begin
    timer_irq <= match and irq_en;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                count   <= (others=>'0');
                compare <= x"FFFFFFFF";
                ctrl_en <= '0';
                irq_en  <= '0';
                match   <= '0';
            else
                -- free-running counter
                if ctrl_en = '1' then
                    count <= count + 1;
                    if count + 1 = compare then
                        match <= '1';
                    end if;
                end if;

                if wr_en = '1' then
                    case addr is
                        when "00" => count   <= unsigned(wr_data);
                        when "01" => compare <= unsigned(wr_data);
                        when "10" =>
                            ctrl_en <= wr_data(0);
                            irq_en  <= wr_data(1);
                        when "11" =>
                            if wr_data(0) = '1' then match <= '0'; end if;
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    with addr select rd_data <=
        std_logic_vector(count)    when "00",
        std_logic_vector(compare)  when "01",
        x"0000000" & "00" & irq_en & ctrl_en when "10",
        x"0000000" & "000" & match when "11",
        (others=>'0')              when others;
end architecture rtl;