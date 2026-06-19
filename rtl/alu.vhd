-- ============================================================
--  MRKK-32 CPU  —  Arithmetic & Logic Unit
--  ISA   : RISC-V RV32I
--  Author: Youness Marrakchi
-- ============================================================
--  Supported operations (sel encoding matches funct3/funct7):
--    000  ADD  / SUB   (sub flag distinguishes)
--    001  SLL           logical shift left
--    010  SLT           signed less-than
--    011  SLTU          unsigned less-than
--    100  XOR
--    101  SRL  / SRA   (arith flag distinguishes)
--    110  OR
--    111  AND
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
    port (
        -- operands
        a        : in  std_logic_vector(31 downto 0);   -- rs1 / PC
        b        : in  std_logic_vector(31 downto 0);   -- rs2 or immediate

        -- operation select
        alu_sel  : in  std_logic_vector(2 downto 0);    -- funct3 encoding
        alu_sub  : in  std_logic;                        -- 1 = SUB (when sel=000)
        alu_arith: in  std_logic;                        -- 1 = SRA (when sel=101)

        -- outputs
        result   : out std_logic_vector(31 downto 0);
        zero     : out std_logic;                        -- result == 0
        negative : out std_logic;                        -- result(31)
        overflow : out std_logic                         -- signed overflow
    );
end entity alu;

architecture rtl of alu is

    -- internal signals
    signal add_sub_result : std_logic_vector(31 downto 0);
    signal slt_result     : std_logic_vector(31 downto 0);
    signal sltu_result    : std_logic_vector(31 downto 0);
    signal shift_amt      : natural range 0 to 31;
    signal alu_out        : std_logic_vector(31 downto 0);

    -- for overflow detection
    signal a_ext  : std_logic_vector(32 downto 0);
    signal b_ext  : std_logic_vector(32 downto 0);
    signal sum_ext: std_logic_vector(32 downto 0);

begin

    -- ── shift amount is lower 5 bits of b ──────────────────
    shift_amt <= to_integer(unsigned(b(4 downto 0)));

    -- ── ADD / SUB ──────────────────────────────────────────
    add_sub_result <=
        std_logic_vector(unsigned(a) + unsigned(b))     when alu_sub = '0' else
        std_logic_vector(unsigned(a) - unsigned(b));

    -- ── SLT (signed) ──────────────────────────────────────
    slt_result <=
        std_logic_vector(to_unsigned(1, 32)) when signed(a) < signed(b) else
        (others => '0');

    -- ── SLTU (unsigned) ───────────────────────────────────
    sltu_result <=
        std_logic_vector(to_unsigned(1, 32)) when unsigned(a) < unsigned(b) else
        (others => '0');

    -- ── Main ALU mux ───────────────────────────────────────
    process(alu_sel, alu_sub, alu_arith, a, b,
            add_sub_result, slt_result, sltu_result, shift_amt)
    begin
        case alu_sel is
            when "000" =>                               -- ADD / SUB
                alu_out <= add_sub_result;

            when "001" =>                               -- SLL
                alu_out <= std_logic_vector(
                    shift_left(unsigned(a), shift_amt));

            when "010" =>                               -- SLT
                alu_out <= slt_result;

            when "011" =>                               -- SLTU
                alu_out <= sltu_result;

            when "100" =>                               -- XOR
                alu_out <= a xor b;

            when "101" =>                               -- SRL / SRA
                if alu_arith = '1' then
                    alu_out <= std_logic_vector(        -- arithmetic (sign-extend)
                        shift_right(signed(a), shift_amt));
                else
                    alu_out <= std_logic_vector(        -- logical
                        shift_right(unsigned(a), shift_amt));
                end if;

            when "110" =>                               -- OR
                alu_out <= a or b;

            when "111" =>                               -- AND
                alu_out <= a and b;

            when others =>
                alu_out <= (others => '0');
        end case;
    end process;

    -- ── Output assignments ─────────────────────────────────
    result   <= alu_out;
    zero     <= '1' when alu_out = x"00000000" else '0';
    negative <= alu_out(31);

    -- signed overflow (only meaningful for ADD/SUB)
    a_ext   <= a(31) & a;
    b_ext   <= b(31) & b;
    sum_ext <=
        std_logic_vector(signed(a_ext) + signed(b_ext)) when alu_sub = '0' else
        std_logic_vector(signed(a_ext) - signed(b_ext));
    overflow <= sum_ext(32) xor sum_ext(31);

end architecture rtl;