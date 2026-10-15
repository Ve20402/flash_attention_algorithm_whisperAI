    .section .rodata.fa_real_vectors,"a",%progbits
    .balign 64

    .global fa_real_qkv_data
    .type fa_real_qkv_data, %object
fa_real_qkv_data:
    .incbin "fa_real_qkv.bin"
    .size fa_real_qkv_data, . - fa_real_qkv_data

    .balign 64
    .global fa_real_golden_data
    .type fa_real_golden_data, %object
fa_real_golden_data:
    .incbin "fa_real_golden.bin"
    .size fa_real_golden_data, . - fa_real_golden_data

    .section .note.GNU-stack,"",%progbits
