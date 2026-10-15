`uvm_analysis_imp_decl(_expected)
`uvm_analysis_imp_decl(_reset)

class fa_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fa_scoreboard)
  
  uvm_analysis_imp #(s_sample,fa_scoreboard) actual_export;
  uvm_analysis_imp_expected #(fa_expected_block,fa_scoreboard) expected_export;
  uvm_analysis_imp_reset #(int,fa_scoreboard) reset_export;
  
  real expected_queue[$];
  int active_epoch;
  fa_config cfg;
  
  int unsigned count = 0;
  real max_error = 0.0;
  bit complete = 0;

  bit inject_bad_expected;
  // Optional first-row window for the separate K/V-order experiment.
  int unsigned window_limit = 0;
  int unsigned window_failed = 0;
  real window_max_error = 0.0;
  string preview_path = "";
  string window_status_path = "";
  
  function new(string name, uvm_component parent);
    super.new(name,parent);
    actual_export = new("actual_export",this);
    expected_export = new("expected_export",this);
    reset_export = new("reset_export",this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(fa_config)::get(this,"","cfg",cfg))
      `uvm_fatal("NO_CFG","Scoreboard nema config")
    inject_bad_expected = $test$plusargs("FA_INJECT_BAD_EXPECTED");
    void'($value$plusargs("FA_COMPARE_WINDOW=%d",window_limit));
    void'($value$plusargs("FA_PREVIEW_FILE=%s",preview_path));
    void'($value$plusargs("FA_WINDOW_STATUS_FILE=%s",window_status_path));
    if (window_limit != 0 && (window_limit != 16 || preview_path == "" ||
        window_status_path == "" || cfg.reset_compute))
      `uvm_fatal("WINDOW_CONFIG","Window experiment requires 16 outputs, evidence paths and no mid-test reset")
  endfunction
  // posle reseta odbacujemo ocekivanja stare operacije
  function void write_reset(int epoch);
    active_epoch = epoch;
    expected_queue.delete();
    count = 0;
    max_error = 0.0;
    complete = 0;
  endfunction

  // primamo referentne rezultate i stavljamo ih u red po izlaznom redosledu
  function void write_expected(fa_expected_block item);
    if (item.epoch != active_epoch)
      `uvm_fatal("REFERENCE_EPOCH","Expected result belongs to another reset epoch")
    if (item.first_index != count + expected_queue.size())
      `uvm_fatal("REFERENCE_ORDER","Expected matrix blocks arrived out of order")
    foreach (item.values[i]) expected_queue.push_back(item.values[i]);
  endfunction

  // svaki prihvacen izlaz dut-a proveravamo odmah tokom simulacije
  function void write(s_sample item);
    longint signed raw;
    real got, expected, error;
    string window_result;
    int h, r, d, failure_fd, preview_fd, window_fd;
	
    if (count >= OUTPUT_WORDS)
      `uvm_fatal("EXTRA_OUTPUT","DUT produced too many output words")
    if ($isunknown({item.data,item.keep,item.last}))
      `uvm_fatal("UNKNOWN_OUTPUT",$sformatf("X/Z on output signals, index=%0d",count))
    // proveravamo sve izlazne bajtove i oznaku poslednje reci
    if (item.keep !== 8'hff)
      `uvm_fatal("TKEEP",$sformatf("index=%0d keep=%h",count,item.keep))
    if (item.last !== (count == OUTPUT_WORDS-1))
      `uvm_fatal("TLAST",$sformatf("Incorrect TLAST at index=%0d",count))
    // 48-bitni rezultat mora biti prosiren znakom na 64-bitnu magistralu
    if (item.data[63:48] !== {16{item.data[47]}})
      `uvm_fatal("SIGN_EXT","Output is not sign extended from 48 to 64 bits")
	  
    raw = $signed(item.data[47:0]);
    // izlazni fixed point broj pretvaramo u realan broj
    got = real'(raw) / OUTPUT_SCALE;
	
    if (expected_queue.size() == 0)
      `uvm_fatal("NO_EXPECTED","Output arrived without a complete observed input block")
    // uzimamo sledeci ocekivani rezultat iz referentnog modela
    expected = expected_queue.pop_front();
    if (inject_bad_expected && count == 0) 
		expected += 1.0;
    error = got - expected;
    if (error < 0.0) error = -error;
    if (error > max_error) max_error = error;
    // Log each of O[0][0..15], including elements within tolerance.
    if (preview_path != "" && count < 16) begin
      output_position(count,h,r,d);
      if (count == 0) preview_fd = $fopen(preview_path,"w");
      else preview_fd = $fopen(preview_path,"a");
      if (preview_fd == 0) `uvm_fatal("PREVIEW_OPEN","Cannot write output preview")
      if (count == 0)
        $fdisplay(preview_fd,"index,head,row,column,expected,actual,abs_error,tolerance,status");
      $fdisplay(preview_fd,"%0d,%0d,%0d,%0d,%0.12f,%0.12f,%0.12f,%0.8f,%s",
        count,h,r,d,expected,got,error,cfg.tolerance,
        error <= cfg.tolerance ? "PASS" : "FAIL");
      $fclose(preview_fd);
    end
    if (window_limit != 0 && error > window_max_error) window_max_error = error;
    // neuspeh prijavljujemo samo ako je razlika veca od tolerancije
    if (error > cfg.tolerance) begin
      output_position(count,h,r,d);
      if (window_limit == 0 || window_failed == 0) begin
        failure_fd = $fopen(cfg.results_path,"w");
        if (failure_fd != 0) begin
          $fdisplay(failure_fd,"index,head,row,column,expected,actual,abs_error,tolerance,status");
          $fdisplay(failure_fd,"%0d,%0d,%0d,%0d,%0.12f,%0.12f,%0.12f,%0.8f,FAIL",
            count,h,r,d,expected,got,error,cfg.tolerance);
          $fclose(failure_fd);
        end
      end
      if (window_limit != 0) begin
        window_failed++;
        `uvm_info("WINDOW_ELEMENT_FAIL",$sformatf(
          "O[%0d][%0d] got=%0.8f expected=%0.8f abs_error=%0.8f; continuing to 16 outputs",
          r,d,got,expected,error),UVM_NONE)
      end else begin
        `uvm_fatal("MISMATCH",$sformatf(
          "index=%0d got=%0.8f expected=%0.8f abs_error=%0.8f raw=%h",
          count,got,expected,error,item.data))
      end
    end
    count++;
    if (window_limit != 0 && count == window_limit) begin
      window_fd = $fopen(window_status_path,"w");
      if (window_fd == 0) `uvm_fatal("WINDOW_STATUS_OPEN","Cannot write window completion evidence")
      if (window_failed == 0) window_result = "WINDOW_PASS";
      else window_result = "MISMATCH";
      $fdisplay(window_fd,"checked,passed,failed,max_abs_error,status");
      $fdisplay(window_fd,"%0d,%0d,%0d,%0.12f,%s",count,count-window_failed,
        window_failed,window_max_error,window_result);
      $fclose(window_fd);
      if (window_failed != 0) begin
        `uvm_fatal("MISMATCH_WINDOW",$sformatf(
          "Checked O[0][0..15]: passed=%0d failed=%0d max_abs_error=%0.8f",
          count-window_failed,window_failed,window_max_error))
      end else begin
        `uvm_info("WINDOW_PASS","All 16 inspected elements are within tolerance; stopping this partial experiment",UVM_NONE)
        $finish;
      end
    end
	
  endfunction
  
  function bit checks_complete();
    if (cfg.reset_compute)
      return complete && cfg.reset_done && count == 0 && expected_queue.size() == 0;
    return complete && count == OUTPUT_WORDS && expected_queue.size() == 0;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!checks_complete())
      `uvm_error("INCOMPLETE","Test did not complete all checks")
  endfunction
  
  // konacni status nastaje tek posle svih provera i uvm gresaka
  function void report_phase(uvm_phase phase);
    uvm_report_server server;
    int status_fd;
    bit passed;
    super.report_phase(phase);
    server = uvm_report_server::get_server();
    passed = checks_complete() &&
        server.get_severity_count(UVM_ERROR) == 0 &&
        server.get_severity_count(UVM_FATAL) == 0;
    status_fd = $fopen(cfg.status_path,"w");
	
    if (status_fd == 0) `uvm_fatal("STATUS_OPEN","Cannot write final status file")
    $fdisplay(status_fd,"version,status,checked,max_abs_error,random_data,input_gaps,output_stalls,rows,heads,b,bc,pattern,reset_done,reset_compute");
    $fdisplay(status_fd,"%s,%s,%0d,%0.12f,%0b,%0b,%0b,%0d,%0d,%0d,%0d,%s,%0b,%0b",FA_TB_VERSION,
      passed ? "PASS" : "FAIL",count,max_error,cfg.random_data,
      cfg.random_input_gaps,cfg.random_output_stalls,ROWS_TB,HEADS_TB,B_TB,BC_TB,cfg.pattern,cfg.reset_done,cfg.reset_compute);
    $fclose(status_fd);
	
    if (passed && cfg.reset_compute)
      `uvm_info("RESET_PASS","PASS: computation interrupted by reset; no post-reset outputs or new RUN",UVM_NONE)
    else if (passed)
      `uvm_info("FA_PASS",$sformatf(
        "%s PASS: %0d outputs; random_data=%0b input_gaps=%0b output_stalls=%0b max_abs_error=%0.8f",
        FA_TB_VERSION,count,cfg.random_data,cfg.random_input_gaps,
        cfg.random_output_stalls,max_error),UVM_NONE)
    else
      `uvm_info("FA_FAIL","FAIL: pogledaj greske iznad",UVM_NONE)
  endfunction
endclass
