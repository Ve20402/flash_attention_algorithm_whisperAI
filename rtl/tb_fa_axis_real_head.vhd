library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use std.textio.all;
use std.env.all;

entity tb_fa_axis_real_head is
end tb_fa_axis_real_head;

architecture sim of tb_fa_axis_real_head is
    constant INPUT_FILE  : string := "../data/matrice/rtl_head3_qblock0_in.bin";
    constant GOLDEN_FILE : string := "../data/matrice/rtl_head3_qblock0_golden.txt";
    constant ABS_TOLERANCE : real := 1.0e-2;

    constant HEADS_TB     : integer := 1;
    constant ROWS_TB      : integer := 1500;
    constant QUERY_ROWS_TB : integer := 32;
    constant B_TB         : integer := 32;
    constant BC_TB        : integer := 64;
    constant COLS_TB      : integer := 64;
    constant HEAD_DIM     : integer := 64;

    constant INPUT_WORDS : integer := HEADS_TB *
        (QUERY_ROWS_TB * HEAD_DIM + 2 * ROWS_TB * HEAD_DIM);
    constant OUTPUT_WORDS : integer := QUERY_ROWS_TB * COLS_TB;

    type binary_file_t is file of character;

    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';
    signal run, all_done : std_logic := '0';
    signal s_tvalid : std_logic := '0';
    signal s_tready : std_logic;
    signal s_tlast  : std_logic := '0';
    signal s_tdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_tkeep  : std_logic_vector(3 downto 0) := (others => '1');
    signal m_tvalid : std_logic;
    signal m_tready : std_logic := '1';
    signal m_tlast  : std_logic;
    signal m_tdata  : std_logic_vector(63 downto 0);
    signal m_tkeep  : std_logic_vector(7 downto 0);
    signal input_progress  : integer range 0 to INPUT_WORDS := 0;
    signal output_progress : integer range 0 to OUTPUT_WORDS := 0;

    function q1434_to_real(value : signed(47 downto 0)) return real is
        variable upper : integer;
        variable middle : integer;
        variable lower : integer;
    begin
        upper := to_integer(value(47 downto 32));
        middle := to_integer(unsigned(value(31 downto 16)));
        lower := to_integer(unsigned(value(15 downto 0)));
        return real(upper) * 2.0**(-2) +
               real(middle) * 2.0**(-18) +
               real(lower) * 2.0**(-34);
    end function;
begin
    aclk <= not aclk after 5 ns;

    dut : entity work.fa_axis_top
        generic map (
            HEADS => HEADS_TB,
            ROWS_G => ROWS_TB,
            B_G => B_TB,
            BC_G => BC_TB,
            COLS_G => COLS_TB
        )
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

    control : process
    begin
        aresetn <= '0';
        run <= '0';
        wait for 100 ns;
        wait until rising_edge(aclk);
        aresetn <= '1';
        wait until rising_edge(aclk);
        run <= '1';
        wait until rising_edge(aclk);
        run <= '0';
        wait;
    end process;

    producer : process
        file input_stream : binary_file_t open read_mode is INPUT_FILE;
        variable word_value : std_logic_vector(31 downto 0);

        procedure read_word_le(
            file stream_file : binary_file_t;
            variable value : out std_logic_vector(31 downto 0)
        ) is
            variable current_byte : character;
        begin
            for byte_index in 0 to 3 loop
                assert not endfile(stream_file)
                    report "Neocekivan kraj one-head RTL ulaznog fajla" severity failure;
                read(stream_file, current_byte);
                value(8 * byte_index + 7 downto 8 * byte_index) :=
                    std_logic_vector(to_unsigned(character'pos(current_byte), 8));
            end loop;
        end procedure;

        procedure axis_send(data : std_logic_vector(31 downto 0); last : std_logic) is
        begin
            s_tdata <= data;
            s_tlast <= last;
            s_tvalid <= '1';
            loop
                wait until rising_edge(aclk);
                exit when s_tready = '1';
            end loop;
            s_tvalid <= '0';
            s_tlast <= '0';
        end procedure;
    begin
        wait until aresetn = '1';
        wait until rising_edge(aclk);

        for word_index in 0 to INPUT_WORDS - 1 loop
            read_word_le(input_stream, word_value);
            if word_index = INPUT_WORDS - 1 then
                axis_send(word_value, '1');
            else
                axis_send(word_value, '0');
            end if;
            input_progress <= word_index + 1;
            if (word_index + 1) mod 8192 = 0 then
                report "ONE HEAD INPUT PROGRESS: " &
                       integer'image(word_index + 1) & "/" &
                       integer'image(INPUT_WORDS) & " words sent"
                    severity note;
            end if;
        end loop;

        assert endfile(input_stream)
            report "One-head RTL ulaz sadrzi vise podataka od ocekivanog" severity failure;
        report "ONE HEAD: poslato " & integer'image(INPUT_WORDS) & " ulaznih reci"
            severity note;
        wait;
    end process;

    monitor : process
        file golden_stream : text open read_mode is GOLDEN_FILE;
        variable input_line : line;
        variable expected_value : real;
        variable actual_value : real;
        variable absolute_error : real;
        variable maximum_error : real := 0.0;
        variable squared_error_sum : real := 0.0;
        variable error_count : integer := 0;
        variable tlast_errors : integer := 0;
        variable output_count : integer := 0;
    begin
        wait until aresetn = '1';

        while output_count < OUTPUT_WORDS loop
            wait until rising_edge(aclk);
            if m_tvalid = '1' and m_tready = '1' then
                assert not endfile(golden_stream)
                    report "One-head golden je kraci od RTL izlaza" severity failure;
                readline(golden_stream, input_line);
                read(input_line, expected_value);

                actual_value := q1434_to_real(signed(m_tdata(47 downto 0)));
                absolute_error := abs(actual_value - expected_value);
                squared_error_sum := squared_error_sum + absolute_error * absolute_error;
                if absolute_error > maximum_error then
                    maximum_error := absolute_error;
                end if;
                if absolute_error > ABS_TOLERANCE then
                    error_count := error_count + 1;
                    if error_count <= 10 then
                        report "ONE HEAD mismatch index=" & integer'image(output_count) &
                               " rtl=" & real'image(actual_value) &
                               " python=" & real'image(expected_value) &
                               " abs_err=" & real'image(absolute_error)
                            severity note;
                    end if;
                end if;

                if output_count mod COLS_TB = COLS_TB - 1 then
                    if m_tlast /= '1' then tlast_errors := tlast_errors + 1; end if;
                elsif m_tlast /= '0' then
                    tlast_errors := tlast_errors + 1;
                end if;
                output_count := output_count + 1;
                output_progress <= output_count;
            end if;
        end loop;

        assert endfile(golden_stream)
            report "One-head golden sadrzi vise podataka od RTL izlaza" severity failure;

        report "ONE HEAD: izlaza=" & integer'image(output_count) &
               " errors=" & integer'image(error_count) &
               " tlast_errors=" & integer'image(tlast_errors) &
               " max_abs=" & real'image(maximum_error) &
               " rms=" & real'image(sqrt(squared_error_sum / real(OUTPUT_WORDS)))
            severity note;

        assert error_count = 0
            report "*** ONE-HEAD REAL-DATA RTL TEST FAILED: numericke greske ***"
            severity failure;
        assert tlast_errors = 0
            report "*** ONE-HEAD REAL-DATA RTL TEST FAILED: TLAST greske ***"
            severity failure;
        report "*** ONE-HEAD REAL-DATA RTL TEST PASSED ***" severity note;
        finish;
    end process;

    heartbeat : process
    begin
        wait until aresetn = '1';
        loop
            wait for 5 ms;
            report "ONE HEAD PROGRESS: sim_time=" & time'image(now) &
                   " input=" & integer'image(input_progress) &
                   "/" & integer'image(INPUT_WORDS) &
                   " output=" & integer'image(output_progress) &
                   "/" & integer'image(OUTPUT_WORDS)
                severity note;
        end loop;
    end process;

    watchdog : process
    begin
        wait for 500 ms;
        assert false report "*** ONE-HEAD REAL-DATA RTL TEST TIMEOUT ***" severity failure;
    end process;
end sim;
