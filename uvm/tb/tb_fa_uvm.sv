`timescale 1ns/1ps
module tb_fa_uvm;	
  import uvm_pkg::*;	
  import fa_pkg::*;	
  // ovde nastaje takt simulacije
  logic aclk = 0;
  always #5 aclk = ~aclk;	
  // interfejs okuplja signale izmedju testbencha i dut-a
  fa_if bus(aclk);	

  // ovde povezujemo stvarni rtl sa signalima interfejsa
  fa_axis_top #(
    .HEADS(HEADS_TB), .ROWS_G(ROWS_TB), .B_G(B_TB),
    .BC_G(BC_TB), .COLS_G(COLS_TB)
  ) dut (
    .aclk(aclk), .aresetn(bus.aresetn), .run(bus.run), .all_done(bus.all_done),
    .s_axis_tvalid(bus.s_axis_tvalid), .s_axis_tready(bus.s_axis_tready),
    .s_axis_tdata(bus.s_axis_tdata), .s_axis_tkeep(bus.s_axis_tkeep),
    .s_axis_tlast(bus.s_axis_tlast),
    .m_axis_tvalid(bus.m_axis_tvalid), .m_axis_tready(bus.m_axis_tready),
    .m_axis_tdata(bus.m_axis_tdata), .m_axis_tkeep(bus.m_axis_tkeep),
    .m_axis_tlast(bus.m_axis_tlast)
  );
  assign bus.compute_active = dut.core.c_en;
  initial begin
    // prosledjujemo interfejs uvm komponentama i pokrecemo glavni test
    uvm_config_db#(virtual fa_if)::set(null,"uvm_test_top*","vif",bus);
    run_test("fa_test");
  end
endmodule
