class m_driver extends uvm_driver #(m_item);
	`uvm_component_utils(m_driver)
	virtual fa_if vif;
	fa_config cfg;
	fa_timing timing;
	int unsigned inserted_gap_cycles = 0;

	function new(string name, uvm_component parent);
		super.new(name,parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual fa_if)::get(this,"","vif",vif))
			`uvm_fatal("NO_VIF","Master driver has no virtual interface")
		if (!uvm_config_db#(fa_config)::get(this,"","cfg",cfg))
			`uvm_fatal("NO_CFG","Master driver has no configuration")
		timing = fa_timing::type_id::create("input_timing");
	endfunction

  task run_phase(uvm_phase phase);
	m_item item;
	wait (vif.aresetn === 1'b1);
	forever begin
		  seq_item_port.get_next_item(item);

      @(negedge vif.aclk);

      if (cfg.random_input_gaps) begin
        if (item.matrix_boundary) begin
          if (!timing.randomize() with { gap_cycles > 0; })
            `uvm_fatal("RANDOMIZE","Failed to randomize an inter-matrix gap")
        end else if (!timing.randomize())
          `uvm_fatal("RANDOMIZE","Failed to randomize an input gap")
        inserted_gap_cycles += timing.gap_cycles;
        repeat (timing.gap_cycles)
			@(negedge vif.aclk);
     end

      //transaction to data
      vif.s_axis_tdata = item.data;
      vif.s_axis_tvalid = 1;
      //waiting for dut to raise signal tready.
      do @(vif.mon_cb);
	  while (vif.mon_cb.s_axis_tready !== 1'b1);
      @(negedge vif.aclk);
      vif.s_axis_tvalid = 0;
      seq_item_port.item_done();
    end
  endtask
endclass
