-- ============================================================
--  MRKK-32  —  Fetch Stage Testbench
--  Tests: reset, sequential PC advance, branch redirect,
--         flush NOP injection, stall hold
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_fetch_stage is end entity;

architecture sim of tb_fetch_stage is
    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal stall         : std_logic := '0';
    signal flush         : std_logic := '0';
    signal branch_taken  : std_logic := '0';
    signal branch_target : std_logic_vector(31 downto 0) := (others=>'0');
    signal imem_addr     : std_logic_vector(31 downto 0);
    signal imem_data     : std_logic_vector(31 downto 0);
    signal pc_out        : std_logic_vector(31 downto 0);
    signal pc_plus4_out  : std_logic_vector(31 downto 0);
    signal instr_out     : std_logic_vector(31 downto 0);

    constant CLK_P : time := 10 ns;
    constant NOP   : std_logic_vector(31 downto 0) := x"00000013";

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

    procedure chk(sig : std_logic_vector(31 downto 0);
                  exp : std_logic_vector(31 downto 0); name : string) is
    begin
        assert sig = exp
            report "FAIL: " & name &
                " got=" & slv_to_string(sig) &
                " exp=" & slv_to_string(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;
begin
    clk <= not clk after CLK_P/2;
    -- simple instruction memory: imem[addr] = addr (word address)
    imem_data <= imem_addr;

    dut: entity work.fetch_stage
        port map(clk=>clk, rst=>rst, stall=>stall, flush=>flush,
                 branch_taken=>branch_taken, branch_target=>branch_target,
                 imem_addr=>imem_addr, imem_data=>imem_data,
                 pc_out=>pc_out, pc_plus4_out=>pc_plus4_out, instr_out=>instr_out);

    stim: process
    begin
        report "=== FETCH STAGE TESTBENCH START ===" severity note;

        -- reset: PC should be 0
        rst <= '1'; wait until rising_edge(clk); wait for 1 ns;
        chk(pc_out, x"00000000", "RST: PC=0");
        chk(instr_out, NOP, "RST: NOP injected");

        -- release reset, PC should advance
        rst <= '0'; wait until rising_edge(clk); wait for 1 ns;
        chk(pc_out, x"00000004", "PC advances to 4");
        chk(pc_plus4_out, x"00000008", "PC+4 = 8");

        wait until rising_edge(clk); wait for 1 ns;
        chk(pc_out, x"00000008", "PC advances to 8");

        -- branch redirect to 0x100
        branch_taken  <= '1';
        branch_target <= x"00000100";
        flush <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        branch_taken <= '0'; flush <= '0';
        chk(pc_out, x"00000100", "Branch redirect PC=0x100");
        chk(instr_out, NOP, "Flush: NOP on branch cycle");

        -- continue sequential from 0x100
        wait until rising_edge(clk); wait for 1 ns;
        chk(pc_out, x"00000104", "Sequential after branch: 0x104");

        -- stall: PC must not advance
        stall <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        chk(pc_out, x"00000104", "Stall: PC holds at 0x104");
        wait until rising_edge(clk); wait for 1 ns;
        chk(pc_out, x"00000104", "Stall: PC still holds");
        stall <= '0';

        -- resume
        wait until rising_edge(clk); wait for 1 ns;
        chk(pc_out, x"00000108", "Resume after stall: 0x108");

        report "=== FETCH STAGE TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;
end architecture sim;