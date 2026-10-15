// Pomocni objekat za slucajne vrednosti matrica.
class fa_random_value extends uvm_object;
  `uvm_object_utils(fa_random_value)
  rand int value;
  constraint small_signed { value inside {[-4:4]}; }
  function new(string name="fa_random_value"); super.new(name); endfunction
endclass

// Ogranicenja za pauze pri slanju i prihvatanju transakcija.
class fa_timing extends uvm_object;
  `uvm_object_utils(fa_timing)
  rand int unsigned gap_cycles;
  rand int unsigned ready_cycles;
  rand int unsigned stall_cycles;
  constraint legal_timing {
    gap_cycles inside {[0:12]};
    ready_cycles inside {[1:8]};
    stall_cycles inside {[1:20]};
  }
  function new(string name="fa_timing"); super.new(name); endfunction
endclass

class fa_expected_block extends uvm_sequence_item;
  `uvm_object_utils(fa_expected_block)
  int epoch, first_index;
  real values[];
  function new(string name="fa_expected_block"); super.new(name); endfunction
endclass

class fa_reset_sample extends uvm_object;
  `uvm_object_utils(fa_reset_sample)
  int epoch;
  bit during_compute;
  function new(string name="fa_reset_sample"); super.new(name); endfunction
endclass
