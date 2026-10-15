#ifndef MATRIX_OPS_H
#define MATRIX_OPS_H

#include "datatypes.h"

void flash_attn_init(fixed_word_t *maximum, fixed_word_t *sum,
                     fixed_word_t *output, int query_rows, int head_dim);

void flash_attn_step(const fixed_word_t *q, int query_rows,
                     const fixed_word_t *k, const fixed_word_t *v, int kv_rows,
                     fixed_word_t *maximum, fixed_word_t *sum,
                     fixed_word_t *output, int head_dim);

void flash_attn_finalize(fixed_word_t *output, const fixed_word_t *sum,
                         int query_rows, int head_dim);

#endif
