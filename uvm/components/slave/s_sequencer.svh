class s_sequencer extends uvm_sequencer #(s_item, s_response);
  `uvm_component_utils(s_sequencer)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
endclass
