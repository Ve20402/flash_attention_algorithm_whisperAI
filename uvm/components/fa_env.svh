class fa_env extends uvm_env;
  `uvm_component_utils(fa_env)
  m_agent master_agent;
  s_agent slave_agent;
  fa_protocol_checker protocol_checker;
  fa_reset_observer reset_observer;
  fa_reference_model reference_model;
  fa_scoreboard scoreboard;
  fa_coverage coverage;

  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    master_agent = m_agent::type_id::create("master_agent",this);
    slave_agent = s_agent::type_id::create("slave_agent",this);
    protocol_checker = fa_protocol_checker::type_id::create("protocol_checker",this);
    reset_observer = fa_reset_observer::type_id::create("reset_observer",this);
    reference_model = fa_reference_model::type_id::create("reference_model",this);
    scoreboard = fa_scoreboard::type_id::create("scoreboard",this);
    coverage = fa_coverage::type_id::create("coverage",this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    master_agent.monitor.input_sample_ap.connect(coverage.input_export);
    reference_model.expected_ap.connect(scoreboard.expected_export);
    reset_observer.reset_ap.connect(scoreboard.reset_export);
    reset_observer.reset_sample_ap.connect(coverage.reset_export);
    slave_agent.monitor.output_ap.connect(scoreboard.actual_export);
    slave_agent.monitor.output_ap.connect(coverage.output_export);
  endfunction
endclass
