class s_item extends uvm_sequence_item;
  `uvm_object_utils(s_item)
  typedef enum bit [1:0] {ACCEPT_WINDOW, ACCEPT_CONTINUOUS, FINAL_STALL} action_t;
  action_t action = ACCEPT_WINDOW;
  int unsigned stall_cycles = 1;
  int unsigned ready_cycles = 1;
  bit stop_before_final = 0;
  int unsigned final_stall_cycles = 0;
  function new(string name="s_item"); super.new(name); endfunction
endclass

class s_response extends uvm_sequence_item;
  `uvm_object_utils(s_response)
  int unsigned accepted_count;
  function new(string name="s_response"); super.new(name); endfunction
endclass

class s_sample extends uvm_sequence_item;
  `uvm_object_utils(s_sample)
  logic [63:0] data;
  logic [7:0] keep;
  logic last;
  int unsigned stall_cycles;
  int unsigned output_index;
  function new(string name = "s_sample");
	super.new(name);
  endfunction
endclass
