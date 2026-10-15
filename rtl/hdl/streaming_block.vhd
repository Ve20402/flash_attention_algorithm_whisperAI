library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.fa_types_pkg.all;

entity stream_engine is
  generic (
    ROWS_G : integer := ROWS;
    B_G : integer := B;
    BC_G : integer := BC;
    COLS_G : integer := COLS
  );
  Port (
    clk : in std_logic;
    rst : in std_logic;

    run : in  std_logic;
    all_done : out std_logic;

    in_rd_en : out std_logic;
    in_rd_valid : in  std_logic;
    in_rd_data : in  std_logic_vector(31 downto 0);
    in_empty : in  std_logic;

    out_wr_en : out std_logic;
    out_wr_data : out std_logic_vector(63 downto 0);
    out_full : in  std_logic;

    c_start : out std_logic;
    c_done : in  std_logic;
    c_q_req : in  std_logic;
    c_q_ack : out std_logic;
    c_kv_req : in  std_logic;
    c_kv_ack : out std_logic;
    c_y_req : in  std_logic;
    c_y_ack : out std_logic;
    c_last_block : out std_logic;
    c_r_last : out unsigned(4 downto 0);
    c_c_last : out unsigned(5 downto 0);

    q_wr_en   : out std_logic;
    q_wr_addr : out std_logic_vector(10 downto 0);
    q_wr_data : out std_logic_vector(23 downto 0);
    k_wr_en   : out std_logic;
    k_wr_addr : out std_logic_vector(11 downto 0);
    k_wr_data : out std_logic_vector(23 downto 0);
    v_wr_en   : out std_logic;
    v_wr_addr : out std_logic_vector(11 downto 0);
    v_wr_data : out std_logic_vector(23 downto 0);
    kv_wr_buf : out std_logic;
    kv_rd_buf : out std_logic;

    dbg_en   : out std_logic;
    dbg_addr : out std_logic_vector(10 downto 0);
    o_data   : in  std_logic_vector(47 downto 0)
  );
end stream_engine;

architecture Behavioral of stream_engine is
    type state_t is (IDLE, QI_SETUP, HEAD,
                     Q_REQ, Q_STREAM, Q_ACK, Q_SETTLE,
                     KV_SET, K_REQ, K_STREAM, V_REQ, V_STREAM,
                     KV_SERVE, KV_SETTLE,
                     Y_DRAIN_ADDR, Y_DRAIN_PUSH, Y_ACK, Y_ACK_SETTLE,
                     QI_NEXT, DONE);
    signal state : state_t := IDLE;

    signal qi : unsigned(10 downto 0) := (others => '0');   
    signal j  : unsigned(10 downto 0) := (others => '0');   

    signal br_reg : unsigned(5 downto 0) := (others => '0');
    signal bc_reg : unsigned(6 downto 0) := (others => '0');

    signal r_count : unsigned(4 downto 0) := (others => '0');   
    signal c_count : unsigned(5 downto 0) := (others => '0');   
    signal d_count : unsigned(5 downto 0) := (others => '0');

    signal in_fixed : signed(23 downto 0);

    signal wr_buf, rd_buf : std_logic := '0';
    signal blk_is_last : std_logic := '0';
    signal done_latch : std_logic := '0'; 
begin

    process(clk)
        variable rows_left : unsigned(10 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state  <= IDLE;
                qi <= (others => '0');
                j <= (others => '0');
                r_count <= (others => '0');
                c_count <= (others => '0');
                d_count <= (others => '0');
                c_start <= '0'; c_q_ack <= '0'; c_kv_ack <= '0'; c_y_ack <= '0';
                q_wr_en <= '0'; k_wr_en <= '0'; v_wr_en <= '0';
                out_wr_en <= '0'; all_done <= '0';
                wr_buf <= '0'; rd_buf <= '0'; blk_is_last <= '0'; done_latch <= '0';
                q_wr_addr <= (others => '0'); q_wr_data <= (others => '0');
                k_wr_addr <= (others => '0'); k_wr_data <= (others => '0');
                v_wr_addr <= (others => '0'); v_wr_data <= (others => '0');
                out_wr_data <= (others => '0');
                c_last_block <= '0'; c_c_last <= (others => '0');
                br_reg <= (others => '0'); bc_reg <= (others => '0');
            else

                c_start <= '0'; c_q_ack <= '0'; c_kv_ack <= '0'; c_y_ack <= '0';
                q_wr_en <= '0'; k_wr_en <= '0'; v_wr_en <= '0';
                out_wr_en <= '0'; all_done <= '0';

                if c_done = '1' then
                    done_latch <= '1';
                end if;

                case state is
                    when IDLE =>
                        if run = '1' then
                            qi <= (others => '0');
                            state <= QI_SETUP;
                        end if;

                    when QI_SETUP =>
                        rows_left := to_unsigned(ROWS_G, 11) - qi;
                        if rows_left > to_unsigned(B_G, 11) then
                            br_reg <= to_unsigned(B_G, 6);
                        else
                            br_reg <= resize(rows_left, 6);
                        end if;
                        j <= (others => '0');
                        done_latch <= '0';
                        c_start <= '1';
                        state <= HEAD;

                    when HEAD =>
                        if c_q_req = '1' then
                            r_count <= (others => '0');
                            d_count <= (others => '0');
                            j <= (others => '0');
                            state <= Q_REQ;
                        elsif c_y_req = '1' then
                            r_count <= (others => '0');
                            d_count <= (others => '0');
                            state <= Y_DRAIN_ADDR;
                        elsif done_latch = '1' then
                            done_latch <= '0';
                            r_count <= (others => '0');
                            state <= QI_NEXT;
                        end if;

                    when Q_REQ =>
                        if in_empty = '0' then
                            state <= Q_STREAM;
                        end if;

                    when Q_STREAM =>
                        q_wr_en <= '1';
                        q_wr_addr <= std_logic_vector(r_count & d_count);
                        q_wr_data <= std_logic_vector(in_fixed);
                        if d_count = 63 then
                            d_count <= (others => '0');
                            if r_count = br_reg - 1 then
                                r_count <= (others => '0');
                                state <= Q_ACK;
                            else
                                r_count <= r_count + 1;
                                state <= Q_REQ;
                            end if;
                        else
                            d_count <= d_count + 1;
                            state <= Q_REQ;      
                        end if;

                    when Q_ACK =>
                        c_q_ack <= '1';
                        state <= Q_SETTLE;

                    when Q_SETTLE =>
                        if c_q_req = '0' then           
                            state <= KV_SET;
                        end if;

                    when KV_SET =>
                        rows_left := to_unsigned(ROWS_G, 11) - j;
                        if rows_left > to_unsigned(BC_G, 11) then
                            bc_reg <= to_unsigned(BC_G, 7);
                            c_last_block <= '0';
                            blk_is_last <= '0';
                        else
                            bc_reg <= resize(rows_left, 7);
                            c_last_block <= '1';
                            blk_is_last <= '1';
                        end if;
                        c_count <= (others => '0');
                        d_count <= (others => '0');
                        state <= K_REQ;

                    when K_REQ =>
                        if in_empty = '0' then
                            state <= K_STREAM;
                        end if;

                    when K_STREAM =>
                        k_wr_en <= '1';
                        k_wr_addr <= std_logic_vector(c_count & d_count);
                        k_wr_data <= std_logic_vector(in_fixed);
                        if d_count = 63 then
                            d_count <= (others => '0');
                            if c_count = bc_reg - 1 then
                                c_count <= (others => '0');
                                state <= V_REQ;
                            else
                                c_count <= c_count + 1;
                                state <= K_REQ;
                            end if;
                        else
                            d_count <= d_count + 1;
                            state <= K_REQ;
                        end if;

                    when V_REQ =>
                        if in_empty = '0' then
                            state <= V_STREAM;
                        end if;

                    when V_STREAM =>
                        v_wr_en <= '1';
                        v_wr_addr <= std_logic_vector(c_count & d_count);
                        v_wr_data <= std_logic_vector(in_fixed);
                        if d_count = 63 then
                            d_count <= (others => '0');
                            if c_count = bc_reg - 1 then
                                c_count <= (others => '0');
                                c_c_last <= resize(bc_reg - 1, 6);
                                state <= KV_SERVE;
                            else
                                c_count <= c_count + 1;
                                state <= V_REQ;
                            end if;
                        else
                            d_count <= d_count + 1;
                            state <= V_REQ;
                        end if;

                    when KV_SERVE =>
                        if c_kv_req = '1' then
                            c_kv_ack <= '1';
                            rd_buf <= wr_buf;
                            state <= KV_SETTLE;
                        end if;

                    when KV_SETTLE =>
                        if c_kv_req = '0' then
                            if blk_is_last = '1' then
                                state <= HEAD;
                            else
                                wr_buf <= not wr_buf;
                                j <= j + bc_reg;
                                state <= KV_SET;
                            end if;
                        end if;

                    when Y_DRAIN_ADDR =>
                        state <= Y_DRAIN_PUSH;

                    when Y_DRAIN_PUSH =>
                        if out_full = '0' then
                            out_wr_en <= '1';
                            out_wr_data <= std_logic_vector(resize(signed(o_data), 64));
                            if d_count = 63 then
                                d_count <= (others => '0');
                                if r_count = br_reg - 1 then
                                    r_count <= (others => '0');
                                    state <= Y_ACK;
                                else
                                    r_count <= r_count + 1;
                                    state <= Y_DRAIN_ADDR;
                                end if;
                            else
                                d_count <= d_count + 1;
                                state <= Y_DRAIN_ADDR;
                            end if;
                        end if;

                    when Y_ACK =>
                        c_y_ack <= '1';
                        state <= Y_ACK_SETTLE;

                    when Y_ACK_SETTLE =>
                        if c_y_req = '0' then
                            state <= HEAD;
                        end if;

                    when QI_NEXT =>
                        if qi + br_reg > to_unsigned(ROWS_G, 11) - 1 then
                            state <= DONE;
                        else
                            qi <= qi + br_reg;
                            state <= QI_SETUP;
                        end if;

                    when DONE =>
                        all_done <= '1';
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    in_fixed <= signed(in_rd_data(23 downto 0));
    c_r_last <= resize(br_reg - 1, 5);
    kv_wr_buf <= wr_buf;
    kv_rd_buf <= rd_buf;

    dbg_en <= '1' when (state = Y_DRAIN_ADDR or state = Y_DRAIN_PUSH) else '0';
    dbg_addr <= std_logic_vector(r_count & d_count);

    in_rd_en <= '1' when (state = Q_REQ or state = K_REQ or state = V_REQ) and in_empty = '0' else '0';

end Behavioral;
