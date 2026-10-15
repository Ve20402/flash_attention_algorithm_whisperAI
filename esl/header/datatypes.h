#ifndef DATATYPES_H
#define DATATYPES_H

#include <cstdint>

#define MAX_COLS 1024

namespace attn {
const int KV_ROWS = 1500;
const int QUERY_ROWS = 1500;
const int NUM_HEADS = 8;
const int HEAD_DIM = 64;
const int B = 32;
const int BC = 64;

const int DATA_BITS = 24;
const int DATA_FRAC = 18; // RTL data_t: Q6.18
const int PROB_BITS = 18;
const int PROB_FRAC = 16; // RTL prob_t: Q2.16
const int ACC_BITS = 48;
const int ACC_FRAC = 34; // RTL O accumulator/output: Q14.34

struct AttentionConfig {
	int query_rows = QUERY_ROWS;
	int kv_rows = KV_ROWS;
	int heads = NUM_HEADS;
	int head_dim = HEAD_DIM;
};
} // namespace attn

using fixed_word_t = std::int64_t;

#endif
