-- ============================================================
--  MRKK-32 CPU  --  RV32M Multiply / Divide Unit
--  All 8 ops + RISC-V corner cases. Combinational.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mul_div_unit is
    port (
        rs1    : in  std_logic_vector(31 downto 0);
        rs2    : in  std_logic_vector(31 downto 0);
        funct3 : in  std_logic_vector(2  downto 0);
        result : out std_logic_vector(31 downto 0)
    );
end entity mul_div_unit;

architecture rtl of mul_div_unit is
    constant INT_MIN : std_logic_vector(31 downto 0) := x"80000000";
    constant NEG_ONE : std_logic_vector(31 downto 0) := x"FFFFFFFF";
    constant MAX_U   : std_logic_vector(31 downto 0) := x"FFFFFFFF";
begin
    process(rs1, rs2, funct3)
        variable a_s  : signed(31 downto 0);
        variable b_s  : signed(31 downto 0);
        variable a_u  : unsigned(31 downto 0);
        variable b_u  : unsigned(31 downto 0);
        -- 128-bit products to hold 64x64 intermediate
        variable p_ss : signed(127 downto 0);
        variable p_su : signed(127 downto 0);
        variable p_uu : unsigned(127 downto 0);
    begin
        a_s := signed(rs1);
        b_s := signed(rs2);
        a_u := unsigned(rs1);
        b_u := unsigned(rs2);

        -- extend to 64-bit, multiply -> 128-bit result, take [63:0]
        p_ss := resize(a_s, 64) * resize(b_s, 64);
        p_su := resize(a_s, 64) * signed(resize(b_u, 64));
        p_uu := resize(a_u, 64) * resize(b_u, 64);

        case funct3 is
            when "000" =>  -- MUL   lower 32
                result <= std_logic_vector(p_ss(31 downto 0));
            when "001" =>  -- MULH  upper 32 signed
                result <= std_logic_vector(p_ss(63 downto 32));
            when "010" =>  -- MULHSU upper 32
                result <= std_logic_vector(p_su(63 downto 32));
            when "011" =>  -- MULHU upper 32 unsigned
                result <= std_logic_vector(p_uu(63 downto 32));
            when "100" =>  -- DIV signed
                if b_s = 0 then                                result <= NEG_ONE;
                elsif rs1 = INT_MIN and rs2 = NEG_ONE then     result <= INT_MIN;
                else                                           result <= std_logic_vector(a_s / b_s);
                end if;
            when "101" =>  -- DIVU unsigned
                if b_u = 0 then                                result <= MAX_U;
                else                                           result <= std_logic_vector(a_u / b_u);
                end if;
            when "110" =>  -- REM signed
                if b_s = 0 then                                result <= rs1;
                elsif rs1 = INT_MIN and rs2 = NEG_ONE then     result <= x"00000000";
                else                                           result <= std_logic_vector(a_s rem b_s);
                end if;
            when "111" =>  -- REMU unsigned
                if b_u = 0 then                                result <= rs1;
                else                                           result <= std_logic_vector(a_u mod b_u);
                end if;
            when others => result <= (others => '0');
        end case;
    end process;
end architecture rtl;