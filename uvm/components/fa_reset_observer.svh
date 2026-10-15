class fa_reset_observer extends uvm_component;
  `uvm_component_utils(fa_reset_observer)
  virtual fa_if vif;
  uvm_analysis_port #(int) reset_ap;
  uvm_analysis_port #(fa_reset_sample) reset_sample_ap;
  bit in_reset;
  bit was_computing;
  int epoch;
  int unsigned compute_reset_count;

  function new(string name, uvm_component parent);
    super.new(name,parent);
    reset_ap = new("reset_ap",this);
    reset_sample_ap = new("reset_sample_ap",this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fa_if)::get(this,"","vif",vif))
      `uvm_fatal("NO_VIF","Reset observer has no virtual interface")
  endfunction

  task run_phase(uvm_phase phase);
    fa_reset_sample observed_reset;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.aresetn === 1'b0) begin
        if (!in_reset) begin
          epoch++;
          reset_ap.write(epoch);
          // Pocetni reset ne uzorkujemo kao funkcionalni reset test.
          if (epoch > 1) begin
            observed_reset = fa_reset_sample::type_id::create("observed_reset");
            observed_reset.epoch = epoch;
            observed_reset.during_compute = was_computing;
            if (was_computing) compute_reset_count++;
            reset_sample_ap.write(observed_reset);
          end
        end
        in_reset = 1;
        was_computing = 0;
      end else begin
        in_reset = 0;
        was_computing = vif.mon_cb.compute_active === 1'b1;
      end
    end
  endtask
endclass
