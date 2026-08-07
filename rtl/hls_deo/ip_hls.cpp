#include "ip_hls.h"
#include "exp_table.h"

static prob_t exp_neg(acc_t arg) {
	if (arg <= (acc_t)(-EXP_MAX))
		return (prob_t)0;

	acc_t x = -arg;
	int idx = (int)(x * (EXP_N / EXP_MAX));
	if (idx >= EXP_N)
		idx = EXP_N - 1;

	return EXP_TABLE[idx];
}

static void flash_attn_init(acc_t m_buf[B], acc_t l_buf[B],
                            acc_t O_acc[B][HEAD_DIM], int br) {
	for (int r = 0; r < br; r++) {
		m_buf[r] = (acc_t)-1000;
		l_buf[r] = 0;
		for (int d = 0; d < HEAD_DIM; d++) {
			#pragma HLS PIPELINE II=1
			O_acc[r][d] = 0;
		}
	}
}

static void flash_attn_step(data_t Q_tile[B][HEAD_DIM],
                            data_t K_tile[BC][HEAD_DIM],
                            data_t V_tile[BC][HEAD_DIM], acc_t m_buf[B],
                            acc_t l_buf[B], acc_t O_acc[B][HEAD_DIM], int br,
                            int bc) {
	static acc_t S[B][BC];
	#pragma HLS ARRAY_PARTITION variable=S dim=2 cyclic factor=8

	prob_t p_row[BC];
	#pragma HLS BIND_STORAGE variable=p_row type=ram_1p impl=bram

	for (int d = 0; d < HEAD_DIM; d++)
		for (int r = 0; r < br; r++)
			for (int c = 0; c < bc; c++) {
				#pragma HLS PIPELINE II=1
				#pragma HLS UNROLL factor=8
				acc_t prod = Q_tile[r][d] * K_tile[c][d];
				if (d == 0)
					S[r][c] = prod;
				else
					S[r][c] = S[r][c] + prod;
			}

	for (int r = 0; r < br; r++) {
		acc_t m_new = m_buf[r];
		for (int c = 0; c < bc; c++) {
			#pragma HLS PIPELINE II=3
			if (S[r][c] > m_new)
				m_new = S[r][c];
		}

		acc_t scale = (acc_t)exp_neg(m_buf[r] - m_new);
		acc_t l_new = l_buf[r] * scale;

		for (int d = 0; d < HEAD_DIM; d++) {
			#pragma HLS PIPELINE II=1
			O_acc[r][d] = O_acc[r][d] * scale;
		}

		for (int c = 0; c < bc; c++) {
			#pragma HLS PIPELINE II=5
			prob_t p = exp_neg(S[r][c] - m_new);
			p_row[c] = p;
			l_new = l_new + p;
		}

		for (int c = 0; c < bc; c++)
			for (int d = 0; d < HEAD_DIM; d++) {
				#pragma HLS PIPELINE II=1
				#pragma HLS UNROLL factor=8
				O_acc[r][d] = O_acc[r][d] + p_row[c] * V_tile[c][d];
			}

		m_buf[r] = m_new;
		l_buf[r] = l_new;
	}
}

static void flash_attn_finalize(acc_t O_acc[B][HEAD_DIM], const acc_t l_buf[B],
                                int br) {
	for (int r = 0; r < br; r++) {
		float inv = 1.0f / (float)l_buf[r];
		for (int d = 0; d < HEAD_DIM; d++) {
			#pragma HLS PIPELINE II=1
			O_acc[r][d] = O_acc[r][d] * (acc_t)inv;
		}
	}
}

void mha_ip(hls::stream<float> &stream_in, hls::stream<float> &stream_out) {
#pragma HLS INTERFACE axis port=stream_in
#pragma HLS INTERFACE axis port=stream_out
#pragma HLS INTERFACE s_axilite port=return

	static data_t Q_tile[B][HEAD_DIM];
	static data_t K_tile[BC][HEAD_DIM];
	static data_t V_tile[BC][HEAD_DIM];
	static acc_t O_acc[B][HEAD_DIM];
	static acc_t m_buf[B];
	static acc_t l_buf[B];

#pragma HLS ARRAY_PARTITION variable=K_tile dim=1 cyclic factor=8
#pragma HLS ARRAY_PARTITION variable=V_tile dim=2 cyclic factor=8
#pragma HLS ARRAY_PARTITION variable=O_acc dim=2 cyclic factor=8

	for (int qi = 0; qi < ROWS; qi += B) {
		int br = ROWS - qi;
		if (br > B)
			br = B;

		for (int h = 0; h < NUM_HEADS; h++) {
			for (int r = 0; r < br; r++)
				for (int d = 0; d < HEAD_DIM; d++) {
					#pragma HLS PIPELINE II=1
					Q_tile[r][d] = (data_t)stream_in.read();
				}

			flash_attn_init(m_buf, l_buf, O_acc, br);

			for (int j = 0; j < ROWS; j += BC) {
				int bc = ROWS - j;
				if (bc > BC)
					bc = BC;

				for (int r = 0; r < bc; r++)
					for (int d = 0; d < HEAD_DIM; d++) {
						#pragma HLS PIPELINE II=1
						K_tile[r][d] = (data_t)stream_in.read();
					}

				for (int r = 0; r < bc; r++)
					for (int d = 0; d < HEAD_DIM; d++) {
						#pragma HLS PIPELINE II=1
						V_tile[r][d] = (data_t)stream_in.read();
					}

				flash_attn_step(Q_tile, K_tile, V_tile, m_buf, l_buf, O_acc, br,
				                bc);
			}

			flash_attn_finalize(O_acc, l_buf, br);

			for (int r = 0; r < br; r++)
				for (int d = 0; d < HEAD_DIM; d++) {
					#pragma HLS PIPELINE II=1
					stream_out.write((float)O_acc[r][d]);
				}
		}
	}
}
