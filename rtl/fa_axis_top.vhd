library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.fa_types_pkg.all;

entity fa_axis_top is
  generic (
    HEADS  : integer := 8;
    ROWS_G : integer := ROWS;   
    B_G    : integer := B;
    BC_G   : integer := BC;
    COLS_G : integer := COLS   
  );
  Port (
    aclk    : in  std_logic;
    aresetn : in  std_logic;    

    run      : in  std_logic;  
    all_done : out std_logic; 


    s_axis_tvalid : in  std_logic;
    s_axis_tready : out std_logic;
    s_axis_tdata  : in  std_logic_vector(31 downto 0);
    s_axis_tkeep  : in  std_logic_vector(3 downto 0);
    s_axis_tlast  : in  std_logic;  

    m_axis_tvalid : out std_logic;
    m_axis_tready : in  std_logic;
    m_axis_tdata  : out std_logic_vector(63 downto 0);
    m_axis_tkeep  : out std_logic_vector(7 downto 0);
    m_axis_tlast  : out std_logic
  );

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of aclk : signal is
      "xilinx.com:signal:clock:1.0 aclk CLK";
  attribute X_INTERFACE_PARAMETER of aclk : signal is
      "ASSOCIATED_BUSIF s_axis:m_axis, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000";
  attribute X_INTERFACE_INFO of aresetn : signal is
      "xilinx.com:signal:reset:1.0 aresetn RST";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is
      "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of s_axis_tvalid : signal is
      "xilinx.com:interface:axis:1.0 s_axis TVALID";
  attribute X_INTERFACE_INFO of s_axis_tready : signal is
      "xilinx.com:interface:axis:1.0 s_axis TREADY";
  attribute X_INTERFACE_INFO of s_axis_tdata : signal is
      "xilinx.com:interface:axis:1.0 s_axis TDATA";
  attribute X_INTERFACE_INFO of s_axis_tkeep : signal is
      "xilinx.com:interface:axis:1.0 s_axis TKEEP";
  attribute X_INTERFACE_INFO of s_axis_tlast : signal is
      "xilinx.com:interface:axis:1.0 s_axis TLAST";

  attribute X_INTERFACE_INFO of m_axis_tvalid : signal is
      "xilinx.com:interface:axis:1.0 m_axis TVALID";
  attribute X_INTERFACE_INFO of m_axis_tready : signal is
      "xilinx.com:interface:axis:1.0 m_axis TREADY";
  attribute X_INTERFACE_INFO of m_axis_tdata : signal is
      "xilinx.com:interface:axis:1.0 m_axis TDATA";
  attribute X_INTERFACE_INFO of m_axis_tkeep : signal is
      "xilinx.com:interface:axis:1.0 m_axis TKEEP";
  attribute X_INTERFACE_INFO of m_axis_tlast : signal is
      "xilinx.com:interface:axis:1.0 m_axis TLAST";
end fa_axis_top;

architecture Behavioral of fa_axis_top is
    signal rst : std_logic;

    signal in_wr_en, in_rd_en, in_rd_valid, in_empty, in_empty_next, in_full, in_full_next : std_logic;
    signal in_wr_data, in_rd_data : std_logic_vector(31 downto 0);

    signal out_wr_en, out_rd_en, out_rd_valid, out_empty, out_empty_next, out_full, out_full_next : std_logic;
    signal out_wr_data, out_rd_data : std_logic_vector(63 downto 0);

    signal e_start, e_done : std_logic;
    signal e_q_req, e_q_ack, e_kv_req, e_kv_ack, e_last_block : std_logic;
    signal e_r_last : unsigned(4 downto 0);
    signal e_c_last : unsigned(5 downto 0);
    signal e_q_we : std_logic; signal e_q_waddr : std_logic_vector(10 downto 0); signal e_q_wdata : std_logic_vector(23 downto 0);
    signal e_k_we : std_logic; signal e_k_waddr : std_logic_vector(11 downto 0); signal e_k_wdata : std_logic_vector(23 downto 0);
    signal e_v_we : std_logic; signal e_v_waddr : std_logic_vector(11 downto 0); signal e_v_wdata : std_logic_vector(23 downto 0);
    signal e_kv_wr_buf, e_kv_rd_buf : std_logic;
    signal e_y_req, e_y_ack : std_logic;
    signal e_dbg_en   : std_logic;
    signal e_dbg_addr : std_logic_vector(10 downto 0);

    signal o_data_dbg : std_logic_vector(47 downto 0);

    signal m_valid   : std_logic := '0';
    signal m_data    : std_logic_vector(63 downto 0) := (others => '0');
    signal fetching  : std_logic := '0';
    signal tlast_cnt : integer range 0 to COLS_G - 1 := 0;

begin

    rst <= not aresetn;

    s_axis_tready <= not in_full;
    in_wr_en      <= s_axis_tvalid and (not in_full);
    in_wr_data    <= s_axis_tdata;

    in_fifo : entity work.ring_buffer
        generic map (RAM_WIDTH => 32, RAM_DEPTH => 64)
        port map (
            clk => aclk, rst => rst,
            wr_en => in_wr_en, wr_data => in_wr_data,
            rd_en => in_rd_en, rd_valid => in_rd_valid, rd_data => in_rd_data,
            empty => in_empty, empty_next => in_empty_next,
            full => in_full, full_next => in_full_next,
            fill_count => open
        );

    engine : entity work.stream_engine
        generic map (ROWS_G => ROWS_G, B_G => B_G, BC_G => BC_G, COLS_G => COLS_G)
        port map (
            clk => aclk, rst => rst,
            run => run, all_done => all_done,
            in_rd_en => in_rd_en, in_rd_valid => in_rd_valid, in_rd_data => in_rd_data, in_empty => in_empty,
            out_wr_en => out_wr_en, out_wr_data => out_wr_data, out_full => out_full,
            c_start => e_start, c_done => e_done,
            c_q_req => e_q_req, c_q_ack => e_q_ack,
            c_kv_req => e_kv_req, c_kv_ack => e_kv_ack,
            c_last_block => e_last_block, c_r_last => e_r_last, c_c_last => e_c_last,
            q_wr_en => e_q_we, q_wr_addr => e_q_waddr, q_wr_data => e_q_wdata,
            k_wr_en => e_k_we, k_wr_addr => e_k_waddr, k_wr_data => e_k_wdata,
            v_wr_en => e_v_we, v_wr_addr => e_v_waddr, v_wr_data => e_v_wdata,
            kv_wr_buf => e_kv_wr_buf, kv_rd_buf => e_kv_rd_buf,
            c_y_req => e_y_req, c_y_ack => e_y_ack,
            dbg_en => e_dbg_en, dbg_addr => e_dbg_addr, o_data => o_data_dbg
        );

    core : entity work.top_qkt_v2
        generic map (HEADS => HEADS)
        port map (
            clk => aclk, rst => rst, start => e_start, done => e_done,
            q_req => e_q_req, q_ack => e_q_ack,
            kv_req => e_kv_req, kv_ack => e_kv_ack,
            y_req => e_y_req, y_ack => e_y_ack,
            last_block => e_last_block,
            r_last => e_r_last, c_last => e_c_last,
            q_wr_en => e_q_we, q_wr_addr => e_q_waddr, q_wr_data => e_q_wdata,
            k_wr_en => e_k_we, k_wr_addr => e_k_waddr, k_wr_data => e_k_wdata,
            v_wr_en => e_v_we, v_wr_addr => e_v_waddr, v_wr_data => e_v_wdata,
            kv_wr_buf => e_kv_wr_buf, kv_rd_buf => e_kv_rd_buf,
            dbg_en => e_dbg_en, dbg_addr => e_dbg_addr, o_data => o_data_dbg
        );

    out_fifo : entity work.ring_buffer
        generic map (RAM_WIDTH => 64, RAM_DEPTH => 64)
        port map (
            clk => aclk, rst => rst,
            wr_en => out_wr_en, wr_data => out_wr_data,
            rd_en => out_rd_en, rd_valid => out_rd_valid, rd_data => out_rd_data,
            empty => out_empty, empty_next => out_empty_next,
            full => out_full, full_next => out_full_next,
            fill_count => open
        );

    m_axis_tvalid <= m_valid;
    m_axis_tdata  <= m_data;
    m_axis_tkeep  <= (others => '1');
    m_axis_tlast  <= '1' when (m_valid = '1' and tlast_cnt = COLS_G - 1) else '0';

    process(aclk)
    begin
        if rising_edge(aclk) then
            if rst = '1' then
                m_valid   <= '0';
                fetching  <= '0';
                out_rd_en <= '0';
                tlast_cnt <= 0;
            else
                out_rd_en <= '0';

                if fetching = '1' then
                    m_data   <= out_rd_data;
                    m_valid  <= '1';
                    fetching <= '0';
                end if;

                if m_valid = '1' and m_axis_tready = '1' then
                    m_valid <= '0';
                    if tlast_cnt = COLS_G - 1 then
                        tlast_cnt <= 0;
                    else
                        tlast_cnt <= tlast_cnt + 1;
                    end if;
                end if;

                if fetching = '0' and out_empty = '0'
                   and (m_valid = '0' or (m_valid = '1' and m_axis_tready = '1')) then
                    out_rd_en <= '1';
                    fetching  <= '1';
                end if;
            end if;
        end if;
    end process;

end Behavioral;
