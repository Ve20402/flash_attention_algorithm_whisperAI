class fa_stimulus extends uvm_object;
  `uvm_object_utils(fa_stimulus)
  int q_values[HEADS_TB][ROWS_TB][DIM_TB];
  int k_values[HEADS_TB][ROWS_TB][DIM_TB];
  int v_values[HEADS_TB][ROWS_TB][DIM_TB];

  function new(string name="fa_stimulus"); 
	super.new(name); 
  endfunction

  function int alternating(int position, int even_value, int odd_value);
    if (position%2 == 0) 
		return even_value;
    return odd_value;
  endfunction

  function int random_value(fa_random_value generator, int scale);
    if (!generator.randomize()) 
		`uvm_fatal("RANDOMIZE","Matrix randomization failed")
    return generator.value*scale;
  endfunction

  // popunjavamo q, k i v matrice pre pocetka slanja i racunanja reference
  function void prepare(string pattern, bit generated_data);
    fa_random_value generator;
    string dump_path;
    int dump_fd;
    generator = fa_random_value::type_id::create("matrix_generator");
    foreach (q_values[h,r,d]) begin
      // deterministicki podaci za osnovni test
      if (!generated_data) begin
        q_values[h][r][d] = FIXED_ONE;
        k_values[h][r][d] = FIXED_ONE;
        if (r < BC_TB) 
			v_values[h][r][d] = ((d%8)+1)*FIXED_ONE;
        else 
			v_values[h][r][d] = ((d%8)+5)*FIXED_ONE;
        continue;
      end
      q_values[h][r][d] = 0;
      k_values[h][r][d] = 0;
      v_values[h][r][d] = (((r+d+h)%9)-4)*FIXED_ONE;
      case (pattern)
        // Representable inputs whose 64-term dot product exceeds 48-bit Q12.36.
        // Correct scores are [4096,0], so the output is approximately 1.
        "numeric_range": begin
          q_values[h][r][d] = 8*FIXED_ONE;
          k_values[h][r][d] = (r == 0) ? 8*FIXED_ONE : 0;
          v_values[h][r][d] = (r == 0) ? FIXED_ONE : 3*FIXED_ONE;
        end
        // Directed input-order probe: correct O=1.5; swapping K/V gives O=0.5.
        "kv_order_probe": begin
          q_values[h][r][d] = FIXED_QUARTER;
          k_values[h][r][d] = 2*FIXED_QUARTER;
          v_values[h][r][d] = FIXED_ONE + 2*FIXED_QUARTER;
        end
        // slucajni q, k i v podaci u ogranicenom opsegu
        "random": begin
          q_values[h][r][d] = random_value(generator,FIXED_QUARTER);
          k_values[h][r][d] = random_value(generator,FIXED_QUARTER);
          v_values[h][r][d] = random_value(generator,FIXED_ONE);
        end
        // Wider random range for the separate paired K/V-order experiment.
        "random_wide": begin
          q_values[h][r][d] = random_value(generator,2*FIXED_QUARTER);
          k_values[h][r][d] = random_value(generator,2*FIXED_QUARTER);
          v_values[h][r][d] = random_value(generator,2*FIXED_ONE);
        end
        // k je nula, a u q i v ubacujemo i najmanji nenulti korak
        "k_zero_lsb": begin
          q_values[h][r][d] = random_value(generator,FIXED_QUARTER);
          k_values[h][r][d] = 0;
          v_values[h][r][d] = random_value(generator,FIXED_ONE);
          if (d % 16 == 0) begin
            q_values[h][r][d] = alternating(r+h,INPUT_LSB,-INPUT_LSB);
            v_values[h][r][d] = alternating(r+d,INPUT_LSB,-INPUT_LSB);
          end
        end
        "zero": v_values[h][r][d] = 0;
        "lsb": begin
          q_values[h][r][d] = alternating(r,INPUT_LSB,-INPUT_LSB);
          k_values[h][r][d] = alternating(d,INPUT_LSB,-INPUT_LSB);
          v_values[h][r][d] = alternating(d+h,INPUT_LSB,-INPUT_LSB);
        end
        "q_limits": q_values[h][r][d] = alternating(d+r,INPUT_MAX,INPUT_MIN);
        "k_limits": k_values[h][r][d] = alternating(d+r,INPUT_MAX,INPUT_MIN);
        "v_limits": v_values[h][r][d] = alternating(d+h,INPUT_MAX,INPUT_MIN);
        "full_uniform": v_values[h][r][d] = (((r+3*d+5*h)%9)-4)*FIXED_QUARTER;
        default: `uvm_fatal("PATTERN",{"Unknown pattern: ",pattern})
      endcase
    end
    // Optional evidence of the ORIGINAL matrices, before stream-order injection.
    // File output consumes no random values and does not modify the stimulus.
    if ($value$plusargs("FA_STIMULUS_FILE=%s",dump_path)) begin
      dump_fd = $fopen(dump_path,"w");
      if (dump_fd == 0)
        `uvm_fatal("STIMULUS_OPEN","Cannot write original stimulus matrices")
      $fdisplay(dump_fd,"head,row,column,q_raw,k_raw,v_raw");
      foreach (q_values[h,r,d])
        $fdisplay(dump_fd,"%0d,%0d,%0d,%0d,%0d,%0d",h,r,d,
          q_values[h][r][d],k_values[h][r][d],v_values[h][r][d]);
      $fclose(dump_fd);
    end
  endfunction

endclass
