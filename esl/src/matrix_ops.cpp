#include "header/matrix_ops.h"
#include <algorithm>
#include <cmath>

void matmul(const float *X, const float *W, float *Y, int rows, int inner, int w_cols, bool accumulate) {
	for (int i = 0; i < rows; i++)
		for (int j = 0; j < w_cols; j++) {
			float sum = 0.0f;
			for (int k = 0; k < inner; k++)
				sum += X[i * inner + k] * W[k * w_cols + j];
			if (accumulate)
				Y[i * w_cols + j] += sum;
			else
				Y[i * w_cols + j] = sum;
		}
}

void flash_attn_init(float *m_buf, float *l_buf, float *O_acc, int br, int HEAD_DIM) {
	for (int r = 0; r < br; r++) {
		m_buf[r] = -1e30f;
		l_buf[r] = 0.0f;
		for (int d = 0; d < HEAD_DIM; d++)
			O_acc[r * HEAD_DIM + d] = 0.0f;
	}
}

void flash_attn_step(const float *Q_tile, int br, const float *K_tile,
                     const float *V_tile, int tk, float *m_buf, float *l_buf,
                     float *O_acc, int HEAD_DIM) {

	static const int BR_MAX = 128;
	static const int BC_MAX = 128;
	static float S[BR_MAX * BC_MAX];

	for (int r = 0; r < br; r++)
		for (int c = 0; c < tk; c++) {
			float s = 0.0f;
			for (int d = 0; d < HEAD_DIM; d++)
				s += Q_tile[r * HEAD_DIM + d] * K_tile[c * HEAD_DIM + d];
			S[r * tk + c] = s;
		}

	for (int r = 0; r < br; r++) {
		float m_new = m_buf[r];
		for (int c = 0; c < tk; c++)
			m_new = std::max(m_new, S[r * tk + c]);

		float scale = std::exp(m_buf[r] - m_new);
		float l_new = l_buf[r] * scale;
		for (int d = 0; d < HEAD_DIM; d++)
			O_acc[r * HEAD_DIM + d] *= scale;

		for (int c = 0; c < tk; c++) {
			float p = std::exp(S[r * tk + c] - m_new);
			l_new += p;
			for (int d = 0; d < HEAD_DIM; d++)
				O_acc[r * HEAD_DIM + d] += p * V_tile[c * HEAD_DIM + d];
		}
		m_buf[r] = m_new;
		l_buf[r] = l_new;
	}
}

void flash_attn_finalize(float *O_acc, const float *l_buf, int br, int HEAD_DIM) {
	for (int r = 0; r < br; r++) {
		float inv = 1.0f / l_buf[r];
		for (int d = 0; d < HEAD_DIM; d++)
			O_acc[r * HEAD_DIM + d] *= inv;
	}
}
