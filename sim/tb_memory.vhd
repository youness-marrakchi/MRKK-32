library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_memory is end entity;

architecture sim of tb_memory is
    signal clk     : std_logic := '0';
    signal wr_en   : std_logic := '0';
    signal rd_en   : std_logic := '0';
    signal addr    : std_logic_vector(31 downto 0) := (others=>'0');
    signal wr_data : std_logic_vector(31 downto 0) := (others=>'0');
    signal sz      : std_logic_vector(1 downto 0)  := "10";
    signal rd_data : std_logic_vector(31 downto 0);
    constant CLK_P : time := 10 ns;

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

    procedure chk32(sig : std_logic_vector(31 downto 0);
                    exp : std_logic_vector(31 downto 0); name : string) is
    begin
        assert sig = exp
            report "FAIL: "& name &" got=0x"&slv_to_string(sig)&" exp=0x"&slv_to_string(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;

    procedure chk8(sig : std_logic_vector(7 downto 0);
                   exp : std_logic_vector(7 downto 0); name : string) is
    begin
        assert sig = exp
            report "FAIL: "& name &" got=0x"&slv_to_string(sig)&" exp=0x"&slv_to_string(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;

    procedure chk16(sig : std_logic_vector(15 downto 0);
                    exp : std_logic_vector(15 downto 0); name : string) is
    begin
        assert sig = exp
            report "FAIL: "& name &" got=0x"&slv_to_string(sig)&" exp=0x"&slv_to_string(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;

begin
    clk <= not clk after CLK_P/2;

    dut: entity work.data_memory
        port map(clk=>clk, wr_en=>wr_en, addr=>addr, wr_data=>wr_data,
                 sz=>sz, rd_en=>rd_en, rd_data=>rd_data);

    stim: process
    begin
        report "=== DATA MEMORY TESTBENCH START ===" severity note;

        -- ── Word write + read ─────────────────────────────────
        wr_en <= '1'; addr <= x"00000000"; wr_data <= x"DEADBEEF"; sz <= "10";
        wait until rising_edge(clk); wait for 1 ns;
        wr_en <= '0'; rd_en <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        rd_en <= '0';
        wait until rising_edge(clk); wait for 1 ns;
        chk32(rd_data, x"DEADBEEF", "Word SW/LW 0xDEADBEEF at 0x0");

        -- ── Second word address ───────────────────────────────
        wr_en <= '1'; addr <= x"00000010"; wr_data <= x"12345678"; sz <= "10";
        wait until rising_edge(clk); wait for 1 ns;
        wr_en <= '0'; rd_en <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        rd_en <= '0';
        wait until rising_edge(clk); wait for 1 ns;
        chk32(rd_data, x"12345678", "Word SW/LW 0x12345678 at 0x10");

        -- ── Half-word write ───────────────────────────────────
        wr_en <= '1'; addr <= x"00000020"; wr_data <= x"0000ABCD"; sz <= "01";
        wait until rising_edge(clk); wait for 1 ns;
        wr_en <= '0'; rd_en <= '1'; sz <= "10";
        wait until rising_edge(clk); wait for 1 ns;
        rd_en <= '0';
        wait until rising_edge(clk); wait for 1 ns;
        chk16(rd_data(15 downto 0), x"ABCD", "Half SH lower 16 bits = 0xABCD");

        -- ── Byte write: write full word first, overwrite byte 0 ──
        wr_en <= '1'; addr <= x"00000040"; wr_data <= x"AABBCCDD"; sz <= "10";
        wait until rising_edge(clk); wait for 1 ns;
        -- now overwrite byte 0 only
        wr_data <= x"000000FF"; sz <= "00";
        wait until rising_edge(clk); wait for 1 ns;
        wr_en <= '0'; rd_en <= '1'; sz <= "10";
        wait until rising_edge(clk); wait for 1 ns;
        rd_en <= '0';
        wait until rising_edge(clk); wait for 1 ns;
        chk8(rd_data(7  downto 0),  x"FF", "SB byte 0 = 0xFF");
        chk8(rd_data(15 downto 8),  x"CC", "SB byte 1 preserved = 0xCC");
        chk8(rd_data(23 downto 16), x"BB", "SB byte 2 preserved = 0xBB");
        chk8(rd_data(31 downto 24), x"AA", "SB byte 3 preserved = 0xAA");

        -- ── Confirm first word still intact ───────────────────
        addr <= x"00000000"; rd_en <= '1'; sz <= "10";
        wait until rising_edge(clk); wait for 1 ns;
        rd_en <= '0';
        wait until rising_edge(clk); wait for 1 ns;
        chk32(rd_data, x"DEADBEEF", "First word still intact after byte write");

        report "=== DATA MEMORY TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;
end architecture sim;