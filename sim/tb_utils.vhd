library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package tb_utils is
    function to_hex_string(s : std_logic_vector) return string;
end package;

package body tb_utils is
    function to_hex_string(s : std_logic_vector) return string is
        variable l : line;
    begin
        hwrite(l, s);
        return l.all;
    end function;
end package body;