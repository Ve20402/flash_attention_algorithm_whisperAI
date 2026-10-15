class fa_test extends uvm_test;
  `uvm_component_utils(fa_test)
  fa_env env;
  fa_config cfg;
  fa_stimulus stimulus;
  virtual fa_if vif;

  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = fa_config::type_id::create("cfg");
    stimulus = fa_stimulus::type_id::create("stimulus");
    cfg.configure();
    stimulus.prepare(cfg.pattern,cfg.random_data);
    uvm_config_db#(fa_config)::set(this,"env.*","cfg",cfg);	
    if (!uvm_config_db#(virtual fa_if)::get(this,"","vif",vif))
      `uvm_fatal("NO_VIF","Test has no virtual interface")
    env = fa_env::type_id::create("env",this);	
  endfunction

  `include "fa_test_checks.svh"
  `include "fa_reset_tasks.svh"

  task run_phase(uvm_phase phase);
    m_sequence input_seq;
    s_sequence output_seq;
    phase.raise_objection(this);
    input_seq = m_sequence::type_id::create("input_seq");
    input_seq.stimulus = stimulus;
    output_seq = s_sequence::type_id::create("output_seq");
    output_seq.cfg = cfg;

    fork
      begin : watchdog	
        repeat (cfg.timeout_cycles) @(negedge vif.aclk);
        `uvm_fatal("TIMEOUT",$sformatf("input=%0d/%0d output=%0d/%0d done=%b",
          env.master_agent.monitor.input_count,INPUT_WORDS,env.scoreboard.count,OUTPUT_WORDS,vif.all_done))
      end
      begin : scenario	
        // Pocetni reset sluzi inicijalizaciji svih testova.
        repeat (10) @(negedge vif.aclk);
        vif.aresetn = 1;
        start_operation();
        if (cfg.reset_compute) begin
          reset_during_compute(input_seq);
        end else begin
          env.reference_model.predict(stimulus,env.reset_observer.epoch);
          fork
            input_seq.start(env.master_agent.sequencer);
            output_seq.start(env.slave_agent.sequencer);
          join
          check_completion();
        end
      end
    join_any
    disable fork;	
    phase.drop_objection(this);	
  endtask
endclass
