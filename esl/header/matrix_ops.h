#ifndef MATRIX_OPS_H
#define MATRIX_OPS_H

void matmul(const float *X, const float *W, float *Y, int rows, int inner,
            int w_cols, bool accumulate = false);

void flash_attn_init(float *m_buf, float *l_buf, float *O_acc, int br, int HEAD_DIM);

void flash_attn_step(const float *Q_tile, int br, const float *K_tile,
                     const float *V_tile, int tk, float *m_buf, float *l_buf,
                     float *O_acc, int HEAD_DIM);

void flash_attn_finalize(float *O_acc, const float *l_buf, int br, int HEAD_DIM);

#endif
