class s_driver extends uvm_driver #(s_item, s_response);
  `uvm_component_utils(s_driver)
  virtual fa_if vif;
  int unsigned accepted_count;

  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fa_if)::get(this,"","vif",vif))
      `uvm_fatal("NO_VIF","Slave driver has no virtual interface")
  endfunction

  task count_ready_cycles(int unsigned cycles, bit stop_before_final);
    for (int unsigned cycle=0; cycle<cycles; cycle++) begin
      @(vif.mon_cb);
      if (vif.mon_cb.aresetn !== 1'b1) begin
        accepted_count = 0;
      end else if (vif.mon_cb.m_axis_tvalid === 1'b1 &&
                   vif.mon_cb.m_axis_tready === 1'b1) begin
        accepted_count++;
        if (stop_before_final && accepted_count >= OUTPUT_WORDS-1)
          return;
      end
    end
  endtask

  task run_phase(uvm_phase phase);
    s_item req;
    s_response rsp;
    accepted_count = 0;
    vif.m_axis_tready = 1'b1;

    forever begin
      seq_item_port.get_next_item(req);
      case (req.action)
        s_item::ACCEPT_WINDOW: begin
          if (req.stall_cycles > 0) begin
            @(negedge vif.aclk);
            vif.m_axis_tready = 1'b0;
            repeat (req.stall_cycles) begin
              @(negedge vif.aclk);
              if (vif.aresetn !== 1'b1) 
				accepted_count = 0;
            end
          end
          @(negedge vif.aclk);
          vif.m_axis_tready = 1'b1;
          count_ready_cycles(req.ready_cycles, req.stop_before_final);
        end
        s_item::ACCEPT_CONTINUOUS: begin
          @(negedge vif.aclk);
          vif.m_axis_tready = 1'b1;
        end
        s_item::FINAL_STALL: begin
          @(negedge vif.aclk);
          vif.m_axis_tready = 1'b0;
          do @(vif.mon_cb);
          while (vif.mon_cb.m_axis_tvalid !== 1'b1);
          if (vif.mon_cb.m_axis_tlast !== 1'b1)
            `uvm_fatal("LAST_STALL","Expected final word when arming directed stall")
          repeat (req.final_stall_cycles-1) @(vif.mon_cb);
          @(negedge vif.aclk);
          vif.m_axis_tready = 1'b1;
          count_ready_cycles(1, 0);
          `uvm_info("LAST_STALL",$sformatf("Released final word after %0d stalled cycles",req.final_stall_cycles),UVM_NONE)
        end
        default: `uvm_fatal("SLAVE_ACTION","Unknown slave agent request")
      endcase
      rsp = s_response::type_id::create("rsp");
      rsp.set_id_info(req);
      rsp.accepted_count = accepted_count;
      seq_item_port.item_done(rsp);
    end
  endtask
endclass
