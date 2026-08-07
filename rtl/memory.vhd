library IEEE;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_1164.ALL;

entity memory is
 generic (ADDR_WIDTH : integer := 11;
          DATA_WIDTH : integer := 24
          );
 Port (clk_1 : in std_logic;
       w_en_1 : in std_logic;
       addr_1 : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
       data_in_1 : in std_logic_vector(DATA_WIDTH - 1 downto 0);
       data_out_1 : out std_logic_vector(DATA_WIDTH - 1 downto 0);

       clk_2 : in std_logic;
       w_en_2 : in std_logic;
       addr_2 : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
       data_in_2 : in std_logic_vector(DATA_WIDTH - 1 downto 0);
       data_out_2 : out std_logic_vector(DATA_WIDTH - 1 downto 0));
end memory;

architecture Behavioral of memory is
type bram_type is array (0 to (2**ADDR_WIDTH)- 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
shared variable BRAM : bram_type := (others => (others => '0'));

begin
    process(clk_1)
    begin
        if (rising_edge(clk_1)) then
            if w_en_1 = '1' then
                BRAM(to_integer(unsigned(addr_1))) := data_in_1;
            end if;
            -- citanje uvek radi, ne gejtuje se upisom
            data_out_1 <= BRAM(to_integer(unsigned(addr_1)));
        end if;
    end process;

    process(clk_2)
    begin
        if (rising_edge(clk_2)) then
            if w_en_2 = '1' then
                BRAM(to_integer(unsigned(addr_2))) := data_in_2;
            end if;
            data_out_2 <= BRAM(to_integer(unsigned(addr_2)));
        end if;
    end process;

end Behavioral;
