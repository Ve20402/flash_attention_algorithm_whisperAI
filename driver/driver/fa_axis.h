#ifndef FA_AXIS_H
#define FA_AXIS_H

#include <linux/types.h>
#include <linux/ioctl.h>

#define FA_HEADS      8u
#define FA_ROWS       1500u
#define FA_HEAD_DIM   64u
#define FA_B          32u
#define FA_BC         64u
#define FA_COLS       512u

#define FA_Q_BLOCKS      ((FA_ROWS + FA_B - 1u) / FA_B)
#define FA_MATRIX_WORDS  (FA_ROWS * FA_COLS)
#define FA_Q_WORDS       (FA_ROWS * FA_HEADS * FA_HEAD_DIM)
#define FA_KV_WORDS      (FA_Q_BLOCKS * FA_HEADS * 2u * FA_ROWS * FA_HEAD_DIM)
#define FA_INPUT_WORDS   (FA_Q_WORDS + FA_KV_WORDS)
#define FA_TX_SIZE       (FA_INPUT_WORDS * 4u)
#define FA_OUTPUT_WORDS  (FA_ROWS * FA_COLS)
#define FA_RX_SIZE       (FA_OUTPUT_WORDS * 8u)

struct fa_info {
	__u32 tx_size;
	__u32 rx_size;
	__u32 input_words;
	__u32 output_words;
};

#define FA_MMAP_TX 0UL
#define FA_MMAP_RX 1UL

#define FA_IOC_MAGIC    'F'
#define FA_IOC_GET_INFO _IOR(FA_IOC_MAGIC, 0, struct fa_info)
#define FA_IOC_RUN      _IO(FA_IOC_MAGIC, 1)

#endif
