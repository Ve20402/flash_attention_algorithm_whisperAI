#!/bin/bash

set -e

PROJECT_DIR=$(pwd)

BITSTREAM_NAME="fa_block_design_second_wrapper.bin"
BITSTREAM_SRC="$PROJECT_DIR/bitstream/$BITSTREAM_NAME"
BITSTREAM_DST="/lib/firmware/$BITSTREAM_NAME"

FPGA_FIRMWARE="/sys/class/fpga_manager/fpga0/firmware"
FPGA_STATE="/sys/class/fpga_manager/fpga0/state"

DRIVER_KO="$PROJECT_DIR/driver/fa_axis.ko"

APP="$PROJECT_DIR/app/test/fa_test"

if [ -f "$PROJECT_DIR/app/whisper.cpp/build/bin/whisper-cli" ]; then
  RUN_WHISPER=1
fi

QKV="$PROJECT_DIR/../rtl/software/fa_real_qkv.bin"
GOLDEN="$PROJECT_DIR/../rtl/software/fa_real_golden.bin"

echo "=== Flash Attention project run ==="

rmmod -f fa_axis || true

echo "[1/5] Loading FPGA bitstream..."
cp "$BITSTREAM_SRC" "$BITSTREAM_DST"
echo "$BITSTREAM_NAME" > "$FPGA_FIRMWARE"

STATE=$(cat "$FPGA_STATE")
echo "FPGA state: $STATE"

if [ "$STATE" != "operating" ]; then
    echo "ERROR: FPGA is not operating"
    exit 1
fi

echo "[2/5] Loading kernel driver..."

if lsmod | grep -q "^fa_axis"; then
    echo "fa_axis already loaded"
else
    insmod "$DRIVER_KO"
fi

echo "[3/5] Checking device file..."

if [ ! -e /dev/fa_axis ]; then       
    echo "ERROR: /dev/fa_axis character device does not exist"
    exit 1
fi

echo "[4/5] Running Flash Attention test application..."

cd "$PROJECT_DIR"
"$APP" "$QKV" "$GOLDEN"

echo "[5/5] Running whisper.cpp"
if [[ -z "${RUN_WHISPER}" ]]; then
  if [ ! -e "$PROJECT_DIR/app/whisper.cpp/models/ggml-base.en.bin" ]; then
    echo "Dependency: Downloading Whisper AI base model"
    "$PROJECT_DIR/app/whisper.cpp/models/download-ggml-model.sh"  "base.en"
  fi

  if [ ! -e "$PROJECT_DIR/app/whisper.cpp/models/ggml-base.en-q5_0.bin" ]; then
    echo "Dependency: Quantizing Whisper AI model to Q5_0"
    "$PROJECT_DIR/app/whisper.cpp/build/bin/whisper-quantize" \
      "${PROJECT_DIR}/app/whisper.cpp/models/ggml-base.en.bin" \
      "${PROJECT_DIR}/app/whisper.cpp/models/ggml-base.en-q5_0.bin" \
      "q5_0"
  fi

  "$PROJECT_DIR/app/whisper.cpp/build/bin/whisper-quantize" \
    -m "$PROJECT_DIR/app/whisper.cpp/models/ggml-base.en-q5_0.bin" \
    -bs 1 -bo 1 "$PROJECT_DIR/../data/normal.wav"
else
  echo "Whisper.cpp has not been compiled. Skipping."
fi

echo "=== DONE ==="
