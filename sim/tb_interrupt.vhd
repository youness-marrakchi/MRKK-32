library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_interrupt_ctrl is end entity;

architecture sim of tb_interrupt_ctrl is
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal irq_lines   : std_logic_vector(3 downto 0) := "0000";
    signal mie         : std_logic := '0';
    signal mepc_in     : std_logic_vector(31 downto 0) := x"00000200";
    signal mepc_out    : std_logic_vector(31 downto 0);
    signal mcause_out  : std_logic_vector(31 downto 0);
    signal reg_addr    : std_logic_vector(1 downto 0) := "00";
    signal reg_wr_en   : std_logic := '0';
    signal reg_wr_data : std_logic_vector(3 downto 0) := "0000";
    signal reg_rd_data : std_logic_vector(3 downto 0);
    signal irq_taken   : std_logic;
    signal mtvec       : std_logic_vector(31 downto 0);
    constant CLK_P     : time := 10 ns;

    function slv_to_string(slv : std_logic_vector) return string is
    variable result : string(1 to slv'length);
    variable idx    : integer := 1;
    begin
        for i in slv'reverse_range loop
            result(idx) := std_logic'image(slv(i))(2);
            idx := idx + 1;
        end loop;
        return result;
    end function;

    procedure chk1(sig : std_logic; exp : std_logic; name : string) is
    begin
        assert sig = exp
            report "FAIL: "&name&" got="&std_logic'image(sig)&" exp="&std_logic'image(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;
begin
    clk <= not clk after CLK_P/2;

    dut: entity work.interrupt_ctrl
        port map(clk=>clk, rst=>rst, irq_lines=>irq_lines, mie=>mie,
                 mepc_in=>mepc_in, mepc_out=>mepc_out, mcause_out=>mcause_out,
                 reg_addr=>reg_addr, reg_wr_en=>reg_wr_en,
                 reg_wr_data=>reg_wr_data, reg_rd_data=>reg_rd_data,
                 irq_taken=>irq_taken, mtvec=>mtvec);

    stim: process
    begin
        report "=== INTERRUPT CTRL TESTBENCH START ===" severity note;
        rst <= '1'; wait until rising_edge(clk); wait for 1 ns;
        rst <= '0';

        -- No interrupt: mie=0 even with pending line
        irq_lines <= "0001"; mie <= '0'; wait for 1 ns;
        chk1(irq_taken, '0', "IRQ masked: mie=0, irq_taken=0");

        -- Enable IRQ0 via MMIO register
        reg_wr_en <= '1'; reg_addr <= "00"; reg_wr_data <= "0001";
        wait until rising_edge(clk); wait for 1 ns;
        reg_wr_en <= '0';

        -- Still not taken until mie=1
        mie <= '1'; wait for 1 ns;
        chk1(irq_taken, '1', "IRQ0 enabled+pending+mie=1: taken");

        -- mtvec must be 0x100
        assert mtvec = x"00000100"
            report "FAIL: mtvec wrong: " & slv_to_string(mtvec)
            severity error;
        report "PASS: mtvec = 0x00000100" severity note;

        -- mcause bit 31 set, cause = 0
        assert mcause_out = x"80000000"
            report "FAIL: mcause wrong"
            severity error;
        report "PASS: mcause = 0x80000000 (IRQ0)" severity note;

        -- mepc saved on irq_taken
        wait until rising_edge(clk); wait for 1 ns;
        assert mepc_out = x"00000200"
            report "FAIL: mepc not saved" severity error;
        report "PASS: mepc saved = 0x00000200" severity note;

        -- Clear pending IRQ0 via SW write
        irq_lines <= "0000";
        reg_wr_en <= '1'; reg_addr <= "01"; reg_wr_data <= "0001";
        wait until rising_edge(clk); wait for 1 ns;
        reg_wr_en <= '0'; wait for 1 ns;
        chk1(irq_taken, '0', "IRQ0 cleared: irq_taken=0");

        -- Priority: IRQ0 and IRQ2 both pending, IRQ0 wins
        reg_wr_en <= '1'; reg_addr <= "00"; reg_wr_data <= "0101";  -- enable IRQ0+IRQ2
        wait until rising_edge(clk); wait for 1 ns;
        reg_wr_en <= '0';
        irq_lines <= "0101";
        wait until rising_edge(clk); wait for 1 ns;
        assert mcause_out = x"80000000"
            report "FAIL: priority wrong, expected IRQ0 cause=0" severity error;
        report "PASS: priority: IRQ0 beats IRQ2, mcause=0" severity note;

        report "=== INTERRUPT CTRL TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;
end architecture sim;