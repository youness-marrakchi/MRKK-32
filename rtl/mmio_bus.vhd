-- ============================================================
--  MRKK-32 CPU  —  MMIO Address Decoder / Bus
--
--  Memory map (above normal RAM):
--    0xFFFF0000  UART    (8 registers x 4 bytes = 0x20)
--    0xFFFF0020  GPIO    (4 registers x 4 bytes = 0x10)
--    0xFFFF0030  TIMER   (4 registers x 4 bytes = 0x10)
--    0xFFFF0040  IRQ_CTRL(4 registers x 4 bytes = 0x10)
--
--  The bus sits between the D-cache/writeback stage and the
--  peripheral registers.  If the address is in the MMIO range
--  the access is routed to the peripheral; otherwise it goes
--  to data memory as normal.
--
--  All MMIO accesses are word-aligned and word-sized.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mmio_bus is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- CPU side (from writeback stage)
        cpu_addr    : in  std_logic_vector(31 downto 0);
        cpu_wr_en   : in  std_logic;
        cpu_rd_en   : in  std_logic;
        cpu_wr_data : in  std_logic_vector(31 downto 0);
        cpu_rd_data : out std_logic_vector(31 downto 0);

        -- Data memory side (pass-through when not MMIO)
        dmem_addr   : out std_logic_vector(31 downto 0);
        dmem_wr_en  : out std_logic;
        dmem_rd_en  : out std_logic;
        dmem_wr_data: out std_logic_vector(31 downto 0);
        dmem_rd_data: in  std_logic_vector(31 downto 0);

        -- UART peripheral registers
        uart_addr   : out std_logic_vector(2 downto 0);
        uart_wr_en  : out std_logic;
        uart_wr_data: out std_logic_vector(31 downto 0);
        uart_rd_data: in  std_logic_vector(31 downto 0);

        -- GPIO peripheral registers
        gpio_addr   : out std_logic_vector(1 downto 0);
        gpio_wr_en  : out std_logic;
        gpio_wr_data: out std_logic_vector(31 downto 0);
        gpio_rd_data: in  std_logic_vector(31 downto 0);

        -- Timer peripheral registers
        timer_addr   : out std_logic_vector(1 downto 0);
        timer_wr_en  : out std_logic;
        timer_wr_data: out std_logic_vector(31 downto 0);
        timer_rd_data: in  std_logic_vector(31 downto 0);

        -- IRQ controller registers
        irqc_addr   : out std_logic_vector(1 downto 0);
        irqc_wr_en  : out std_logic;
        irqc_wr_data: out std_logic_vector(3 downto 0);
        irqc_rd_data: in  std_logic_vector(3 downto 0)
    );
end entity mmio_bus;

architecture rtl of mmio_bus is

    -- MMIO region base
    constant MMIO_BASE  : std_logic_vector(15 downto 0) := x"FFFF";

    -- Peripheral base offsets (relative to 0xFFFF0000)
    constant UART_BASE  : std_logic_vector(7 downto 0) := x"00";
    constant GPIO_BASE  : std_logic_vector(7 downto 0) := x"20";
    constant TIMER_BASE : std_logic_vector(7 downto 0) := x"30";
    constant IRQ_BASE   : std_logic_vector(7 downto 0) := x"40";

    signal is_mmio   : std_logic;
    signal offset    : std_logic_vector(7 downto 0);
    signal sel_uart  : std_logic;
    signal sel_gpio  : std_logic;
    signal sel_timer : std_logic;
    signal sel_irq   : std_logic;

begin

    -- ── MMIO region detect ────────────────────────────────────
    is_mmio <= '1' when cpu_addr(31 downto 16) = MMIO_BASE else '0';
    offset  <= cpu_addr(7 downto 0);

    -- ── Peripheral select ─────────────────────────────────────
    sel_uart  <= is_mmio when offset < x"20"                             else '0';
    sel_gpio  <= is_mmio when offset >= x"20" and offset < x"30"        else '0';
    sel_timer <= is_mmio when offset >= x"30" and offset < x"40"        else '0';
    sel_irq   <= is_mmio when offset >= x"40" and offset < x"50"        else '0';

    -- ── Data memory pass-through (non-MMIO) ──────────────────
    dmem_addr    <= cpu_addr;
    dmem_wr_en   <= cpu_wr_en  when is_mmio = '0' else '0';
    dmem_rd_en   <= cpu_rd_en  when is_mmio = '0' else '0';
    dmem_wr_data <= cpu_wr_data;

    -- ── Peripheral register addresses ─────────────────────────
    uart_addr  <= cpu_addr(4 downto 2);
    gpio_addr  <= cpu_addr(3 downto 2);
    timer_addr <= cpu_addr(3 downto 2);
    irqc_addr  <= cpu_addr(3 downto 2);

    -- ── Peripheral write enables ──────────────────────────────
    uart_wr_en  <= cpu_wr_en and sel_uart;
    gpio_wr_en  <= cpu_wr_en and sel_gpio;
    timer_wr_en <= cpu_wr_en and sel_timer;
    irqc_wr_en  <= cpu_wr_en and sel_irq;

    -- ── Write data ────────────────────────────────────────────
    uart_wr_data  <= cpu_wr_data;
    gpio_wr_data  <= cpu_wr_data;
    timer_wr_data <= cpu_wr_data;
    irqc_wr_data  <= cpu_wr_data(3 downto 0);

    -- ── Read data mux ─────────────────────────────────────────
    cpu_rd_data <=
        uart_rd_data                            when (cpu_rd_en='1' and sel_uart='1')  else
        gpio_rd_data                            when (cpu_rd_en='1' and sel_gpio='1')  else
        timer_rd_data                           when (cpu_rd_en='1' and sel_timer='1') else
        (x"0000000" & irqc_rd_data)             when (cpu_rd_en='1' and sel_irq='1')   else
        dmem_rd_data;

end architecture rtl;