library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity exp_rom is
  Port (
    clk : in  std_logic;
    arg : in  signed(31 downto 0);
    p   : out signed(17 downto 0)
  );
end exp_rom;

architecture Behavioral of exp_rom is
    constant EXP_N : integer := 2048;
    type rom_t is array (0 to EXP_N-1) of signed(17 downto 0);

    function init_rom return rom_t is
        variable t : rom_t;
        variable v : real;
    begin
        for i in 0 to EXP_N-1 loop
            v := exp(-real(i)/128.0);
            t(i) := to_signed(integer(round(v * 65536.0)), 18);
        end loop;
        return t;
    end function;

    constant EXP_ROM : rom_t := init_rom;
begin
    process(clk)
        variable ix : integer;
    begin
        if rising_edge(clk) then
            if arg >= to_signed(16*2**20, 32) then
                p <= (others => '0');
            elsif arg <= to_signed(0, 32) then
                p <= EXP_ROM(0);
            else
                ix := to_integer(shift_right(arg, 13));
                if ix > EXP_N-1 then
                    ix := EXP_N-1;
                end if;
                p <= EXP_ROM(ix);
            end if;
        end if;
    end process;
end Behavioral;
