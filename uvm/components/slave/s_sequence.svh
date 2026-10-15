class s_sequence extends uvm_sequence #(s_item, s_response);
  `uvm_object_utils(s_sequence)
  fa_config cfg;
  fa_timing timing;

  function new(string name="s_sequence"); super.new(name); endfunction

  task send_window(output int unsigned accepted);
    s_item req;
    s_response rsp;
    req = s_item::type_id::create("accept_window");
    req.action = s_item::ACCEPT_WINDOW;
    req.stop_before_final = cfg.last_stall_cycles > 0;
    if (cfg.random_output_stalls) begin
      if (!timing.randomize())
        `uvm_fatal("SLAVE_RANDOMIZE","Failed randomization")
      req.stall_cycles = timing.stall_cycles;
      req.ready_cycles = timing.ready_cycles;
    end else begin
      req.stall_cycles = 0;
      req.ready_cycles = 1;
    end
    start_item(req);
    finish_item(req);
    get_response(rsp);
    accepted = rsp.accepted_count;
  endtask

  task body();
    s_item req;
    s_response rsp;
    int unsigned accepted;

    timing = fa_timing::type_id::create("slave_timing");
    accepted = 0;
    while (accepted < OUTPUT_WORDS) begin
      send_window(accepted);
      if (cfg.last_stall_cycles > 0 && accepted >= OUTPUT_WORDS-1) begin
        req = s_item::type_id::create("final_stall");
        req.action = s_item::FINAL_STALL;
        req.final_stall_cycles = cfg.last_stall_cycles;
        start_item(req);
        finish_item(req);
        get_response(rsp);
        accepted = rsp.accepted_count;
      end
    end

    req = s_item::type_id::create("finish_accepting");
    req.action = s_item::ACCEPT_CONTINUOUS;
    start_item(req);
    finish_item(req);
    get_response(rsp);
  endtask
endclass

