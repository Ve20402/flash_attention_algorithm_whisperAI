library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity datapath_v2 is
    port (
        clk : in std_logic;
        rst : in std_logic;

        q_wr_en : in std_logic;
        q_wr_addr : in std_logic_vector(10 downto 0);
        q_wr_data : in std_logic_vector(23 downto 0);
        k_wr_en : in std_logic;
        k_wr_addr : in std_logic_vector(11 downto 0);
        k_wr_data : in std_logic_vector(23 downto 0);
        v_wr_en : in std_logic;
        v_wr_addr : in std_logic_vector(11 downto 0);
        v_wr_data : in std_logic_vector(23 downto 0);
        kv_wr_buffer : in std_logic;
        kv_rd_buffer : in std_logic;

        en : in std_logic;
        clr : in std_logic;
        sel_a : in std_logic;
        sel_b : in std_logic;
        q_rd_addr : in std_logic_vector(10 downto 0);
        k_rd_addr : in std_logic_vector(11 downto 0);
        v_rd_addr : in std_logic_vector(11 downto 0);


        s_wr_en : in std_logic;
        s_wr_addr : in std_logic_vector(10 downto 0);
        s_rd_addr : in std_logic_vector(10 downto 0);


        r_index : in unsigned(4 downto 0);
        c_index : in unsigned(5 downto 0);
        block_valid : in std_logic_vector(7 downto 0);

        load_m : in std_logic;
        en_max : in std_logic;
        m_buf_en : in std_logic;
        m_buf_init : in std_logic;
        l_buf_en : in std_logic;
        l_buf_init : in std_logic;
        l_new_init : in std_logic;
        p_acc_en : in std_logic;

        o_rd_addr : in std_logic_vector(10 downto 0);
        o_wr_en : in std_logic;
        o_wr_addr : in std_logic_vector(10 downto 0);
        o_zero_data : in std_logic;
        o_mul_data : in std_logic;
        sel_inv : in std_logic;

        o_data : out std_logic_vector(47 downto 0));
end datapath_v2;

architecture beh of datapath_v2 is
    constant N_MAC : integer := 8;
    constant SCORE_WIDTH : positive := 54;
    subtype score_t is signed(SCORE_WIDTH-1 downto 0);
    subtype score_diff_t is signed(SCORE_WIDTH downto 0);
    constant M_INIT : score_t := (SCORE_WIDTH-1 => '1', others => '0');

    function bounded_exp_arg(delta : score_diff_t) return signed is
    begin
        if delta <= to_signed(0, delta'length) then
            return to_signed(0, 32);
        elsif delta >= shift_left(to_signed(16, delta'length), 36) then
            return to_signed(16*2**20, 32);
        else
            return delta(47 downto 16);
        end if;
    end function;

    type slv24_arr   is array (0 to N_MAC-1) of std_logic_vector(23 downto 0);
    type slv48_arr   is array (0 to N_MAC-1) of std_logic_vector(47 downto 0);
    type sd24_arr    is array (0 to N_MAC-1) of signed(23 downto 0);
    type prod_arr    is array (0 to N_MAC-1) of signed(47 downto 0);
    type acc_arr     is array (0 to N_MAC-1) of score_t;
    type slv_score_arr is array (0 to N_MAC-1) of std_logic_vector(SCORE_WIDTH-1 downto 0);
    type score_buf_array is array (0 to 31) of score_t;
    type mul_arr     is array (0 to N_MAC-1) of signed(65 downto 0);
    type comp_1_arr  is array (0 to 3) of score_t;
    type comp_2_arr  is array (0 to 1) of score_t;
    type buf_array   is array (0 to 31) of signed(47 downto 0);
    type p_row_array is array (0 to 63) of signed(17 downto 0);

    signal q_data_out : std_logic_vector(23 downto 0);
    signal k_data_out : slv24_arr;
    signal v_data_out : slv24_arr;
    signal s_data_out : slv_score_arr;
    signal o_data_out : slv48_arr;

    signal k_bank_wr_addr, k_bank_rd_addr : std_logic_vector(9 downto 0);
    signal v_bank_wr_addr, v_bank_rd_addr : std_logic_vector(9 downto 0);
    signal s_bank_wr_addr, s_bank_rd_addr : std_logic_vector(7 downto 0);
    signal o_bank_wr_addr, o_bank_rd_addr : std_logic_vector(7 downto 0);
    signal k_bank_wr_en : std_logic_vector(0 to N_MAC-1);
    signal v_bank_wr_en : std_logic_vector(0 to N_MAC-1);
    signal o_bank_wr_en : std_logic_vector(0 to N_MAC-1);
    signal s_bank_sel : integer range 0 to N_MAC-1 := 0;
    signal o_bank_sel : integer range 0 to N_MAC-1 := 0;
    signal s_data : std_logic_vector(SCORE_WIDTH-1 downto 0);

    signal mac_a : signed(23 downto 0);
    signal mac_b : sd24_arr;
    signal mac_a_reg : signed(23 downto 0) := (others => '0');
    signal mac_b_reg : sd24_arr := (others => (others => '0'));
    signal prod : prod_arr := (others => (others => '0'));
    signal acc : acc_arr := (others => (others => '0'));
    signal en_mul : std_logic := '0';
    signal en_add : std_logic := '0';
    signal clr_mul : std_logic := '0';
    signal clr_add : std_logic := '0';

    signal s_val : acc_arr;
    signal max_comp_1 : comp_1_arr;
    signal max_comp_1_reg : comp_1_arr := (others => (others => '0'));
    signal max_comp_2 : comp_2_arr;
    signal max_comp_2_reg : comp_2_arr := (others => (others => '0'));
    signal comp_stablo_max : score_t;
    signal en_max_delay_1, en_max_delay_2 : std_logic := '0';

    signal m_new : score_t := (others => '0');
    signal m_old : score_t := (others => '0');
    signal m_diff : score_diff_t;
    signal s_minus_m : score_diff_t;
    signal exp_arg : signed(31 downto 0) := (others => '0');
    signal exp_arg_p : signed(31 downto 0) := (others => '0');
    signal scale : signed(17 downto 0);
    signal p_val : signed(17 downto 0);
    signal p_reg : signed(47 downto 0);
    signal inv : signed(17 downto 0);
    signal l_prod : signed(65 downto 0);
    signal l_prod_reg : signed(65 downto 0) := (others => '0');
    signal l_new : signed(47 downto 0) := (others => '0');

    signal o_scalar : signed(17 downto 0);
    signal prod_o : mul_arr;
    signal o_prod_reg : slv48_arr := (others => (others => '0'));
    signal o_acc_reg : slv48_arr := (others => (others => '0'));
    signal o_wr_data : slv48_arr := (others => (others => '0'));
    signal o_wr_en_delay_1, o_wr_en_delay_2 : std_logic := '0';
    signal o_wr_addr_delay_1, o_wr_addr_delay_2 : std_logic_vector(10 downto 0) := (others => '0');
    signal o_zero_data_delay_1, o_mul_data_delay_1 : std_logic := '0';

    signal p_row : p_row_array := (others => (others => '0'));
    signal m_buf : score_buf_array := (others => M_INIT);
    signal l_buf : buf_array := (others => (others => '0'));
    signal p_row_read : signed(17 downto 0);
    signal m_buf_read : score_t;
    signal l_buf_read : signed(47 downto 0);
    signal m_val : score_t;
    signal l_val : signed(47 downto 0);
    signal p_row_sel : std_logic_vector(23 downto 0);
    signal p_row_data : std_logic_vector(23 downto 0) := (others => '0');
    signal p_row_en : std_logic := '0';

    signal c_index_delay_1, c_index_delay_2, c_index_delay_3 : unsigned(5 downto 0) := (others => '0');
    signal p_acc_en_delay_1, p_acc_en_delay_2 : std_logic := '0';
begin
                                    --DEFINISANJE MEMORIJSKIH MODULA--\
    --q mem
    q_bram : entity work.memory
        generic map (ADDR_WIDTH => 11, DATA_WIDTH => 24)
        port map (clk_1 => clk, w_en_1 => q_wr_en,  addr_1 => q_wr_addr,
                  data_in_1 => q_wr_data, data_out_1 => open,
                  clk_2 => clk, w_en_2 => '0', addr_2 => q_rd_addr,
                  data_in_2 => (others => '0'), data_out_2 => q_data_out);
    --k banka
    gen_k_bank : for i in 0 to N_MAC - 1 generate
        kb : entity work.memory
                generic map (ADDR_WIDTH => 10, DATA_WIDTH => 24)
                port map (clk_1 => clk, w_en_1 => k_bank_wr_en(i), addr_1 => k_bank_wr_addr,
                          data_in_1 => k_wr_data, data_out_1 => open, clk_2 => clk, w_en_2 => '0',
                          addr_2 => k_bank_rd_addr, data_in_2 => (others => '0'), data_out_2 => k_data_out(i));
    end generate;
    --adresiranje po bankama
    k_bank_wr_addr <= kv_wr_buffer & k_wr_addr(11 downto 9) & k_wr_addr(5 downto 0);
    k_bank_rd_addr <= kv_rd_buffer & k_rd_addr(11 downto 9) & k_rd_addr(5 downto 0);
    --wr en za k banke
    gen_wr_en_k_bank : for i in 0 to N_MAC - 1 generate
        k_bank_wr_en(i) <= '1' when (k_wr_en = '1' and to_integer(unsigned(k_wr_addr(8 downto 6))) = i) else '0';
    end generate;
    --v banka
    gen_v_bank : for i in 0 to N_MAC - 1 generate
        vb : entity work.memory
                generic map (ADDR_WIDTH => 10, DATA_WIDTH => 24)
                port map (clk_1 => clk, w_en_1 => v_bank_wr_en(i), addr_1 => v_bank_wr_addr,
                          data_in_1 => v_wr_data, data_out_1 => open, clk_2 => clk, w_en_2 => '0',
                          addr_2 => v_bank_rd_addr, data_in_2 => (others => '0'), data_out_2 => v_data_out(i));
    end generate;
    --adresiranje po v bankama
    v_bank_wr_addr <= kv_wr_buffer & v_wr_addr(11 downto 6) & v_wr_addr(5 downto 3);
    v_bank_rd_addr <= kv_rd_buffer & v_rd_addr(11 downto 6) & v_rd_addr(5 downto 3);
    --wr en za v banke
    gen_wr_en_v_bank : for i in 0 to N_MAC - 1 generate
        v_bank_wr_en(i) <= '1' when (v_wr_en = '1' and to_integer(unsigned(v_wr_addr(2 downto 0))) = i) else '0';
    end generate;
    --s banka
    gen_s_bank : for i in 0 to N_MAC - 1 generate
        sb : entity work.memory
                generic map (ADDR_WIDTH => 8, DATA_WIDTH => SCORE_WIDTH)
                port map (clk_1 => clk, w_en_1 => s_wr_en, addr_1 => s_bank_wr_addr,
                          data_in_1 => std_logic_vector(acc(i)), data_out_1 => open, clk_2 => clk, w_en_2 => '0',
                          addr_2 => s_bank_rd_addr, data_in_2 => (others => '0'), data_out_2 => s_data_out(i));
    end generate;
    --o banka
    gen_o_bank : for i in 0 to N_MAC - 1 generate
        ob : entity work.memory
                 generic map (ADDR_WIDTH => 8, DATA_WIDTH => 48)
                 port map (clk_1 => clk, w_en_1 => o_bank_wr_en(i), addr_1 => o_bank_wr_addr,
                           data_in_1 => o_wr_data(i), data_out_1 => open, clk_2 => clk, w_en_2 => '0',
                           addr_2 => o_bank_rd_addr, data_in_2 => (others => '0'), data_out_2 => o_data_out(i));
    end generate;
    --adresiranje po s bankama
    s_bank_wr_addr <= s_wr_addr(10 downto 6) & s_wr_addr(5 downto 3);
    s_bank_rd_addr <= s_rd_addr(10 downto 6) & s_rd_addr(5 downto 3);

    process(clk)
    begin
        if rising_edge(clk) then
            s_bank_sel <= to_integer(unsigned(s_rd_addr(2 downto 0)));
        end if;
    end process;
    s_data <= s_data_out(s_bank_sel);
    o_bank_wr_addr <= o_wr_addr_delay_2(10 downto 6) & o_wr_addr_delay_2(5 downto 3);
    o_bank_rd_addr <= o_rd_addr(10 downto 6) & o_rd_addr(5 downto 3);
    gen_wr_en_o_bank : for i in 0 to N_MAC - 1 generate
        o_bank_wr_en(i) <= o_wr_en_delay_2;
    end generate;
    process(clk)
    begin
        if rising_edge(clk) then
            o_bank_sel <= to_integer(unsigned(o_rd_addr(2 downto 0)));
        end if;
    end process;
    o_data <= o_data_out(o_bank_sel);
                                --izvrsavanje algoritma--
    --prod = Q_tile[r][d] * K_tile[c][d];
    --S[r][c] = S[r][c] + prod;
    mac_a <= signed(q_data_out) when sel_a = '1' else signed(p_row_data);  
    gen_mac_b : for i in 0 to N_MAC - 1 generate
        mac_b(i) <= signed(k_data_out(i)) when sel_b = '1' else signed(v_data_out(i));
    end generate;
    --sabirac kasni 1 takt za mnozacem
    process(clk)
    begin
        if rising_edge(clk) then
            en_mul <= en;
            en_add <= en_mul;
            clr_mul <= clr;
            clr_add <= clr_mul;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mac_a_reg <= (others => '0');
            else
                mac_a_reg <= mac_a;
            end if;
        end if;
    end process;

    mac_units : for i in 0 to N_MAC - 1 generate
        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    mac_b_reg(i) <= (others => '0');
                    prod(i) <= (others => '0');
                    acc(i) <= (others => '0');
                else
                    mac_b_reg(i) <= mac_b(i);
                    if en_mul = '1' then
                        prod(i) <= mac_a_reg * mac_b_reg(i);
                    end if;
                    if en_add = '1' then
                        if clr_add = '1' then
                            acc(i) <= resize(prod(i), acc(i)'length);
                        else
                            acc(i) <= acc(i) + resize(prod(i), acc(i)'length);
                        end if;
                    end if;
                end if;
            end if;
        end process;
    end generate;
    --acc_t m_new = m_buf[r];
    --m_new = S[r][c];
    --djubre za poslednji blok koji nije potpun
    s_val_last : for i in 0 to N_MAC - 1 generate
                s_val(i) <= signed(s_data_out(i)) when block_valid(i) = '1' else M_INIT;
             end generate;
    comp_stablo_1 : for i in 0 to 3 generate
                max_comp_1(i) <= s_val(2*i) when s_val(2*i) > s_val(2*i+1) else s_val(2*i+1);
            end generate;

    comp_stablo_2 : for i in 0 to 1 generate
                max_comp_2(i) <= max_comp_1_reg(2*i) when max_comp_1_reg(2*i) > max_comp_1_reg(2*i+1) else max_comp_1_reg(2*i+1);
            end generate;

    comp_stablo_max <= max_comp_2_reg(0) when max_comp_2_reg(0) > max_comp_2_reg(1) else max_comp_2_reg(1);
    process(clk)
    begin
        if rising_edge(clk) then
            max_comp_1_reg <= max_comp_1;
            max_comp_2_reg <= max_comp_2;
            en_max_delay_1 <= en_max;
            en_max_delay_2 <= en_max_delay_1;
        end if;
    end process;
    --registar za vrednosti m_new
    process(clk)
    begin
        if rising_edge(clk) then
            if load_m = '1' then
                m_new <= m_buf_read;
                m_old <= m_buf_read; 
            elsif en_max_delay_2 = '1' and comp_stablo_max > m_new then
                m_new <= comp_stablo_max; 
            end if;
        end if;
    end process;
    --l_new = l_buf[r] * scale; l_new = l_new + p; l_buf[r] = l_new;
    --scale = (acc_t)exp_neg(m_buf[r] - m_new);
    m_diff <= resize(m_new, m_diff'length) - resize(m_old, m_diff'length);
    l_prod <= l_buf_read * scale;
    s_minus_m <= resize(m_new, s_minus_m'length) - resize(signed(s_data), s_minus_m'length);
    process(clk)
    begin
        if rising_edge(clk) then
            exp_arg <= bounded_exp_arg(m_diff);
        end if;
    end process;

    u_exp : entity work.exp_rom
            port map (clk => clk, arg => exp_arg, p => scale);

    process(clk)
    begin
        if rising_edge(clk) then
            exp_arg_p <= bounded_exp_arg(s_minus_m);
        end if;
    end process;

    u_exp_p : entity work.exp_rom
        port map (clk => clk, arg => exp_arg_p, p => p_val);

    u_recip : entity work.recip_rom
        port map (clk => clk, arg => l_buf_read(31 downto 0), inv => inv);

    process(clk)
    begin
        if rising_edge(clk) then
            l_prod_reg <= l_prod;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            c_index_delay_1 <= c_index;
            c_index_delay_2 <= c_index_delay_1;
            c_index_delay_3 <= c_index_delay_2;
            p_acc_en_delay_1 <= p_acc_en;
            p_acc_en_delay_2 <= p_acc_en_delay_1;
        end if;
    end process;
    p_row_en <= p_acc_en_delay_2;
    p_reg    <= resize(p_val, 48);

    process(clk)
    begin
        if rising_edge(clk) then
            if l_new_init = '1' then
                l_new <= l_prod_reg(63 downto 16);
            elsif p_acc_en_delay_2 = '1' then
                l_new <= l_new + p_reg;
            end if;
        end if;
    end process;
    --O_acc[r][d] = O_acc[r][d] * scale;
    o_scalar <= inv when sel_inv = '1' else scale;
    gen_o_prod : for i in 0 to N_MAC - 1 generate
        prod_o(i) <= signed(o_data_out(i)) * o_scalar;
    end generate;

    process(clk)
    begin
        if rising_edge(clk) then
            o_wr_en_delay_1 <= o_wr_en;
            o_wr_addr_delay_1 <= o_wr_addr;
            o_zero_data_delay_1 <= o_zero_data;
            o_mul_data_delay_1 <= o_mul_data;
            for i in 0 to N_MAC - 1 loop
                o_prod_reg(i) <= std_logic_vector(prod_o(i)(63 downto 16));
                o_acc_reg(i) <= std_logic_vector(signed(o_data_out(i)) + resize(acc(i), 48));
            end loop;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            o_wr_en_delay_2 <= o_wr_en_delay_1;
            o_wr_addr_delay_2 <= o_wr_addr_delay_1;
            for i in 0 to N_MAC - 1 loop
                if o_zero_data_delay_1 = '1' then
                    o_wr_data(i) <= (others => '0');
                elsif o_mul_data_delay_1 = '1' then
                    o_wr_data(i) <= o_prod_reg(i);
                else
                    o_wr_data(i) <= o_acc_reg(i);
                end if;
            end loop;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if p_row_en = '1' then
                p_row(to_integer(c_index_delay_3)) <= p_val;
            end if;
            if m_buf_en = '1' then
                m_buf(to_integer(r_index)) <= m_val;
            elsif m_buf_init = '1' then
                m_buf(to_integer(r_index)) <= M_INIT;
            end if;
            if l_buf_en = '1' then
                l_buf(to_integer(r_index)) <= l_val;
            elsif l_buf_init = '1' then
                l_buf(to_integer(r_index)) <= (others => '0');
            end if;
        end if;
    end process;

    m_val <= m_new;
    l_val <= l_new;
    p_row_read <= p_row(to_integer(c_index));
    m_buf_read <= m_buf(to_integer(r_index));
    l_buf_read <= l_buf(to_integer(r_index));
    p_row_sel <= std_logic_vector(resize(p_row_read, 24));

    process(clk)
    begin
        if rising_edge(clk) then
            p_row_data <= p_row_sel;
        end if;
    end process;
end architecture;
