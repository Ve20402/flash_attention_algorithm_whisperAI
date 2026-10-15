class fa_protocol_checker extends uvm_component;
  `uvm_component_utils(fa_protocol_checker)
  virtual fa_if vif;
  bit input_pending = 0, output_pending = 0;
  logic [36:0] previous_input;
  logic [72:0] previous_output;
  int unsigned input_wait_cycles = 0;
  int unsigned output_wait_cycles = 0;
  int unsigned last_wait_cycles = 0;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fa_if)::get(this,"","vif",vif))
      `uvm_fatal("NO_VIF","Protocol checker has no virtual interface")
  endfunction
  
  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.aresetn !== 1'b1) begin
        input_pending = 0;
        output_pending = 0;
      end else begin
        // kontrolni signali ne smeju imati nepoznate vrednosti
        if ($isunknown({vif.mon_cb.s_axis_tvalid, vif.mon_cb.s_axis_tready, vif.mon_cb.m_axis_tvalid, vif.mon_cb.m_axis_tready}))
          `uvm_fatal("AXIS_UNKNOWN","Unknown value on AXI stream handshake signals")
		  
        // tokom ulaznog cekanja valid i payload moraju ostati stabilni
        if (input_pending && (vif.mon_cb.s_axis_tvalid !== 1'b1 || {vif.mon_cb.s_axis_tdata,vif.mon_cb.s_axis_tkeep,vif.mon_cb.s_axis_tlast} !== previous_input))
          `uvm_fatal("INPUT_HOLD","Testbench withdrew or changed an unaccepted input word")
        // tokom izlaznog cekanja dut mora zadrzati istu rec
        if (output_pending && (vif.mon_cb.m_axis_tvalid !== 1'b1 || {vif.mon_cb.m_axis_tdata,vif.mon_cb.m_axis_tkeep,vif.mon_cb.m_axis_tlast} !== previous_output))
          `uvm_fatal("OUTPUT_HOLD","DUT withdrew or changed an unaccepted output word")
		  
        // pamtimo handshake koji jos nije zavrsen i brojimo cikluse cekanja
        input_pending = vif.mon_cb.s_axis_tvalid && !vif.mon_cb.s_axis_tready;
        output_pending = vif.mon_cb.m_axis_tvalid && !vif.mon_cb.m_axis_tready;
        previous_input = {vif.mon_cb.s_axis_tdata,vif.mon_cb.s_axis_tkeep,vif.mon_cb.s_axis_tlast};
        previous_output = {vif.mon_cb.m_axis_tdata,vif.mon_cb.m_axis_tkeep,vif.mon_cb.m_axis_tlast};
		
        if (input_pending) 
			input_wait_cycles++;
        if (output_pending) begin
          output_wait_cycles++;
          if (vif.mon_cb.m_axis_tlast === 1'b1) last_wait_cycles++;
        end
      end
    end
  endtask
endclass
