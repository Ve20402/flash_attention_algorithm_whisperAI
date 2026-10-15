#include <stdint.h>
#include <string.h>

#include "xaxidma.h"
#include "xgpio.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xscugic.h"
#include "xtime_l.h"
#include "xparameters.h"
#include "xstatus.h"
#include "sleep.h"

#define FA_HEADS 8U
#define FA_ROWS 1500U
#define FA_HEAD_DIM 64U
#define FA_B 32U
#define FA_BC 64U
#define FA_COLS 512U

#define FA_Q_BLOCKS ((FA_ROWS + FA_B - 1U) / FA_B)
#define FA_MATRIX_WORDS (FA_ROWS * FA_COLS)
#define FA_Q_WORDS (FA_ROWS * FA_HEADS * FA_HEAD_DIM)
#define FA_KV_WORDS (FA_Q_BLOCKS * FA_HEADS * 2U * FA_ROWS * FA_HEAD_DIM)
#define FA_INPUT_WORDS (FA_Q_WORDS + FA_KV_WORDS)
#define FA_OUTPUT_WORDS (FA_ROWS * FA_COLS)
#define FA_OUTPUT_BYTES (FA_OUTPUT_WORDS * sizeof(int64_t))

#define TX_BUFFER_ADDR 0x10000000U
#define RX_BUFFER_ADDR 0x11000000U
#define TX_CHUNK_BYTES (1024U * 1024U)
#define TX_CHUNK_WORDS (TX_CHUNK_BYTES / sizeof(uint32_t))

#define GPIO_RUN_CHANNEL 1U
#define GPIO_DONE_CHANNEL 2U
#define DMA_TIMEOUT_SECONDS 30U
#define FINAL_TIMEOUT_SECONDS 300U

#if defined(XPAR_AXIDMA_0_DEVICE_ID)
#define DMA_DEVICE_ID XPAR_AXIDMA_0_DEVICE_ID
#elif defined(XPAR_AXI_DMA_0_DEVICE_ID)
#define DMA_DEVICE_ID XPAR_AXI_DMA_0_DEVICE_ID
#elif defined(XPAR_XAXIDMA_0_DEVICE_ID)
#define DMA_DEVICE_ID XPAR_XAXIDMA_0_DEVICE_ID
#else
#error "AXI DMA device ID was not found in xparameters.h"
#endif

#if defined(XPAR_XAXIDMA_0_BASEADDR)
#define DMA_BASE_ADDRESS XPAR_XAXIDMA_0_BASEADDR
#elif defined(XPAR_AXIDMA_0_BASEADDR)
#define DMA_BASE_ADDRESS XPAR_AXIDMA_0_BASEADDR
#elif defined(XPAR_AXI_DMA_0_BASEADDR)
#define DMA_BASE_ADDRESS XPAR_AXI_DMA_0_BASEADDR
#else
#define DMA_BASE_ADDRESS 0U
#endif

#if defined(XPAR_GPIO_0_DEVICE_ID)
#define GPIO_DEVICE_ID XPAR_GPIO_0_DEVICE_ID
#elif defined(XPAR_AXI_GPIO_0_DEVICE_ID)
#define GPIO_DEVICE_ID XPAR_AXI_GPIO_0_DEVICE_ID
#elif defined(XPAR_XGPIO_0_DEVICE_ID)
#define GPIO_DEVICE_ID XPAR_XGPIO_0_DEVICE_ID
#else
#error "AXI GPIO device ID was not found in xparameters.h"
#endif

#if defined(XPAR_XGPIO_0_BASEADDR)
#define GPIO_BASE_ADDRESS XPAR_XGPIO_0_BASEADDR
#elif defined(XPAR_GPIO_0_BASEADDR)
#define GPIO_BASE_ADDRESS XPAR_GPIO_0_BASEADDR
#elif defined(XPAR_AXI_GPIO_0_BASEADDR)
#define GPIO_BASE_ADDRESS XPAR_AXI_GPIO_0_BASEADDR
#else
#define GPIO_BASE_ADDRESS 0U
#endif

#if defined(XPAR_SCUGIC_SINGLE_DEVICE_ID)
#define INTERRUPT_CONTROLLER_DEVICE_ID XPAR_SCUGIC_SINGLE_DEVICE_ID
#elif defined(XPAR_SCUGIC_0_DEVICE_ID)
#define INTERRUPT_CONTROLLER_DEVICE_ID XPAR_SCUGIC_0_DEVICE_ID
#else
#error "SCUGIC device ID was not found in xparameters.h"
#endif

#if defined(XPAR_FABRIC_AXI_DMA_0_MM2S_INTROUT_INTR)
#define MM2S_INTERRUPT_ID XPAR_FABRIC_AXI_DMA_0_MM2S_INTROUT_INTR
#define S2MM_INTERRUPT_ID XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR
#elif defined(XPAR_FABRIC_AXI_DMA_0_MM2S_INTROUT_VEC_ID)
#define MM2S_INTERRUPT_ID XPAR_FABRIC_AXI_DMA_0_MM2S_INTROUT_VEC_ID
#define S2MM_INTERRUPT_ID XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_VEC_ID
#elif defined(XPAR_FABRIC_AXIDMA_0_MM2S_INTROUT_VEC_ID)
#define MM2S_INTERRUPT_ID XPAR_FABRIC_AXIDMA_0_MM2S_INTROUT_VEC_ID
#define S2MM_INTERRUPT_ID XPAR_FABRIC_AXIDMA_0_S2MM_INTROUT_VEC_ID
#elif defined(XPAR_FABRIC_AXIDMA_0_MM2S_INTROUT_INTR)
#define MM2S_INTERRUPT_ID XPAR_FABRIC_AXIDMA_0_MM2S_INTROUT_INTR
#define S2MM_INTERRUPT_ID XPAR_FABRIC_AXIDMA_0_S2MM_INTROUT_INTR
#else
#error "AXI DMA interrupt IDs were not found in xparameters.h"
#endif

#if defined(XPAR_CPU_CORE_CLOCK_FREQ_HZ)
#define CPU_CLOCK_FREQ_HZ XPAR_CPU_CORE_CLOCK_FREQ_HZ
#elif defined(XPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ)
#define CPU_CLOCK_FREQ_HZ XPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ
#elif defined(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ)
#define CPU_CLOCK_FREQ_HZ XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ
#else
#error "CPU clock frequency was not found in xparameters.h"
#endif

extern const uint32_t fa_real_qkv_data[];
extern const int64_t fa_real_golden_data[];

typedef struct {
    uint32_t *buffer;
    uint32_t used_words;
    uint32_t sent_words;
    uint32_t transfers;
} StreamWriter;

XAxiDma dma;
XGpio gpio;
XScuGic interrupt_controller;
volatile uint32_t tx_done;
volatile uint32_t rx_done;
volatile uint32_t dma_error;
volatile uint32_t tx_interrupts;
volatile uint32_t rx_interrupts;

int wait_interrupt(volatile uint32_t *done, unsigned timeout_seconds)
{
    XTime start;
    XTime now;
    const uint64_t timeout_ticks = (uint64_t)timeout_seconds * (uint64_t)COUNTS_PER_SECOND;

    XTime_GetTime(&start);
    while (*done == 0U && dma_error == 0U) {
        XTime_GetTime(&now);
        if ((uint64_t)(now - start) > timeout_ticks)
            return XST_FAILURE;
    }
    return dma_error == 0U ? XST_SUCCESS : XST_FAILURE;
}

void tx_interrupt_handler(void *callback)
{
    XAxiDma *instance = (XAxiDma *)callback;
    const uint32_t status = XAxiDma_IntrGetIrq(instance, XAXIDMA_DMA_TO_DEVICE);

    XAxiDma_IntrAckIrq(instance, status, XAXIDMA_DMA_TO_DEVICE);
    if ((status & XAXIDMA_IRQ_ERROR_MASK) != 0U)
        dma_error = 1U;
    if ((status & XAXIDMA_IRQ_IOC_MASK) != 0U) {
        tx_done = 1U;
        ++tx_interrupts;
    }
}

void rx_interrupt_handler(void *callback)
{
    XAxiDma *instance = (XAxiDma *)callback;
    const uint32_t status =
        XAxiDma_IntrGetIrq(instance, XAXIDMA_DEVICE_TO_DMA);

    XAxiDma_IntrAckIrq(instance, status, XAXIDMA_DEVICE_TO_DMA);
    if ((status & XAXIDMA_IRQ_ERROR_MASK) != 0U)
        dma_error = 1U;
    if ((status & XAXIDMA_IRQ_IOC_MASK) != 0U) {
        rx_done = 1U;
        ++rx_interrupts;
    }
}

int setup_interrupt_system(void)
{
    XScuGic_Config *config;
    int status;

    config = XScuGic_LookupConfig(INTERRUPT_CONTROLLER_DEVICE_ID);
    if (config == NULL)
        return XST_FAILURE;

    status = XScuGic_CfgInitialize(&interrupt_controller, config, config->CpuBaseAddress);
    if (status != XST_SUCCESS)
        return status;

    status = XScuGic_Connect(&interrupt_controller, MM2S_INTERRUPT_ID,
                             (Xil_InterruptHandler)tx_interrupt_handler, &dma);
    if (status != XST_SUCCESS)
        return status;

    status = XScuGic_Connect(&interrupt_controller, S2MM_INTERRUPT_ID,
                             (Xil_InterruptHandler)rx_interrupt_handler, &dma);
    if (status != XST_SUCCESS)
        return status;

    XScuGic_SetPriorityTriggerType(&interrupt_controller, MM2S_INTERRUPT_ID, 0xA0U, 0x3U);
    XScuGic_SetPriorityTriggerType(&interrupt_controller, S2MM_INTERRUPT_ID, 0xA0U, 0x3U);
    XScuGic_Enable(&interrupt_controller, MM2S_INTERRUPT_ID);
    XScuGic_Enable(&interrupt_controller, S2MM_INTERRUPT_ID);

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                 &interrupt_controller);
    Xil_ExceptionEnable();
    return XST_SUCCESS;
}

unsigned elapsed_ms(XTime start, XTime stop)
{
    return (unsigned)(((uint64_t)(stop - start) * 1000U) / (uint64_t)COUNTS_PER_SECOND);
}

void pmu_cycle_counter_start(void)
{
    uint32_t value = 5U;
    __asm__ volatile ("mcr p15, 0, %0, c9, c12, 0" :: "r" (value));
    value = 0x80000000U;
    __asm__ volatile ("mcr p15, 0, %0, c9, c12, 1" :: "r" (value));
    __asm__ volatile ("isb");
}

uint32_t pmu_cycle_counter_read(void)
{
    uint32_t value;
    __asm__ volatile ("isb");
    __asm__ volatile ("mrc p15, 0, %0, c9, c13, 0" : "=r" (value));
    return value;
}

int init_peripherals(void)
{
    XAxiDma_Config *dma_cfg;
    int status;

    status = XGpio_Initialize(&gpio, GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: XGpio_Initialize failed (%d)\r\n", status);
        return XST_FAILURE;
    }
    XGpio_SetDataDirection(&gpio, GPIO_RUN_CHANNEL, 0x0U);
    XGpio_SetDataDirection(&gpio, GPIO_DONE_CHANNEL, 0x1U);
    XGpio_DiscreteWrite(&gpio, GPIO_RUN_CHANNEL, 0U);

    dma_cfg = XAxiDma_LookupConfig(DMA_DEVICE_ID);
    if (dma_cfg == NULL) {
        xil_printf("AXI DMA configuration not found\r\n");
        return XST_FAILURE;
    }
    status = XAxiDma_CfgInitialize(&dma, dma_cfg);
    if (status != XST_SUCCESS || XAxiDma_HasSg(&dma)) {
        xil_printf("AXI DMA init/simple-mode check failed (%d)\r\n", status);
        return XST_FAILURE;
    }
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrAckIrq(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrAckIrq(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    status = setup_interrupt_system();
    if (status != XST_SUCCESS) {
        xil_printf("DMA interrupt setup failed (%d)\r\n", status);
        return XST_FAILURE;
    }

    tx_done = 0U;
    rx_done = 0U;
    dma_error = 0U;
    tx_interrupts = 0U;
    rx_interrupts = 0U;
    XAxiDma_IntrEnable(&dma, (XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK), XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrEnable(&dma, (XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK), XAXIDMA_DEVICE_TO_DMA);

    xil_printf("DMA interrupts: MM2S ID=%u, S2MM ID=%u\r\n", (unsigned)MM2S_INTERRUPT_ID, (unsigned)S2MM_INTERRUPT_ID);
    return XST_SUCCESS;
}

int writer_flush(StreamWriter *writer)
{
    uint32_t bytes;
    int status;

    if (writer->used_words == 0U)
        return XST_SUCCESS;

    bytes = writer->used_words * sizeof(uint32_t);
    Xil_DCacheFlushRange((UINTPTR)writer->buffer, bytes);
    tx_done = 0U;
    status = XAxiDma_SimpleTransfer(&dma, (UINTPTR)writer->buffer, bytes, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS)
        return XST_FAILURE;
    if (wait_interrupt(&tx_done, DMA_TIMEOUT_SECONDS) != XST_SUCCESS)
        return XST_FAILURE;

    writer->sent_words += writer->used_words;
    writer->used_words = 0U;
    ++writer->transfers;
    return XST_SUCCESS;
}

static int writer_append(StreamWriter *writer, const uint32_t *source, uint32_t words)
{
    while (words != 0U) {
        const uint32_t available = TX_CHUNK_WORDS - writer->used_words;
        const uint32_t copy_words = (words < available) ? words : available;

        memcpy(&writer->buffer[writer->used_words], source, copy_words * sizeof(uint32_t));
        writer->used_words += copy_words;
        source += copy_words;
        words -= copy_words;

        if (writer->used_words == TX_CHUNK_WORDS && writer_flush(writer) != XST_SUCCESS)
            return XST_FAILURE;
    }
    return XST_SUCCESS;
}

int send_real_qkv_stream(void)
{
    const uint32_t *q = fa_real_qkv_data;
    const uint32_t *k = q + FA_MATRIX_WORDS;
    const uint32_t *v = k + FA_MATRIX_WORDS;
    StreamWriter writer = {
        (uint32_t *)(uintptr_t)TX_BUFFER_ADDR, 0U, 0U, 0U
    };

    for (uint32_t qi = 0U; qi < FA_ROWS; qi += FA_B) {
        const uint32_t br = ((FA_ROWS - qi) < FA_B) ? (FA_ROWS - qi) : FA_B;

        for (uint32_t head = 0U; head < FA_HEADS; ++head) {
            const uint32_t column = head * FA_HEAD_DIM;

            for (uint32_t row = 0U; row < br; ++row) {
                const uint32_t *source = &q[(qi + row) * FA_COLS + column];
                if (writer_append(&writer, source, FA_HEAD_DIM) != XST_SUCCESS)
                    return XST_FAILURE;
            }

            for (uint32_t j = 0U; j < FA_ROWS; j += FA_BC) {
                const uint32_t bc = ((FA_ROWS - j) < FA_BC) ? (FA_ROWS - j) : FA_BC;

                for (uint32_t row = 0U; row < bc; ++row) {
                    const uint32_t *source = &k[(j + row) * FA_COLS + column];
                    if (writer_append(&writer, source, FA_HEAD_DIM) != XST_SUCCESS)
                        return XST_FAILURE;
                }
                for (uint32_t row = 0U; row < bc; ++row) {
                    const uint32_t *source = &v[(j + row) * FA_COLS + column];
                    if (writer_append(&writer, source, FA_HEAD_DIM) != XST_SUCCESS)
                        return XST_FAILURE;
                }
            }
        }

        if ((((qi / FA_B) + 1U) % 4U) == 0U || qi + br == FA_ROWS) {
            xil_printf("  Q rows processed: %u / %u\r\n", (unsigned)(qi + br), (unsigned)FA_ROWS);
        }
    }

    if (writer_flush(&writer) != XST_SUCCESS)
        return XST_FAILURE;
    if (writer.sent_words != FA_INPUT_WORDS) {
        xil_printf("stream size %u, expected %u words\r\n", (unsigned)writer.sent_words, (unsigned)FA_INPUT_WORDS);
        return XST_FAILURE;
    }

    xil_printf("Input complete: %u words in %u DMA transfers\r\n", (unsigned)writer.sent_words, (unsigned)writer.transfers);
    return XST_SUCCESS;
}

int compare_real_output(void)
{
    volatile const int64_t *actual = (volatile const int64_t *)(uintptr_t)RX_BUFFER_ADDR;
    uint32_t errors = 0U;

    Xil_DCacheInvalidateRange((UINTPTR)RX_BUFFER_ADDR, FA_OUTPUT_BYTES);
    for (uint32_t i = 0U; i < FA_OUTPUT_WORDS; ++i) {
        if (actual[i] != fa_real_golden_data[i]) {
            if (errors < 8U) {
                const uint64_t got = (uint64_t)actual[i];
                const uint64_t expected = (uint64_t)fa_real_golden_data[i];
                xil_printf("Mismatch[%u] got=%08x%08x expected=%08x%08x\r\n",
                           (unsigned)i,
                           (unsigned)(got >> 32), (unsigned)got,
                           (unsigned)(expected >> 32), (unsigned)expected);
            }
            ++errors;
        }
    }

    if (errors != 0U) {
        xil_printf("FA REAL TEST FAILED %u / %u mismatches\r\n", (unsigned)errors, (unsigned)FA_OUTPUT_WORDS);
        return XST_FAILURE;
    }

    xil_printf("FA REAL TEST PASSED %u / %u exact Q14.34 matches\r\n", (unsigned)FA_OUTPUT_WORDS, (unsigned)FA_OUTPUT_WORDS);
    return XST_SUCCESS;
}

int main(void)
{
    int status;
    XTime start;
    XTime input_done;
    XTime stop;
    uint32_t pmu_start;
    uint32_t pmu_stop;
    uint32_t pmu_cycles;

    xil_printf("\r\nFlashAttention real Whisper test\r\n");
    xil_printf("DMA=0x%08x GPIO=0x%08x\r\n", (unsigned)DMA_BASE_ADDRESS, (unsigned)GPIO_BASE_ADDRESS);

    if (init_peripherals() != XST_SUCCESS)
        return XST_FAILURE;

    usleep(1U);

    memset((void *)(uintptr_t)RX_BUFFER_ADDR, 0xA5, FA_OUTPUT_BYTES);
    Xil_DCacheFlushRange((UINTPTR)RX_BUFFER_ADDR, FA_OUTPUT_BYTES);

    rx_done = 0U;
    status = XAxiDma_SimpleTransfer(&dma, (UINTPTR)RX_BUFFER_ADDR, FA_OUTPUT_BYTES, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("could not start S2MM (%d)\r\n", status);
        return XST_FAILURE;
    }

    pmu_cycle_counter_start();
    pmu_start = pmu_cycle_counter_read();
    XTime_GetTime(&start);
    XGpio_DiscreteWrite(&gpio, GPIO_RUN_CHANNEL, 1U);
    for (volatile unsigned delay = 0U; delay < 1000U; ++delay) {
    }
    XGpio_DiscreteWrite(&gpio, GPIO_RUN_CHANNEL, 0U);

    xil_printf("Streaming real quantized Q/K/V...\r\n");
    if (send_real_qkv_stream() != XST_SUCCESS) {
        xil_printf("real input stream/DMA failed\r\n");
        return XST_FAILURE;
    }
    XTime_GetTime(&input_done);

    if (wait_interrupt(&rx_done, FINAL_TIMEOUT_SECONDS) != XST_SUCCESS) {
        xil_printf("S2MM interrupt timeout/error; all_done=%u\r\n", (unsigned)(XGpio_DiscreteRead(&gpio, GPIO_DONE_CHANNEL) & 1U));
        return XST_FAILURE;
    }
    XTime_GetTime(&stop);
    pmu_stop = pmu_cycle_counter_read();
    pmu_cycles = pmu_stop - pmu_start;

    if ((XGpio_DiscreteRead(&gpio, GPIO_DONE_CHANNEL) & 1U) == 0U) {
        xil_printf("DMA finished but all_done is low\r\n");
        return XST_FAILURE;
    }

    xil_printf("Input streaming time: %u ms\r\n", elapsed_ms(start, input_done));
    xil_printf("Independent PMU: %u CPU cycles, %u ms\r\n", (unsigned)pmu_cycles,(unsigned)(((uint64_t)pmu_cycles * 1000U) / (uint64_t)CPU_CLOCK_FREQ_HZ));
    return compare_real_output();
}
