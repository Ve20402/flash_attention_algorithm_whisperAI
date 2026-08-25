SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.SILENT:
.DEFAULT_GOAL := help

CXX ?= g++
GHDL ?= ghdl
PYTHON ?= python3

VENV_DIR := esl/.venv
VENV_PY := $(VENV_DIR)/bin/python
DATA_DIR := data
MATRIX_DIR := $(DATA_DIR)/matrice
VP_EXE := esl/simulation_tlm

CXXFLAGS := -O3 -std=c++17 -DSC_INCLUDE_FX -Iesl -Iesl/header
GHDL_FLAGS := --std=08 -frelaxed-rules

PYBIND_SRCS := esl/src/pybind_wrapper.cpp \
	       esl/src/attention_module_multiple_heads.cpp

VP_SRCS := esl/src/testbench_vp.cpp \
	   esl/src/vp.cpp \
	   esl/src/cpu.cpp \
	   esl/src/ip.cpp \
	   esl/src/dma.cpp \
	   esl/src/matrix_ops.cpp \
	   esl/src/bram_tlm.cpp \
	   esl/src/interconnect.cpp

RTL_SRCS := rtl/fa_types_pkg.vhd \
	    rtl/memory.vhd \
	    rtl/ring_buffer.vhd \
	    rtl/exp_rom.vhd \
	    rtl/recip_rom.vhd \
	    rtl/datapath_v2.vhd \
	    rtl/controlpath_real.vhd \
	    rtl/top_qkt_v2.vhd \
	    rtl/streaming_block.vhd \
	    rtl/fa_axis_top.vhd

.PHONY: help app head clean

help:
	echo "make app   - glavni program"
	echo "make head  - RTL simulacija"
	echo "make clean"

app:
	if [ ! -x "$(VENV_PY)" ]; then
		echo ">>> Kreiram WSL Python okruzenje u $(VENV_DIR)..."
		$(PYTHON) -m venv "$(VENV_DIR)"
		"$(VENV_PY)" -m pip install --upgrade pip
		"$(VENV_PY)" -m pip install torch==2.9.1 --index-url https://download.pytorch.org/whl/cpu
		"$(VENV_PY)" -m pip install numpy transformers==4.35.0 sounddevice soundfile pybind11
	fi

	mkdir -p "$(MATRIX_DIR)"
	PYTHON_INCLUDE="$$($(VENV_PY) -c 'import sysconfig; print(sysconfig.get_path("include"))')"
	PYBIND_INCLUDE="$$($(VENV_PY) -c 'import pybind11; print(pybind11.get_include())')"
	PYBIND_SUFFIX="$$($(VENV_PY) -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))')"

	echo ">>> [1/4] Python/C++ attention i generisanje pravih matrica..."
	$(CXX) $(CXXFLAGS) -shared -fPIC \
		-I"$$PYTHON_INCLUDE" -I"$$PYBIND_INCLUDE" \
		$(PYBIND_SRCS) \
		-o "$(DATA_DIR)/multihead_attention_algorithm$$PYBIND_SUFFIX"
	cd esl
	PYTHONPATH=../data:$${PYTHONPATH:-} .venv/bin/python final_app.py
	cd ..

	for file in \
		multihead_ulaz_Q.txt multihead_ulaz_K.txt multihead_ulaz_V.txt \
		multihead_W_out.txt multihead_b_out.txt \
		multihead_output_pre_wout.txt output_main_app.txt matrix_metadata.json; do
		test -s "$(MATRIX_DIR)/$$file" || {
			echo "GRESKA: nedostaje ili je prazan $(MATRIX_DIR)/$$file"
			exit 1
		}
	done

	echo ">>> [2/4] Kompajliranje SystemC/TLM virtuelne platforme..."
	$(CXX) $(CXXFLAGS) $(VP_SRCS) -lsystemc -o "$(VP_EXE)"

	echo ">>> [3/4] Pokretanje virtuelne platforme..."
	cd esl
	./simulation_tlm
	cd ..

	echo ">>> [4/4] Poredjenje VP izlaza sa Python post-projection goldenom..."
	"$(VENV_PY)" esl/compare.py \
		"$(DATA_DIR)/vp_output.txt" \
		"$(MATRIX_DIR)/output_main_app.txt"

head:
	test -x "$(VENV_PY)" || {
		echo "GRESKA: Python okruzenje ne postoji; prvo pokreni 'make app'."
		exit 1
	}
	for file in \
		multihead_ulaz_Q.txt multihead_ulaz_K.txt multihead_ulaz_V.txt \
		multihead_output_pre_wout.txt matrix_metadata.json; do
		test -s "$(MATRIX_DIR)/$$file" || {
			echo "GRESKA: nedostaje $(MATRIX_DIR)/$$file; prvo pokreni 'make app'."
			exit 1
		}
	done

	echo ">>> [1/3] Fixed-point vektori: glava 3, 32 Q reda, svih 1500 K/V reda..."
	"$(VENV_PY)" esl/fixed_point.py --dir "$(MATRIX_DIR)" --heads 8 \
		--head-index 3 --query-rows 32 \
		--out "$(MATRIX_DIR)/rtl_head3_qblock0_in.bin" \
		--golden-in "$(MATRIX_DIR)/multihead_output_pre_wout.txt" \
		--golden-out "$(MATRIX_DIR)/rtl_head3_qblock0_golden.txt"

	echo ">>> [2/3] GHDL analiza..."
	rm -f rtl/work-obj*.cf
	$(GHDL) -a $(GHDL_FLAGS) --workdir=rtl $(RTL_SRCS)
	$(GHDL) -a $(GHDL_FLAGS) --workdir=rtl rtl/tb_fa_axis_real_head.vhd

	echo ">>> [3/3] GHDL simulacija; progress se ispisuje tokom K/V prenosa..."
	cd rtl
	$(GHDL) --elab-run $(GHDL_FLAGS) tb_fa_axis_real_head --assert-level=error

clean:
	rm -f data/multihead_attention_algorithm*.so
	rm -f data/vp_output.txt esl/simulation_tlm esl/src/*.o esl/*.o
	rm -f rtl/work-obj*.cf rtl/*.vcd rtl/*.ghw
	rm -f "$(MATRIX_DIR)/rtl_head3_qblock0_in.bin"
	rm -f "$(MATRIX_DIR)/rtl_head3_qblock0_golden.txt"
	echo ">>> Clean zavrsen; .venv i pune ESL matrice su sacuvani."
