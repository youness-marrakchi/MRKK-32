library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_icache is end entity;

architecture sim of tb_icache is
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal cpu_addr  : std_logic_vector(31 downto 0) := (others=>'0');
    signal cpu_rd_en : std_logic := '0';
    signal cpu_data  : std_logic_vector(31 downto 0);
    signal stall_req : std_logic;
    signal mem_addr  : std_logic_vector(31 downto 0) := (others=>'0');
    signal mem_rd_en : std_logic;
    signal mem_data  : std_logic_vector(31 downto 0) := (others=>'0');
    constant CLK_P   : time := 10 ns;
begin
    clk <= not clk after CLK_P/2;

    -- Memory model: returns word index as data value
    -- Registered to avoid metavalue at t=0
    mem_model: process(clk)
    begin
        if rising_edge(clk) then
            if mem_rd_en = '1' then
                mem_data <= std_logic_vector(
                    to_unsigned(to_integer(unsigned(mem_addr)) / 4, 32));
            end if;
        end if;
    end process;

    dut: entity work.icache
        port map(clk=>clk, rst=>rst,
                 cpu_addr=>cpu_addr, cpu_rd_en=>cpu_rd_en,
                 cpu_data=>cpu_data, stall_req=>stall_req,
                 mem_addr=>mem_addr, mem_rd_en=>mem_rd_en, mem_data=>mem_data);

    stim: process
        variable stall_cycles : integer;
    begin
        report "=== ICACHE TESTBENCH START ===" severity note;
        rst <= '1'; wait until rising_edge(clk); wait for 1 ns;
        rst <= '0';

        -- Cold miss: fetch word at address 0x0
        cpu_addr  <= x"00000000"; cpu_rd_en <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        stall_cycles := 0;
        while stall_req = '1' loop
            wait until rising_edge(clk); wait for 1 ns;
            stall_cycles := stall_cycles + 1;
        end loop;
        assert stall_cycles > 0
            report "FAIL: Cold miss should have stalled" severity error;
        report "PASS: Cold miss stalled " & integer'image(stall_cycles) & " cycles" severity note;

        -- Hit: word 1 same line
        cpu_addr <= x"00000004"; wait for 1 ns;
        if stall_req = '0' then
            report "PASS: Hit word 1 same line - no stall" severity note;
        else
            report "FAIL: Hit should not stall" severity error;
        end if;

        -- Hit: last word of line (offset 7)
        cpu_addr <= x"0000001C"; wait for 1 ns;
        if stall_req = '0' then
            report "PASS: Hit last word of line - no stall" severity note;
        else
            report "FAIL: Last word should hit" severity error;
        end if;

        -- Miss: different cache line (line 1 = base addr 0x20)
        cpu_addr <= x"00000020";
        wait until rising_edge(clk); wait for 1 ns;
        stall_cycles := 0;
        while stall_req = '1' loop
            wait until rising_edge(clk); wait for 1 ns;
            stall_cycles := stall_cycles + 1;
        end loop;
        assert stall_cycles > 0
            report "FAIL: Second line cold miss should stall" severity error;
        report "PASS: Second line miss stalled " & integer'image(stall_cycles) & " cycles" severity note;

        -- First line should still hit
        cpu_addr <= x"00000000"; wait for 1 ns;
        if stall_req = '0' then
            report "PASS: First line still valid after second fill" severity note;
        else
            report "FAIL: First line evicted unexpectedly" severity error;
        end if;

        -- No-read: stall must be 0
        cpu_rd_en <= '0'; cpu_addr <= x"00000000"; wait for 1 ns;
        assert stall_req = '0'
            report "FAIL: No read should never stall" severity error;
        report "PASS: rd_en=0 never stalls" severity note;

        report "=== ICACHE TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;
end architecture sim;