class m_monitor extends uvm_monitor;
  `uvm_component_utils(m_monitor)
  virtual fa_if vif;
  uvm_analysis_port #(m_sample) input_sample_ap;
  int unsigned input_count;

  function new(string name, uvm_component parent);
    super.new(name,parent);
    input_sample_ap = new("input_sample_ap",this);
  endfunction

  function fa_matrix_kind input_matrix_kind(int unsigned word_index);
    int unsigned remaining, query_rows, key_rows;
    remaining = word_index;
    for (int query_start=0; query_start<ROWS_TB; query_start+=B_TB) begin
      query_rows = minimum(B_TB,ROWS_TB-query_start);
      for (int head=0; head<HEADS_TB; head++) begin
        if (remaining < query_rows*DIM_TB) return MATRIX_Q;
        remaining -= query_rows*DIM_TB;
        for (int key_start=0; key_start<ROWS_TB; key_start+=BC_TB) begin
          key_rows = minimum(BC_TB,ROWS_TB-key_start);
          if (remaining < key_rows*DIM_TB) return MATRIX_K;
          remaining -= key_rows*DIM_TB;
          if (remaining < key_rows*DIM_TB) return MATRIX_V;
          remaining -= key_rows*DIM_TB;
        end
      end
    end
    `uvm_fatal("INPUT_ORDER","Input index is outside the configured stream")
    return MATRIX_Q;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fa_if)::get(this,"","vif",vif))
      `uvm_fatal("NO_VIF","Input monitor has no interface")
  endfunction

  task run_phase(uvm_phase phase);
    m_sample observed;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.aresetn !== 1'b1) 
		input_count = 0;
      else if (vif.mon_cb.s_axis_tvalid === 1'b1 && vif.mon_cb.s_axis_tready === 1'b1) begin
        if (input_count >= INPUT_WORDS)
          `uvm_fatal("EXTRA_INPUT","over input words limit")
        observed = m_sample::type_id::create("observed_input");
        observed.matrix_kind = input_matrix_kind(input_count);
        observed.raw_value = $signed(vif.mon_cb.s_axis_tdata[23:0]);
        if (input_count == 0)
          `uvm_info("FIRST_INPUT",$sformatf(
            "DUT accepted Q[0][0][0]=%0d on the AXI input",
            observed.raw_value),UVM_NONE)
        input_sample_ap.write(observed);
        input_count++;
      end
    end
  endtask
endclass
