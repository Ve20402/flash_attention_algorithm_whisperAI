#ifndef IP_HLS_H
#define IP_HLS_H

#include "ap_fixed.h"
#include "hls_stream.h"

const int ROWS = 1500;
const int COLS = 512;
const int NUM_HEADS = 8;
const int HEAD_DIM = 64;
const int B = 32;
const int BC = 64;

typedef ap_fixed<24, 6>  data_t;
typedef ap_fixed<18, 2>  prob_t;
typedef ap_fixed<32, 12> acc_t;

void mha_ip(hls::stream<float> &stream_in, hls::stream<float> &stream_out);

#endif
