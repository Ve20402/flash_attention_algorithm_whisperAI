`uvm_analysis_imp_decl(_coverage_output)
`uvm_analysis_imp_decl(_coverage_reset)

class fa_coverage extends uvm_component;
  `uvm_component_utils(fa_coverage)
  uvm_analysis_imp #(m_sample, fa_coverage) input_export;
  uvm_analysis_imp_coverage_output #(s_sample, fa_coverage) output_export;
  uvm_analysis_imp_coverage_reset #(fa_reset_sample, fa_coverage) reset_export;
  longint unsigned total_inputs, total_outputs;

  // binovi za q, k i v vrednosti koje je dut stvarno prihvatio
  covergroup input_cg with function sample(fa_matrix_kind matrix_kind, int raw_value);
    option.per_instance = 1;
    matrix_cp: coverpoint matrix_kind {
      bins q = {MATRIX_Q};
      bins k = {MATRIX_K};
      bins v = {MATRIX_V};
    }
    q_value_cp: coverpoint raw_value iff (matrix_kind == MATRIX_Q) {
      bins negative_value = {[INPUT_MIN:-2]};
      bins minus_lsb = {-INPUT_LSB};
      bins zero = {0};
      bins plus_lsb = {INPUT_LSB};
      bins positive_value = {[2:INPUT_MAX]};
    }
    k_value_cp: coverpoint raw_value iff (matrix_kind == MATRIX_K) {
      bins negative_value = {[INPUT_MIN:-1]};
      bins zero = {0};
      bins positive_value = {[1:INPUT_MAX]};
    }
    v_value_cp: coverpoint raw_value iff (matrix_kind == MATRIX_V) {
      bins negative_value = {[INPUT_MIN:-2]};
      bins minus_lsb = {-INPUT_LSB};
      bins zero = {0};
      bins plus_lsb = {INPUT_LSB};
      bins positive_value = {[2:INPUT_MAX]};
    }
  endgroup

  // binovi za obicne i poslednje izlaze sa razlicitim cekanjem
  covergroup output_cg with function sample(bit last_word, int stalls);
    option.per_instance = 1;
    last_cp: coverpoint last_word { 
		bins ordinary = {0}; 
		bins final_word = {1}; 
	}
    ordinary_stall_cp: coverpoint stalls iff (last_word == 0) {
      bins none = {0}; 
      bins short_wait = {[1:8]};
      bins long_wait = {[9:2147483647]};
    }
    final_stall_cp: coverpoint stalls iff (last_word == 1) {
      bins none = {0};
      bins long_wait = {[9:2147483647]};
    }
  endgroup

  // binovi za glave i pune ili nepotpune blokove
  covergroup shape_cg with function sample(int head, bit q_tail, bit kv_tail);
    option.per_instance = 1;
    head_cp: coverpoint head { 
	bins heads[] = {[0:7]}; 
	}
    q_tail_cp: coverpoint q_tail { 
	bins full_tile = {0}; 
	bins partial_tile = {1}; 
	}
    kv_tail_cp: coverpoint kv_tail { 
	bins divisible = {0}; 
	bins remainder = {1}; 
	}
  endgroup

  // Jedini dodatni reset scenario prekida aktivno racunanje.
  covergroup reset_cg with function sample(bit during_compute);
    option.per_instance = 1;
    compute_cp: coverpoint during_compute {
      bins interrupted_compute = {1};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name,parent);
    input_export = new("input_export", this);
	output_export = new("output_export", this);
    reset_export = new("reset_export", this);
    input_cg = new();
	output_cg = new(); 
	shape_cg = new(); 
	reset_cg = new();
    total_inputs=0;
    total_outputs=0;
  endfunction

  // ulazni monitor ovde pokrece uzorkovanje ulazne pokrivenosti
  function void write(m_sample item);
    input_cg.sample(item.matrix_kind, item.raw_value);
    total_inputs++;
  endfunction
  
  // izlazni monitor ovde pokrece uzorkovanje izlaza i oblika bloka
  function void write_coverage_output(s_sample item);
	output_cg.sample(item.last, item.stall_cycles);
	sample_output_shape(item.output_index);
	total_outputs++;
  endfunction

  // Pocetni reset se ne salje u funkcionalnu pokrivenost.
  function void write_coverage_reset(fa_reset_sample item);
    reset_cg.sample(item.during_compute);
  endfunction

  // iz indeksa izlaza izvodimo glavu i da li je blok nepotpun
  function void sample_output_shape(int output_index);
    int head, row, column;
    int q_block_index, first_q_row, remaining_rows, rows_in_q_block;
    bit partial_q_block, partial_kv_block;
    output_position(output_index,head,row,column);
    q_block_index = row / B_TB;
    first_q_row = q_block_index * B_TB;
    remaining_rows = ROWS_TB - first_q_row;
    rows_in_q_block = minimum(B_TB,remaining_rows);
    partial_q_block = rows_in_q_block < B_TB;
    partial_kv_block = (ROWS_TB % BC_TB) != 0;
    shape_cg.sample(head,partial_q_block,partial_kv_block);
  endfunction
  
endclass
