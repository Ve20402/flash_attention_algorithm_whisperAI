#ifndef DATATYPES_H
#define DATATYPES_H

#ifndef SC_INCLUDE_FX
#define SC_INCLUDE_FX
#endif

#include <systemc.h>
#include <tlm.h>
#include <vector>

#define MAX_COLS 1024

namespace attn {
const int ROWS = 1500;
const int COLS = 512;
const int NUM_HEADS = 8;
const int HEAD_DIM = 64;
const int B = 32;
const int BC = 64;
} 

using DATA_T = sc_fixed<32, 10>;
using PROB_T = sc_fixed<16, 1>;
using ACC_T = sc_fixed<32, 12>;

typedef float mem_data_t;

using Matrix = std::vector<std::vector<DATA_T>>;
using Vector = std::vector<DATA_T>;

#endif
