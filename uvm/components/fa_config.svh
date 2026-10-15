class fa_config extends uvm_object;
  `uvm_object_utils(fa_config)

  real tolerance = 0.05;	
  longint unsigned timeout_cycles = 2_000_000;	
  bit random_input_gaps = 0;	
  bit random_output_stalls = 0;	
  bit random_data = 0;	
  string results_path = "fa_failure.csv";
  string status_path = "fa_status.csv";
  string pattern = "random";
  bit reset_compute = 0;
  bit reset_done = 0;
  int last_stall_cycles = 0;

  function new(string name="fa_config"); super.new(name); endfunction

  function void configure();
    if (ROWS_TB<1 || ROWS_TB>1500 || HEADS_TB<1 || HEADS_TB>8 || B_TB<1 || B_TB>32 || BC_TB<1 || BC_TB>64)
      `uvm_fatal("CONFIG","Unsupported dimension configuration")
    void'($value$plusargs("FA_PATTERN=%s",pattern));
    void'($value$plusargs("FA_LAST_STALL=%d",last_stall_cycles));
    reset_compute = $test$plusargs("FA_RESET_COMPUTE");
    if (last_stall_cycles < 0 || last_stall_cycles > 100)
      `uvm_fatal("CONFIG","FA_LAST_STALL must be in [0:100]")
    timeout_cycles = 2_000_000 + 256 * longint'(ROWS_TB)*ROWS_TB*HEADS_TB + 16*longint'(INPUT_WORDS);
    if (pattern == "zero" || pattern == "lsb") tolerance=1.0/OUTPUT_SCALE;
    void'($value$plusargs("FA_RESULTS_FILE=%s",results_path));
    void'($value$plusargs("FA_STATUS_FILE=%s",status_path));

    if ($test$plusargs("FA_BASELINE")) begin
      random_data = 0;
      random_input_gaps = 0;
      random_output_stalls = 0;
    end else if ($test$plusargs("FA_RANDOM_DATA") || $test$plusargs("FA_RANDOM_TIMING") || $test$plusargs("FA_INPUT_GAPS") || $test$plusargs("FA_OUTPUT_STALLS")) begin
      random_data = $test$plusargs("FA_RANDOM_DATA");
      random_input_gaps = $test$plusargs("FA_RANDOM_TIMING") || $test$plusargs("FA_INPUT_GAPS");
      random_output_stalls = $test$plusargs("FA_RANDOM_TIMING") || $test$plusargs("FA_OUTPUT_STALLS");
    end else begin
      random_data = 1;
      random_input_gaps = 1;
      random_output_stalls = 1;
    end
    if (!random_data && pattern != "random")
      `uvm_fatal("CONFIG","Directed patterns require FA_RANDOM_DATA")
    if (pattern == "numeric_range" &&
        (ROWS_TB != 2 || B_TB < 2 || BC_TB < 2 || reset_compute))
      `uvm_fatal("CONFIG","Numeric range probe requires two rows in one tile and no compute reset")
    if (ROWS_TB > 128 && pattern != "full_uniform")
      `uvm_fatal("CONFIG","Large runs use full_uniform to avoid huge SV dense reference")
    // Jedan reset test: cela operacija staje u jedan blok, pre prvog izlaza.
    if (reset_compute && (!random_data || pattern != "random" ||
        random_output_stalls || random_input_gaps || last_stall_cycles != 0 ||
        HEADS_TB != 1 || ROWS_TB > B_TB || ROWS_TB > BC_TB))
      `uvm_fatal("CONFIG","Compute reset requires generated random data, one tile/head and no timing stalls")
  endfunction
endclass
