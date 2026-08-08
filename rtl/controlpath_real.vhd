library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity controlpath_real is
    generic (HEADS : integer := 8);
    port (clk : in  std_logic;
          rst   : in  std_logic;
          start : in  std_logic;
          done  : out std_logic;

          q_tile_req  : out std_logic;
          q_tile_ack  : in  std_logic;
          kv_tile_req : out std_logic;
          kv_tile_ack : in  std_logic;
          last_block  : in  std_logic;
          last_row    : in  unsigned(4 downto 0);
          last_column : in  unsigned(5 downto 0);
          output_req  : out std_logic;
          output_ack  : in  std_logic;

          en    : out std_logic;
          clr   : out std_logic;
          sel_a : out std_logic;
          sel_b : out std_logic;
          q_rd_addr : out std_logic_vector(10 downto 0);
          k_rd_addr : out std_logic_vector(11 downto 0);
          v_rd_addr : out std_logic_vector(11 downto 0);

          s_wr_en   : out std_logic;
          s_wr_addr : out std_logic_vector(10 downto 0);
          s_rd_addr : out std_logic_vector(10 downto 0);

          r_index     : out unsigned(4 downto 0);
          c_index     : out unsigned(5 downto 0);
          block_valid : out std_logic_vector(7 downto 0);

          load_m     : out std_logic;
          en_max     : out std_logic;
          m_buf_en   : out std_logic;
          m_buf_init : out std_logic;
          l_buf_en   : out std_logic;
          l_buf_init : out std_logic;
          l_new_init : out std_logic;
          p_acc_en   : out std_logic;

          o_rd_addr   : out std_logic_vector(10 downto 0);
          o_wr_en     : out std_logic;
          o_wr_addr   : out std_logic_vector(10 downto 0);
          o_zero_data : out std_logic;
          o_mul_data  : out std_logic;
          sel_inv     : out std_logic);
end controlpath_real;

architecture beh of controlpath_real is

    type state_type is (ST_IDLE, ST_WAIT_Q_TILE, ST_INIT, ST_WAIT_KV_TILE, ST_SET_SCORE, ST_SCORE_DRAIN,
                        ST_NEXT_SCORE, ST_MAX, ST_MAX_DRAIN, ST_SCALE, ST_PROB, ST_PROB_DRAIN, ST_PV_VALUE,
                        ST_PV_DRAIN, ST_PV_NEXT, ST_NEXT_TILE, ST_LAST_KV_BLOCK, ST_FINALIZE_INIT, ST_FINALIZE,
                        ST_FINALIZE_DRAIN, ST_FINALIZE_NEXT, ST_WAIT_OUTPUT, ST_DONE);

    constant HEAD_DIM_LAST : integer := 63;

    signal state : state_type := ST_IDLE;

    signal r_count : unsigned(4 downto 0) := (others => '0');
    signal c_count : unsigned(5 downto 0) := (others => '0');
    signal d_count : unsigned(5 downto 0) := (others => '0');
    signal h_count : unsigned(2 downto 0) := (others => '0');

    signal last_row_reg    : unsigned(4 downto 0) := (others => '1');
    signal last_column_reg : unsigned(5 downto 0) := (others => '1');
    signal last_block_reg  : std_logic := '0';

    signal drain : unsigned(2 downto 0) := (others => '0');

    signal bv : std_logic_vector(7 downto 0);
begin

    gen_block_valid : for i in 0 to 7 generate
        bv(i) <= '1' when (to_integer(c_count) + i <= to_integer(last_column_reg)) else '0';
    end generate;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= ST_IDLE;
                r_count   <= (others => '0');
                c_count   <= (others => '0');
                d_count   <= (others => '0');
                h_count   <= (others => '0');
                drain     <= (others => '0');
                en <= '0'; clr <= '0'; s_wr_en <= '0'; done <= '0';
                sel_a <= '1'; sel_b <= '1';
                load_m <= '0'; en_max <= '0';
                m_buf_en <= '0'; m_buf_init <= '0';
                l_buf_en <= '0'; l_buf_init <= '0';
                l_new_init <= '0'; p_acc_en <= '0';
                o_wr_en <= '0'; o_wr_addr <= (others => '0');
                o_zero_data <= '0'; o_mul_data <= '0'; sel_inv <= '0';
                block_valid <= (others => '0');
            else
                en <= '0'; clr <= '0'; s_wr_en <= '0'; done <= '0';
                sel_a <= '1'; sel_b <= '1';            
                load_m <= '0'; en_max <= '0';
                m_buf_en <= '0'; m_buf_init <= '0';
                l_buf_en <= '0'; l_buf_init <= '0';
                l_new_init <= '0'; p_acc_en <= '0';
                o_wr_en <= '0'; o_zero_data <= '0'; o_mul_data <= '0';
                sel_inv <= '0';
                block_valid <= bv;                  

                case state is
                    --u ovoj fazi uzimamo podatke iz BRAM-a koji je dostavio streaming block
                    when ST_IDLE =>
                        if start = '1' then
                            h_count <= (others => '0');
                            last_row_reg <= last_row; 
                            state <= ST_WAIT_Q_TILE;
                        end if;

                    when ST_WAIT_Q_TILE =>
                        if q_tile_ack = '1' then
                            d_count <= (others => '0');
                            r_count <= (others => '0');
                            state <= ST_INIT;
                        end if;

                    when ST_INIT =>
                        m_buf_init <= '1';
                        l_buf_init <= '1';
                        o_zero_data <= '1';
                        o_wr_en <= '1';
                        o_wr_addr <= std_logic_vector(r_count & d_count);
                        if (to_integer(d_count) + 8) > HEAD_DIM_LAST then
                            d_count <= (others => '0');
                            if r_count = last_row_reg then
                                r_count <= (others => '0');
                                state <= ST_WAIT_KV_TILE;
                            else
                                r_count <= r_count + 1;
                            end if;
                        else
                            d_count <= d_count + 8;
                        end if;

                    when ST_WAIT_KV_TILE =>
                        if kv_tile_ack = '1' then
                            last_column_reg <= last_column;
                            last_block_reg  <= last_block;
                            d_count <= (others => '0');
                            c_count <= (others => '0');
                            r_count <= (others => '0');
                            state <= ST_SET_SCORE;
                        end if;
                    --ovde krecemo sa izvrsavanjem algoritma koristeci podatke iz BRAM-a
                    --stanja su lepo nazvana po deo algoritma koji se izvrsava za dato stanje
                    when ST_SET_SCORE =>
                        en <= '1';
                        if d_count = 0 then
                            clr <= '1';
                        end if;
                        if d_count = HEAD_DIM_LAST then
                            drain <= (others => '0');
                            state <= ST_SCORE_DRAIN;
                        else
                            d_count <= d_count + 1;
                        end if;

                    when ST_SCORE_DRAIN =>
                        if drain = 2 then
                            s_wr_en <= '1';
                            drain <= (others => '0');
                            state <= ST_NEXT_SCORE;
                        else
                            drain <= drain + 1;
                        end if;

                    when ST_NEXT_SCORE =>
                        d_count <= (others => '0');
                        if (to_integer(c_count) + 8 > to_integer(last_column_reg)) then
                            c_count <= (others => '0');
                            if r_count = last_row_reg then
                                r_count <= (others => '0');
                                state <= ST_MAX;
                            else
                                r_count <= r_count + 1;
                                state <= ST_SET_SCORE;
                            end if;
                        else
                            c_count <= c_count + 8;
                            state <= ST_SET_SCORE;
                        end if;


                    when ST_MAX =>
                        en_max <= '1';
                        if c_count = 0 then
                            load_m <= '1';
                        end if;
                        if (to_integer(c_count) + 8 > to_integer(last_column_reg)) then
                            c_count <= (others => '0');
                            drain <= (others => '0');
                            state <= ST_MAX_DRAIN;
                        else
                            c_count <= c_count + 8;
                        end if;

                    when ST_MAX_DRAIN =>
                        if drain = 5 then
                            drain <= (others => '0');
                            l_new_init <= '1';
                            state <= ST_SCALE;
                        else
                            drain <= drain + 1;
                        end if;

                    when ST_SCALE =>
                        o_wr_en <= '1';
                        sel_inv <= '0';
                        o_mul_data <= '1';
                        o_wr_addr <= std_logic_vector(r_count & d_count);
                        if to_integer(d_count) + 8 > HEAD_DIM_LAST then
                            d_count <= (others => '0');
                            state <= ST_PROB;
                        else
                            d_count <= d_count + 8;
                        end if;

                    when ST_PROB =>
                        p_acc_en <= '1';
                        if c_count = last_column_reg then
                            c_count <= (others => '0');
                            drain <= (others => '0');
                            state <= ST_PROB_DRAIN;
                        else
                            c_count <= c_count + 1;
                        end if;

                    when ST_PROB_DRAIN =>
                        if drain = 2 then
                            drain <= (others => '0');
                            state <= ST_PV_VALUE;
                        else
                            drain <= drain + 1;
                        end if;

                    when ST_PV_VALUE =>
                        en <= '1';
                        sel_a <= '0';
                        sel_b <= '0';
                        if c_count = 0 then
                            clr <= '1';
                        end if;

                        if c_count = last_column_reg then
                            c_count <= (others => '0');
                            drain <= (others => '0');
                            state <= ST_PV_DRAIN;
                        else
                            c_count <= c_count + 1;
                        end if;

                    when ST_PV_DRAIN =>
                        if drain = 2 then
                            o_wr_en <= '1';
                            o_mul_data <= '0';
                            o_wr_addr <= std_logic_vector(r_count & d_count);
                            drain <= (others => '0');
                            state <= ST_PV_NEXT;
                        else
                            drain <= drain + 1;
                        end if;

                    when ST_PV_NEXT =>
                        if to_integer(d_count) + 8 > HEAD_DIM_LAST then
                            d_count <= (others => '0');
                            m_buf_en <= '1';
                            l_buf_en <= '1';
                            state <= ST_NEXT_TILE;
                        else
                            d_count <= d_count + 8;
                            state <= ST_PV_VALUE;
                        end if;


                    when ST_NEXT_TILE =>
                        c_count <= (others => '0');
                        d_count <= (others => '0');
                        if r_count = last_row_reg then
                            r_count <= (others => '0');
                            state <= ST_LAST_KV_BLOCK;
                        else
                            r_count <= r_count + 1;
                            state <= ST_MAX;
                        end if;

                    when ST_LAST_KV_BLOCK =>
                        if last_block_reg = '1' then
                            state <= ST_FINALIZE_INIT;
                        else
                            state <= ST_WAIT_KV_TILE;
                        end if;

                    when ST_FINALIZE_INIT =>
                        if drain = 1 then
                            drain <= (others => '0');
                            state <= ST_FINALIZE;
                        else
                            drain <= drain + 1;
                        end if;

                    when ST_FINALIZE =>
                        sel_inv <= '1';
                        o_mul_data <= '1';
                        o_wr_en <= '1';
                        o_wr_addr <= std_logic_vector(r_count & d_count);
                        if to_integer(d_count) + 8 > HEAD_DIM_LAST then
                            drain <= (others => '0');
                            d_count <= (others => '0');
                            state <= ST_FINALIZE_DRAIN;
                        else
                            d_count <= d_count + 8;
                        end if;

                    when ST_FINALIZE_DRAIN =>
                        if drain = 1 then
                            drain <= (others => '0');
                            state <= ST_FINALIZE_NEXT;
                        else
                            drain <= drain + 1;
                        end if;

                    when ST_FINALIZE_NEXT =>
                        if r_count = last_row_reg then
                            r_count <= (others => '0');
                            state <= ST_WAIT_OUTPUT;
                        else
                            r_count <= r_count + 1;
                            state <= ST_FINALIZE_INIT;
                        end if;

                    when ST_WAIT_OUTPUT =>
                        if output_ack = '1' then
                            if to_integer(h_count) = HEADS - 1 then
                                state <= ST_DONE;
                            else
                                h_count <= h_count + 1;
                                state <= ST_WAIT_Q_TILE;
                            end if;
                        end if;

                    when ST_DONE =>
                        done <= '1';
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process;

    q_rd_addr <= std_logic_vector(r_count & d_count);   -- Q[r][d]
    k_rd_addr <= std_logic_vector(c_count & d_count);   -- K[c][d]
    v_rd_addr <= std_logic_vector(c_count & d_count);   -- V[c][d]
    s_wr_addr <= std_logic_vector(r_count & c_count);   -- S[r][c]
    s_rd_addr <= std_logic_vector(r_count & c_count);   
    o_rd_addr <= std_logic_vector(r_count & d_count);   -- O[r][d]

    r_index <= r_count;
    c_index <= c_count;

    q_tile_req  <= '1' when state = ST_WAIT_Q_TILE  else '0';
    kv_tile_req <= '1' when state = ST_WAIT_KV_TILE else '0';
    output_req  <= '1' when state = ST_WAIT_OUTPUT  else '0';

end architecture;
