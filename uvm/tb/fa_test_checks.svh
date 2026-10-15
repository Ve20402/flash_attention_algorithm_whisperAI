  // cekamo sve rezultate i potvrdjujemo da je dut zavrsio
  task check_completion();
    while (env.scoreboard.count < OUTPUT_WORDS) 
		@(negedge vif.aclk);
    while (vif.all_done !== 1'b1) 
		@(negedge vif.aclk);

    repeat (32) begin
      @(negedge vif.aclk);
      if (vif.all_done !== 1'b1)
        `uvm_fatal("DONE","Completion signal is not asserted")
    end
	
    if (env.master_agent.monitor.input_count != INPUT_WORDS)
      `uvm_fatal("INPUT_COUNT",$sformatf("Accepted %0d input words",env.master_agent.monitor.input_count))
    // trazene ulazne pauze i izlazni backpressure moraju se stvarno desiti
    if (cfg.random_input_gaps && env.master_agent.driver.inserted_gap_cycles == 0)
      `uvm_fatal("NO_INPUT_GAPS","No pauses")
    if (cfg.random_output_stalls && env.protocol_checker.output_wait_cycles == 0)
      `uvm_fatal("NO_BACKPRESSURE","No output VALID && !READY condition was observed")
    if (cfg.last_stall_cycles > 0 && env.protocol_checker.last_wait_cycles != cfg.last_stall_cycles)
      `uvm_fatal("LAST_STALL_COUNT",$sformatf("Expected %0d final-word wait cycles, observed %0d",
        cfg.last_stall_cycles,env.protocol_checker.last_wait_cycles))
    // tek nakon svih uslova dozvoljavamo konacni pass
    env.scoreboard.complete = 1;
	
  endtask

