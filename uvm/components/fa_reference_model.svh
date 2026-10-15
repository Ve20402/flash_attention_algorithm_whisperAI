class fa_reference_model extends uvm_component;
  `uvm_component_utils(fa_reference_model)

  uvm_analysis_port #(fa_expected_block) expected_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    expected_ap = new("expected_ap", this);
  endfunction

  // pretvaramo ulazni fixed point broj u realnu vrednost
  function real to_real(int raw_value);
    return real'(raw_value) / INPUT_SCALE;
  endfunction

  function bit query_is_zero(fa_stimulus stimulus, int head, int query_row);
    for (int column = 0; column < DIM_TB; column++) begin
      if (stimulus.q_values[head][query_row][column] != 0)
        return 0;
    end
    return 1;
  endfunction

  // za jedan q red racunamo skalarni proizvod sa svakim k redom
  function void calculate_scores(
      fa_stimulus stimulus,
      int head,
      int query_row,
      output real scores[ROWS_TB]
  );
    real query_value, key_value;

    for (int key_row = 0; key_row < ROWS_TB; key_row++) begin
      scores[key_row] = 0.0;
      for (int column = 0; column < DIM_TB; column++) begin
        query_value = to_real(stimulus.q_values[head][query_row][column]);
        key_value = to_real(stimulus.k_values[head][key_row][column]);
        scores[key_row] += query_value * key_value;
      end
    end
  endfunction

  // normalizujemo skorove u tezine, oduzimanje maksimuma cuva stabilnost
  function void calculate_softmax(
      input real scores[ROWS_TB],
      output real weights[ROWS_TB]
  );
    real maximum, denominator;

    maximum = scores[0];
    for (int key_row = 1; key_row < ROWS_TB; key_row++) begin
      if (scores[key_row] > maximum)
        maximum = scores[key_row];
    end

    denominator = 0.0;
    for (int key_row = 0; key_row < ROWS_TB; key_row++) begin
      weights[key_row] = $exp(scores[key_row] - maximum);
      denominator += weights[key_row];
    end

    if (denominator <= 0.0)
      `uvm_fatal("REFERENCE", "Softmax denominator must be positive")

    for (int key_row = 0; key_row < ROWS_TB; key_row++)
      weights[key_row] = weights[key_row] / denominator;
  endfunction

  // sabiramo v redove pomnozene softmax tezinama
  function void calculate_output_row(
      fa_stimulus stimulus,
      int head,
      int result_row,
      input real weights[ROWS_TB],
      fa_expected_block result
  );
    real total, value;

    for (int column = 0; column < DIM_TB; column++) begin
      total = 0.0;
      for (int key_row = 0; key_row < ROWS_TB; key_row++) begin
        value = to_real(stimulus.v_values[head][key_row][column]);
        total += weights[key_row] * value;
      end
      result.values[result_row*DIM_TB + column] = total;
    end
  endfunction

  // kada je q nula sve tezine su jednake, pa je izlaz srednja vrednost v
  function void calculate_mean_v(
      fa_stimulus stimulus,
      int head,
      output real mean_v[DIM_TB]
  );
    real total;

    for (int column = 0; column < DIM_TB; column++) begin
      total = 0.0;
      for (int key_row = 0; key_row < ROWS_TB; key_row++)
        total += to_real(stimulus.v_values[head][key_row][column]);
      mean_v[column] = total / ROWS_TB;
    end
  endfunction

  // glavni ulaz: racunamo ocekivanja iz istih matrica koje sekvenca salje dut-u
  function void predict(fa_stimulus stimulus, int epoch);
    fa_expected_block result;
    real scores[ROWS_TB], weights[ROWS_TB], mean_v[DIM_TB];
    int rows_in_block, query_row;
    bit mean_ready;

    for (int first_row = 0; first_row < ROWS_TB; first_row += B_TB) begin
      rows_in_block = minimum(B_TB, ROWS_TB-first_row);

      for (int head = 0; head < HEADS_TB; head++) begin
        result = fa_expected_block::type_id::create("expected");
        // vezujemo ocekivanja za operaciju izmedju dva reseta
        result.epoch = epoch;
        result.first_index = first_row*HEADS_TB*DIM_TB
                           + head*rows_in_block*DIM_TB;
        result.values = new[rows_in_block*DIM_TB];
        mean_ready = 0;

        for (int row = 0; row < rows_in_block; row++) begin
          query_row = first_row + row;

          // biramo jednostavniji racun za nulti q red, inace punu matematiku
          if (query_is_zero(stimulus, head, query_row)) begin
            if (!mean_ready) begin
              calculate_mean_v(stimulus, head, mean_v);
              mean_ready = 1;
            end
            for (int column = 0; column < DIM_TB; column++)
              result.values[row*DIM_TB + column] = mean_v[column];
          end else begin
            calculate_scores(stimulus, head, query_row, scores);
            calculate_softmax(scores, weights);
            calculate_output_row(stimulus, head, row, weights, result);
          end
        end

        // gotov blok ocekivanih izlaza predajemo scoreboardu
        expected_ap.write(result);
      end
    end
  endfunction
endclass
