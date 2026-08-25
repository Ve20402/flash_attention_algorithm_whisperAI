library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity tb_fa_axis_top is
end tb_fa_axis_top;

architecture sim of tb_fa_axis_top is
    constant HEADS_TB : integer := 2;
    constant ROWS_G : integer := 8;
    constant B_G    : integer := 4;
    constant BC_G   : integer := 4;
    constant COLS_G : integer := HEADS_TB * 64;   
    constant TOTAL  : integer := ROWS_G * COLS_G; 

    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';
    signal running : boolean := true;

    signal run, all_done : std_logic := '0';

    signal s_tvalid, s_tready, s_tlast : std_logic;
    signal s_tdata : std_logic_vector(31 downto 0);
    signal s_tkeep : std_logic_vector(3 downto 0) := (others => '1');
    signal m_tvalid, m_tready, m_tlast : std_logic;
    signal m_tdata : std_logic_vector(63 downto 0);
    signal m_tkeep : std_logic_vector(7 downto 0);

    function q618(n : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(n * 262144, 32));
    end function;

    function fixed_to_real(v : signed; frac : integer) return real is
        variable acc : real := 0.0;
        variable n   : integer := v'length;
    begin
        for i in 0 to n - 2 loop
            if v(i) = '1' then acc := acc + 2.0 ** (i - frac); end if;
        end loop;
        if v(n - 1) = '1' then acc := acc - 2.0 ** (n - 1 - frac); end if;
        return acc;
    end function;
begin

    clk_proc : process
    begin
        while running loop
            aclk <= '0'; wait for 5 ns;
            aclk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    dut : entity work.fa_axis_top
        generic map (HEADS => HEADS_TB, ROWS_G => ROWS_G, B_G => B_G, BC_G => BC_G, COLS_G => COLS_G)
        port map (
            aclk => aclk, aresetn => aresetn,
            run => run, all_done => all_done,
            s_axis_tvalid => s_tvalid, s_axis_tready => s_tready,
            s_axis_tdata => s_tdata, s_axis_tkeep => s_tkeep,
            s_axis_tlast => s_tlast,
            m_axis_tvalid => m_tvalid, m_axis_tready => m_tready,
            m_axis_tdata => m_tdata, m_axis_tkeep => m_tkeep,
            m_axis_tlast => m_tlast
        );

    producer : process
        procedure axis_send(data : std_logic_vector(31 downto 0)) is
        begin
            s_tdata  <= data;
            s_tvalid <= '1';
            loop
                wait until rising_edge(aclk);
                exit when s_tready = '1'; 
            end loop;
            s_tvalid <= '0';
        end procedure;
    begin
        s_tvalid <= '0';
        s_tlast  <= '0';
        wait until aresetn = '1';
        wait until rising_edge(aclk);

        for qi in 0 to (ROWS_G / B_G) - 1 loop
            for h in 0 to HEADS_TB - 1 loop
                for r in 0 to B_G - 1 loop           
                    for d in 0 to 63 loop
                        axis_send(q618(1));
                    end loop;
                end loop;
                for jblk in 0 to (ROWS_G / BC_G) - 1 loop
                    for c in 0 to BC_G - 1 loop      
                        for d in 0 to 63 loop
                            axis_send(q618(1));
                        end loop;
                    end loop;
                    for c in 0 to BC_G - 1 loop       
                        for d in 0 to 63 loop
                            if jblk = 0 then
                                axis_send(q618((d mod 8) + 1));
                            else
                                axis_send(q618((d mod 8) + 5));
                            end if;
                        end loop;
                    end loop;
                end loop;
            end loop;
        end loop;
        wait;
    end process;

    monitor : process
        variable count, errors, tlast_err : integer := 0;
        variable d_local : integer;
        variable got_r, exp_r, err_r, max_err : real := 0.0;
    begin
        m_tready <= '1';
        max_err := 0.0;
        wait until aresetn = '1';
        loop
            wait until rising_edge(aclk);
            if m_tvalid = '1' and m_tready = '1' then
                got_r := fixed_to_real(signed(m_tdata(47 downto 0)), 34);
                d_local := (count mod COLS_G) mod 64;
                exp_r := real((d_local mod 8) + 3);
                err_r := abs(got_r - exp_r);
                if err_r > max_err then max_err := err_r; end if;
                if err_r > 0.05 then
                    errors := errors + 1;
                    if errors <= 8 then
                        report "count=" & integer'image(count) &
                               " got=" & real'image(got_r) & " exp=" & real'image(exp_r) severity note;
                    end if;
                end if;
                if (count mod COLS_G) = COLS_G - 1 then
                    if m_tlast /= '1' then tlast_err := tlast_err + 1; end if;
                else
                    if m_tlast /= '0' then tlast_err := tlast_err + 1; end if;
                end if;
                count := count + 1;
                exit when count = TOTAL;
            end if;
        end loop;

        report "AXIS: primljeno=" & integer'image(count) & " errors=" & integer'image(errors) &
               " tlast_err=" & integer'image(tlast_err) & " max_abs_err=" & real'image(max_err) severity note;
        if errors = 0 and tlast_err = 0 then
            report "*** FA AXIS TOP TEST PASSED ***" severity note;
        else
            report "*** FA AXIS TOP TEST FAILED ***" severity error;
        end if;
        wait until rising_edge(aclk);
        running <= false;
        wait;
    end process;

    ctrl_proc : process
    begin
        aresetn <= '0';
        run <= '0';
        wait until rising_edge(aclk);
        wait until rising_edge(aclk);
        aresetn <= '1';
        wait until rising_edge(aclk);
        run <= '1';
        wait until rising_edge(aclk);
        run <= '0';
        wait;
    end process;

end sim;
