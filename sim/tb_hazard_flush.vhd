-- ============================================================
--  MRKK-32  —  Hazard & Flush Unit Testbench
--  Tests: no hazard, load-use stall, branch flush,
--         load-use + branch simultaneous, x0 no stall
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;

entity tb_hazard_flush is end entity;

architecture sim of tb_hazard_flush is
    signal id_ex_mem_rd  : std_logic := '0';
    signal id_ex_rd_addr : std_logic_vector(4 downto 0) := "00000";
    signal if_rs1_addr   : std_logic_vector(4 downto 0) := "00000";
    signal if_rs2_addr   : std_logic_vector(4 downto 0) := "00000";
    signal branch_taken  : std_logic := '0';
    signal stall         : std_logic;
    signal flush         : std_logic;

    procedure chk(sig : std_logic; exp : std_logic; name : string) is
    begin
        assert sig = exp
            report "FAIL: " & name & " got=" & std_logic'image(sig) & " exp=" & std_logic'image(exp)
            severity error;
        report "PASS: " & name severity note;
    end procedure;
begin
    dut: entity work.hazard_flush
        port map(id_ex_mem_rd=>id_ex_mem_rd, id_ex_rd_addr=>id_ex_rd_addr,
                 if_rs1_addr=>if_rs1_addr, if_rs2_addr=>if_rs2_addr,
                 branch_taken=>branch_taken, stall=>stall, flush=>flush);

    stim: process
    begin
        report "=== HAZARD FLUSH TESTBENCH START ===" severity note;
        wait for 5 ns;

        -- No hazard: ALU instruction, no load, no branch
        id_ex_mem_rd <= '0'; id_ex_rd_addr <= "00001";
        if_rs1_addr  <= "00010"; if_rs2_addr <= "00011";
        branch_taken <= '0'; wait for 5 ns;
        chk(stall, '0', "No hazard: stall=0");
        chk(flush, '0', "No hazard: flush=0");

        -- Load-use hazard: LW x1 followed by ADD rx, x1, x2
        id_ex_mem_rd <= '1'; id_ex_rd_addr <= "00001";
        if_rs1_addr  <= "00001"; if_rs2_addr <= "00010";
        branch_taken <= '0'; wait for 5 ns;
        chk(stall, '1', "Load-use rs1 match: stall=1");
        chk(flush, '1', "Load-use rs1 match: flush=1");

        -- Load-use hazard via rs2
        id_ex_mem_rd <= '1'; id_ex_rd_addr <= "00101";
        if_rs1_addr  <= "00001"; if_rs2_addr <= "00101";
        branch_taken <= '0'; wait for 5 ns;
        chk(stall, '1', "Load-use rs2 match: stall=1");
        chk(flush, '1', "Load-use rs2 match: flush=1");

        -- Load to x0: NEVER stall (x0 is always 0, no real dependency)
        id_ex_mem_rd <= '1'; id_ex_rd_addr <= "00000";
        if_rs1_addr  <= "00000"; if_rs2_addr <= "00000";
        branch_taken <= '0'; wait for 5 ns;
        chk(stall, '0', "Load to x0: no stall");
        chk(flush, '0', "Load to x0: no flush");

        -- Branch taken, no load hazard
        id_ex_mem_rd <= '0'; id_ex_rd_addr <= "00001";
        if_rs1_addr  <= "00010"; if_rs2_addr <= "00011";
        branch_taken <= '1'; wait for 5 ns;
        chk(stall, '0', "Branch taken: no stall");
        chk(flush, '1', "Branch taken: flush=1");

        -- Load-use hazard AND branch taken simultaneously
        id_ex_mem_rd <= '1'; id_ex_rd_addr <= "00011";
        if_rs1_addr  <= "00011"; if_rs2_addr <= "00001";
        branch_taken <= '1'; wait for 5 ns;
        chk(stall, '1', "Load+branch: stall=1");
        chk(flush, '1', "Load+branch: flush=1");

        -- Clean again
        id_ex_mem_rd <= '0'; branch_taken <= '0';
        if_rs1_addr  <= "00001"; if_rs2_addr <= "00010";
        id_ex_rd_addr <= "00111"; wait for 5 ns;
        chk(stall, '0', "Clean after hazards: stall=0");
        chk(flush, '0', "Clean after hazards: flush=0");

        report "=== HAZARD FLUSH TESTBENCH COMPLETE ===" severity note;
        wait;
    end process;
end architecture sim;