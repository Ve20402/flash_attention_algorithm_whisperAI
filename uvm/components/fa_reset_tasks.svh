// RUN pokrece novu operaciju posle inicijalizacije ili reseta.
task start_operation();
  @(negedge vif.aclk);
  vif.run = 1;
  repeat (4) @(negedge vif.aclk);
  vif.run = 0;
endtask

// Reset se aktivira tek kada je c_en zaista primecen tokom racunanja.
task reset_during_compute(m_sequence seq);
  env.reference_model.predict(stimulus,env.reset_observer.epoch);
  seq.start(env.master_agent.sequencer);
  if (env.master_agent.monitor.input_count != INPUT_WORDS)
    `uvm_fatal("RESET_TARGET","Not all inputs were accepted before computation")

  do @(vif.mon_cb);
  while (vif.mon_cb.compute_active !== 1'b1);
  repeat (16) @(negedge vif.aclk);
  if (vif.compute_active !== 1'b1 || vif.m_axis_tvalid !== 1'b0 ||
      vif.all_done !== 1'b0 || env.scoreboard.count != 0)
    `uvm_fatal("RESET_TARGET","Reset must interrupt active computation before the first output")
  `uvm_info("RESET_TARGET","Interrupting active computation (c_en=1)",UVM_NONE)
  vif.run = 0;
  vif.aresetn = 0;
  repeat (10) begin
    @(negedge vif.aclk);
    if (vif.compute_active !== 1'b0 || vif.m_axis_tvalid !== 1'b0 ||
        vif.m_axis_tlast !== 1'b0 || vif.all_done !== 1'b0 ||
        vif.s_axis_tready !== 1'b1)
      `uvm_fatal("RESET_CLEAR","Reset must stop computation, clear VALID/LAST/DONE and empty the input FIFO")
  end
  if (env.master_agent.monitor.input_count != 0 ||
      env.slave_agent.monitor.output_count != 0 ||
      env.scoreboard.count != 0 || env.scoreboard.expected_queue.size() != 0 ||
      env.reset_observer.compute_reset_count != 1)
    `uvm_fatal("RESET_CLEAR","Monitors, expectations or observed compute reset were not cleared correctly")

  vif.aresetn = 1;
  repeat (32) begin
    @(negedge vif.aclk);
    if (vif.run !== 1'b0 || vif.compute_active !== 1'b0 ||
        vif.m_axis_tvalid !== 1'b0 || vif.m_axis_tlast !== 1'b0 ||
        vif.all_done !== 1'b0 || vif.s_axis_tready !== 1'b1 ||
        vif.m_axis_tready !== 1'b1 || env.scoreboard.count != 0 ||
        env.slave_agent.monitor.output_count != 0 ||
        env.scoreboard.expected_queue.size() != 0)
      `uvm_fatal("RESET_STALE","Computation or output resumed without a new RUN after reset")
  end
  cfg.reset_done = 1;
  env.scoreboard.complete = 1;
  `uvm_info("RESET_STOP","Computation stopped; no output or new RUN during 32 post-reset cycles",UVM_NONE)
endtask
