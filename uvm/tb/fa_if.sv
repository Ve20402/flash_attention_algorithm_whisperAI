`timescale 1ns/1ps
interface fa_if(input logic aclk);
  logic aresetn;
  logic run;
  wire all_done;
  wire compute_active;
  logic s_axis_tvalid;
  wire s_axis_tready;
  logic [31:0] s_axis_tdata;	
  logic [3:0] s_axis_tkeep;
  logic s_axis_tlast;
  wire m_axis_tvalid;
  logic m_axis_tready;
  wire [63:0] m_axis_tdata;
  wire [7:0] m_axis_tkeep;
  wire m_axis_tlast;

  initial begin	
    #1ps;
    aresetn = 0;
    run = 0;
    s_axis_tvalid = 0;
    s_axis_tdata = 0;
    s_axis_tkeep = '1;	
    s_axis_tlast = 0;
    m_axis_tready = 1;
  end

  logic [4:0] debug_pre_edge = 'x;
  initial begin
    forever begin
      @(negedge aclk);
      #4.999;	
      debug_pre_edge = {aresetn, s_axis_tvalid, s_axis_tready,
                        m_axis_tvalid, m_axis_tready};
      if ($time <= 120ns)
        $display("[FA_PRE_EDGE] t=%0t resetn=%b s_valid=%b s_ready=%b m_valid=%b m_ready=%b",
          $time, aresetn, s_axis_tvalid, s_axis_tready, m_axis_tvalid, m_axis_tready);
    end
  end

  // zajednicki trenutak uzorkovanja axi signala na rastucoj ivici
  clocking mon_cb @(posedge aclk);
    default input #1step;	
    input aresetn, all_done, compute_active;
    input s_axis_tvalid, s_axis_tready, s_axis_tdata, s_axis_tkeep, s_axis_tlast;
    input m_axis_tvalid, m_axis_tready, m_axis_tdata;
    input m_axis_tkeep, m_axis_tlast;
  endclocking
endinterface
