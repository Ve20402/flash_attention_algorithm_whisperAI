library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

package fa_types_pkg is
    constant ROWS : integer := 1500;
    constant COLS : integer := 512;
    constant NUM_HEADS : integer := 8;
    constant HEAD_DIM : integer := 64;
    constant B  : integer := 32;
    constant BC : integer := 64;

    type mac_operand_array is array (0 to 7) of signed(23 downto 0); 
    type mac_acc_array     is array (0 to 7) of signed(47 downto 0); 

    subtype data_t is signed(23 downto 0);  --Q6.18
    subtype prob_t is signed(17 downto 0);  --Q2.16
    subtype acc_t  is signed(31 downto 0);  --Q12.20

    constant Q_tile : integer  := B * HEAD_DIM;
    constant K_tile : integer  := BC * HEAD_DIM;
    constant V_tile : integer  := BC * HEAD_DIM;
    constant O_acc  : integer  := B * HEAD_DIM;
    constant M_buf  : integer  := B;
    constant L_buf  : integer  := B;
    constant W_row  : integer  := COLS;
    constant Y_tile : integer  := B * COLS;

    component mac is
        port (
              a   : in data_t;
              b   : in data_t;
              clk : in std_logic;
              rst : in std_logic;
              en  : in std_logic;
              clr : in std_logic;
              acc : out signed(47 downto 0)
              );
        end component;

    component memory is
        generic (ADDR_WIDTH : integer := 4;
                 DATA_WIDTH : integer := 8
                );
        port (
               clk_1      : in std_logic;
               w_en_1     : in std_logic;
               addr_1     : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
               data_in_1  : in std_logic_vector(DATA_WIDTH - 1 downto 0);
               data_out_1 : out std_logic_vector(DATA_WIDTH - 1 downto 0);

               clk_2  : in std_logic;
               w_en_2 : in std_logic;
               addr_2 : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
               data_in_2  : in std_logic_vector(DATA_WIDTH - 1 downto 0);
               data_out_2 : out std_logic_vector(DATA_WIDTH - 1 downto 0)
              );
     end component;

     component sync_fifo is
         generic (
                  RAM_WIDTH : natural;
                  RAM_DEPTH : natural
                  );
        port (
              clk : in std_logic;
              rst : in std_logic;
              wr_en   : in std_logic;
              wr_data : in std_logic_vector(RAM_WIDTH - 1 downto 0);
              rd_en   : in std_logic;
              rd_valid : out std_logic;
              rd_data  : out std_logic_vector(RAM_WIDTH - 1 downto 0);

              empty : out std_logic;
              empty_next : out std_logic;
              full : out std_logic;
              full_next : out std_logic;

              fill_count : out integer range RAM_DEPTH - 1 downto 0
              );
      end component;
end package;
