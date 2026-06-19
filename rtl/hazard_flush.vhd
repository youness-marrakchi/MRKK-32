-- ============================================================
--  MRKK-32 CPU  —  Hazard & Flush Control Unit
--
--  3-stage pipeline hazard analysis:
--
--  DATA HAZARDS:
--    In a 3-stage pipeline (Fetch / Decode+Exec / Writeback)
--    the register file writeback happens one cycle after
--    decode/exec.  The register_file already has
--    write-then-read forwarding built in (async read port),
--    so NO stalls are needed for ALU->ALU chains.
--
--    Load-use hazard: if EX stage is a LOAD and the
--    immediately following instruction reads the same rd,
--    we need 1 stall cycle.
--
--  CONTROL HAZARDS:
--    Branch/jump resolution happens at end of Decode/Exec.
--    The instruction already in Fetch must be flushed
--    (replaced with NOP) whenever branch_taken = '1'.
--    This gives a 1-cycle branch penalty — acceptable for
--    a 3-stage design.
--
--  Outputs:
--    stall  → freeze PC + IF/ID register (repeat fetch)
--    flush  → inject NOP into IF/ID register
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;

entity hazard_flush is
    port (
        -- current instruction in Decode/Exec stage
        id_ex_mem_rd  : in  std_logic;                     -- is it a load?
        id_ex_rd_addr : in  std_logic_vector(4 downto 0);  -- destination reg

        -- next instruction (currently in Fetch stage)
        if_rs1_addr   : in  std_logic_vector(4 downto 0);
        if_rs2_addr   : in  std_logic_vector(4 downto 0);

        -- branch/jump signal from Decode/Exec
        branch_taken  : in  std_logic;

        -- outputs
        stall         : out std_logic;
        flush         : out std_logic
    );
end entity hazard_flush;

architecture rtl of hazard_flush is

    signal load_use_hazard : std_logic;

begin

    -- ── Load-use hazard detection ─────────────────────────────
    -- Stall if: current instr is a LOAD  AND
    --           its destination == rs1 or rs2 of next instr AND
    --           destination is not x0
    load_use_hazard <=
        '1' when (
            id_ex_mem_rd = '1' and
            id_ex_rd_addr /= "00000" and
            (id_ex_rd_addr = if_rs1_addr or id_ex_rd_addr = if_rs2_addr)
        ) else '0';

    -- ── Stall: load-use hazard ────────────────────────────────
    stall <= load_use_hazard;

    -- ── Flush: branch taken OR load-use (inject bubble in EX)
    -- When a branch is taken, the instruction in Fetch is wrong.
    -- When a load-use stall fires, we inject a NOP into the
    -- pipeline slot to give the load time to complete.
    flush <= branch_taken or load_use_hazard;

end architecture rtl;