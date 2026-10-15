class m_item extends uvm_sequence_item;
  `uvm_object_utils(m_item)
  bit [31:0] data;
  bit matrix_boundary;
  function new(string name = "m_item");
	super.new(name);
  endfunction
endclass

class m_sample extends uvm_object;
  `uvm_object_utils(m_sample)
  fa_matrix_kind matrix_kind;
  int raw_value;
  function new(string name="m_sample");
	super.new(name);
  endfunction
endclass
