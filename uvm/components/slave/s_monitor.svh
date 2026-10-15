class s_monitor extends uvm_monitor;
  `uvm_component_utils(s_monitor)
  virtual fa_if vif;
  uvm_analysis_port #(s_sample) output_ap;
  int unsigned output_count;
  int unsigned output_stall_cycles;

  function new(string name, uvm_component parent);
    super.new(name,parent);
    output_ap = new("output_ap",this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fa_if)::get(this,"","vif",vif))
      `uvm_fatal("NO_VIF","Output monitor has no virtual interface")
  endfunction

  task run_phase(uvm_phase phase);
    s_sample item;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.aresetn !== 1'b1) begin
        output_count = 0;
        output_stall_cycles = 0;
      end else begin
        if (vif.mon_cb.m_axis_tvalid === 1'b1 && vif.mon_cb.m_axis_tready === 1'b0)
          output_stall_cycles++;
        else if (vif.mon_cb.m_axis_tvalid === 1'b0)
          output_stall_cycles = 0;
        if (vif.mon_cb.m_axis_tvalid === 1'b1 && vif.mon_cb.m_axis_tready === 1'b1) begin
          item = s_sample::type_id::create("observed_output");
          item.data = vif.mon_cb.m_axis_tdata;
          item.keep = vif.mon_cb.m_axis_tkeep;
          item.last = vif.mon_cb.m_axis_tlast;
          item.stall_cycles = output_stall_cycles;
          item.output_index = output_count;
          output_ap.write(item);
          output_count++;
          output_stall_cycles = 0;
        end
      end
    end
  endtask
endclass
