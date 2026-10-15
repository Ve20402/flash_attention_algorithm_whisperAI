class s_agent extends uvm_agent;
  `uvm_component_utils(s_agent)
  s_sequencer sequencer;
  s_driver driver;
  s_monitor monitor;

  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = s_monitor::type_id::create("monitor",this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = s_sequencer::type_id::create("sequencer",this);
      driver = s_driver::type_id::create("driver",this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
