class m_sequence extends uvm_sequence #(m_item);
  `uvm_object_utils(m_sequence)
  fa_stimulus stimulus;
  int unsigned sent = 0;
  function new(string name = "m_sequence");
	super.new(name);
  endfunction
  task send_raw(int value, bit matrix_boundary = 0);
    m_item item;
    item = m_item::type_id::create("item");
    start_item(item);
    item.data = value;
    item.matrix_boundary = matrix_boundary;
    finish_item(item);
    sent++;
  endtask

  task body();
    int nr, nc;
    bit swap_kv;
    sent=0;
    swap_kv = $test$plusargs("FA_SWAP_KV");
    if (swap_kv)
      `uvm_info("KV_ORDER_INJECTION", "Sending Q, V, K instead of Q, K, V", UVM_NONE)
    for (int qs=0; qs<ROWS_TB; qs+=B_TB) begin
      nr=minimum(B_TB,ROWS_TB-qs);
      for (int h=0; h<HEADS_TB; h++) begin
        for (int r=0; r<nr; r++)
          for (int d=0; d<DIM_TB; d++) begin
            send_raw(stimulus.q_values[h][qs+r][d]);
          end
        for (int ks=0; ks<ROWS_TB; ks+=BC_TB) begin
          nc=minimum(BC_TB,ROWS_TB-ks);
          for (int r=0; r<nc; r++)
            for (int d=0; d<DIM_TB; d++) begin
              send_raw(swap_kv ? stimulus.v_values[h][ks+r][d] : stimulus.k_values[h][ks+r][d], r == 0 && d == 0);
            end
          for (int r=0; r<nc; r++)
            for (int d=0; d<DIM_TB; d++) begin
              send_raw(swap_kv ? stimulus.k_values[h][ks+r][d] : stimulus.v_values[h][ks+r][d], r == 0 && d == 0);
            end
        end
      end
    end
  endtask
endclass

