library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity top_qkt_v2 is
  generic (
    HEADS : integer := 8
  );
  Port (
    clk : in  std_logic;
    rst : in  std_logic;
    start : in  std_logic;
    done : out std_logic;

    q_req : out std_logic;
    q_ack : in  std_logic;
    kv_req : out std_logic;
    kv_ack : in  std_logic;
    y_req : out std_logic;
    y_ack : in  std_logic;
    last_block : in  std_logic;
    r_last : in  unsigned(4 downto 0);
    c_last : in  unsigned(5 downto 0);

    q_wr_en : in std_logic;
    q_wr_addr : in std_logic_vector(10 downto 0);
    q_wr_data : in std_logic_vector(23 downto 0);
    k_wr_en : in std_logic;
    k_wr_addr : in std_logic_vector(11 downto 0);
    k_wr_data : in std_logic_vector(23 downto 0);
    v_wr_en : in std_logic;
    v_wr_addr : in std_logic_vector(11 downto 0);
    v_wr_data : in std_logic_vector(23 downto 0);
    kv_wr_buf : in std_logic;
    kv_rd_buf : in std_logic;

    dbg_en : in  std_logic;
    dbg_addr : in  std_logic_vector(10 downto 0);
    o_data : out std_logic_vector(47 downto 0)
  );
end top_qkt_v2;

architecture Behavioral of top_qkt_v2 is
    signal c_en, c_clr, c_sel_a, c_sel_b : std_logic;
    signal c_q_rd_addr : std_logic_vector(10 downto 0);
    signal c_k_rd_addr : std_logic_vector(11 downto 0);
    signal c_v_rd_addr : std_logic_vector(11 downto 0);

    signal c_s_wr_en : std_logic;
    signal c_s_wr_addr : std_logic_vector(10 downto 0);
    signal c_s_rd_addr : std_logic_vector(10 downto 0);

    signal c_r_index : unsigned(4 downto 0);
    signal c_c_index : unsigned(5 downto 0);
    signal c_block_valid : std_logic_vector(7 downto 0);

    signal c_load_m, c_en_max : std_logic;
    signal c_m_buf_en, c_m_buf_init : std_logic;
    signal c_l_buf_en, c_l_buf_init : std_logic;
    signal c_l_new_init, c_p_acc_en : std_logic;

    signal c_o_rd_addr : std_logic_vector(10 downto 0);
    signal c_o_wr_en : std_logic;
    signal c_o_wr_addr : std_logic_vector(10 downto 0);
    signal c_o_zero_data, c_o_mul_data, c_sel_inv : std_logic;

    signal dp_o_rd_addr : std_logic_vector(10 downto 0);
begin

    dp_o_rd_addr <= dbg_addr when dbg_en = '1' else c_o_rd_addr;

    ctrl : entity work.controlpath_real
        generic map (HEADS => HEADS)
        port map (
            clk => clk, rst => rst, start => start, done => done,

            q_tile_req  => q_req,
            q_tile_ack  => q_ack,
            kv_tile_req => kv_req,
            kv_tile_ack => kv_ack,
            output_req => y_req,
            output_ack => y_ack,
            last_block => last_block,
            last_row => r_last,
            last_column => c_last,

            en => c_en, clr => c_clr, sel_a => c_sel_a, sel_b => c_sel_b,
            q_rd_addr => c_q_rd_addr,
            k_rd_addr => c_k_rd_addr,
            v_rd_addr => c_v_rd_addr,

            s_wr_en => c_s_wr_en,
            s_wr_addr => c_s_wr_addr,
            s_rd_addr => c_s_rd_addr,

            r_index => c_r_index,
            c_index => c_c_index,
            block_valid => c_block_valid,

            load_m => c_load_m,
            en_max => c_en_max,
            m_buf_en => c_m_buf_en,
            m_buf_init => c_m_buf_init,
            l_buf_en => c_l_buf_en,
            l_buf_init => c_l_buf_init,
            l_new_init => c_l_new_init,
            p_acc_en => c_p_acc_en,

            o_rd_addr => c_o_rd_addr,
            o_wr_en => c_o_wr_en,
            o_wr_addr => c_o_wr_addr,
            o_zero_data => c_o_zero_data,
            o_mul_data => c_o_mul_data,
            sel_inv => c_sel_inv);

    dp : entity work.datapath_v2
        port map (
            clk => clk, rst => rst,

            q_wr_en => q_wr_en, q_wr_addr => q_wr_addr, q_wr_data => q_wr_data,
            k_wr_en => k_wr_en, k_wr_addr => k_wr_addr, k_wr_data => k_wr_data,
            v_wr_en => v_wr_en, v_wr_addr => v_wr_addr, v_wr_data => v_wr_data,
            kv_wr_buffer => kv_wr_buf,
            kv_rd_buffer => kv_rd_buf,

            en => c_en, clr => c_clr, sel_a => c_sel_a, sel_b => c_sel_b,
            q_rd_addr => c_q_rd_addr,
            k_rd_addr => c_k_rd_addr,
            v_rd_addr => c_v_rd_addr,

            s_wr_en => c_s_wr_en,
            s_wr_addr => c_s_wr_addr,
            s_rd_addr => c_s_rd_addr,

            r_index => c_r_index,
            c_index => c_c_index,
            block_valid => c_block_valid,

            load_m => c_load_m,
            en_max => c_en_max,
            m_buf_en => c_m_buf_en,
            m_buf_init => c_m_buf_init,
            l_buf_en  => c_l_buf_en,
            l_buf_init => c_l_buf_init,
            l_new_init => c_l_new_init,
            p_acc_en => c_p_acc_en,

            o_rd_addr => dp_o_rd_addr,
            o_wr_en => c_o_wr_en,
            o_wr_addr => c_o_wr_addr,
            o_zero_data => c_o_zero_data,
            o_mul_data  => c_o_mul_data,
            sel_inv => c_sel_inv,

            o_data => o_data);

end Behavioral;
