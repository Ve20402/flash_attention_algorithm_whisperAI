library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity recip_rom is
  Port (
    clk : in  std_logic;
    arg : in  signed(31 downto 0);
    inv : out signed(17 downto 0)
  );
end recip_rom;

architecture Behavioral of recip_rom is
    constant MANT_BITS : integer := 9;
    constant MANT_N    : integer := 2**MANT_BITS;

    type rom_t is array (0 to MANT_N-1) of unsigned(17 downto 0);

    function init_rom return rom_t is
        variable t : rom_t;
        variable m : real;
        variable v : real;
    begin
        for j in 0 to MANT_N-1 loop
            m := 1.0 + real(j) / real(MANT_N);
            v := 131072.0 / m;
            t(j) := to_unsigned(integer(round(v)), 18);
        end loop;
        return t;
    end function;

    constant RECIP_ROM : rom_t := init_rom;

    signal idx_r : integer range 0 to MANT_N-1 := 0;
    signal sh_r  : integer range 1 to 31 := 1;
    signal sat_r : std_logic := '1';
begin
    process(clk)
        variable u  : unsigned(31 downto 0);
        variable e  : integer range 15 to 30;
        variable mn : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            u := unsigned(arg);
            e := 15;
            for i in 16 to 30 loop
                if u(i) = '1' then
                    e := i;
                end if;
            end loop;

            if arg <= 0 or e = 15 then
                sat_r <= '1';
                idx_r <= 0;
                sh_r  <= 1;
            else
                sat_r <= '0';
                mn    := shift_right(u, e - MANT_BITS);
                idx_r <= to_integer(mn(MANT_BITS-1 downto 0));
                sh_r  <= e - 15;
            end if;
        end if;
    end process;

    process(clk)
        variable ext : unsigned(31 downto 0);
        variable rnd : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            if sat_r = '1' then
                inv <= to_signed(131071, 18);
            else
                ext := resize(RECIP_ROM(idx_r), 32);
                rnd := shift_left(to_unsigned(1, 32), sh_r - 1);
                inv <= signed(resize(shift_right(ext + rnd, sh_r), 18));
            end if;
        end if;
    end process;

end Behavioral;
