
OUTPUT_DIR = ../data

SYSTEMC_HOME ?= $(HOME)/systemc-2.3.3
SYSTEMC_ARCH ?= -linux64
SYSTEMC_LINK = -lsystemc
SYSTEMC_STD ?= -std=c++14

CXX = g++
CXXFLAGS = -O3 -DSC_INCLUDE_FX -I. -Iheader -I.

SRCS = src/testbench_vp.cpp \
       src/vp.cpp \
       src/cpu.cpp \
       src/ip.cpp \
       src/dma.cpp \
       src/matrix_ops.cpp \
       src/bram_tlm.cpp \
       src/interconnect.cpp

OBJS :=  $(SRCS:.cpp=.o)

# Python biblioteke
PYTHON = python3
VENV_PY = .venv/bin/python
PYBIND_INCLUDES = $(shell $(PYTHON) -m pybind11 --includes)
PYBIND_SUFFIX = $(shell python3-config --extension-suffix)
PYBIND_FLAGS = -shared -fPIC

# SystemC biblioteke
SC_INCLUDE = -I$(SYSTEMC_HOME)/include
SC_LIB = -L$(SYSTEMC_HOME)/lib$(SYSTEMC_ARCH) -Wl,-rpath=$(SYSTEMC_HOME)/lib$(SYSTEMC_ARCH) $(SYSTEMC_LINK)

LIB_NAME = multihead_attention_algorithm$(PYBIND_SUFFIX)
VP_EXE = simulation_tlm

.PHONY: all check_venv check_deps_vp check_deps_app help run_app vp app install_deps clean

all: help

check_venv:
ifndef VIRTUAL_ENV
	$(error ERROR: Niste u Python virtuelnom okruzenju. Molimo Vas da ga aktivirate koristeci instrukcije na README-u.)
endif
	@echo "Trenutno Python virtuelno okruzenje: $(VIRTUAL_ENV)"

check_deps_vp:
	@# 1. Provera SystemC biblioteke...
	@printf "#include <systemc.h>\nint sc_main(int argc, char *argv[]) { return 0; }" > .test_sysc.cpp
	@$(CXX) $(SYSTEMC_STD) $(SC_INCLUDE) .test_sysc.cpp $(SC_LIB) -o .test_sysc_out > /dev/null 2>&1 && \
		(echo "SystemC pronadjen na $(SYSTEMC_HOME)"; rm -f .test_sysc.cpp .test_sysc_out) || \
		(echo "GRESKA: SystemC nije pronađen na $(SYSTEMC_HOME)"; \
		 echo "Rešenje: make vp SYSTEMC_HOME=/prava/putanja"; \
		 rm -f .test_sysc.cpp .test_sysc_out; exit 1)

check_deps_app: check_venv check_deps_vp
	@# 2. Provera PortAudio biblioteke...
	@# Trenutno ne moguce bez uvodjenja build sistema, a zadatak trazi da bude Makefile

	@# 3. Provera da li su python biblioteke instalirane
	@if [ -z "$(PYBIND_INCLUDES)" ]; then \
		echo "GRESKA: pybind11 nije pronadjen. Instaliraj sa 'make install_deps'"; \
		exit 1; \
	fi

help:
	@echo "------------------------------------------------------------------"
	@echo "Dostupne komande:"
	@echo "  make vp          -> Kompajlira i pokrece Virtuelnu Platformu (TLM)"
	@echo "  make app         -> Radi bukvalno sve sem clean"
	@echo "  make run_app     -> Glavni program"
	@echo "                      "
	@echo "  make install_deps-> Instalira potrebne Python biblioteke"
	@echo "  make clean       -> Brise sve generisane fajlove"
	@echo "------------------------------------------------------------------"


run_app: check_deps_app
	@echo ">>> Kompajliranje C++ wrapper-a za Python..."
	@mkdir -p ../data/matrice
	$(CXX) $(CXXFLAGS) $(PYBIND_FLAGS) $(PYBIND_INCLUDES) src/pybind_wrapper.cpp src/attention_module_multiple_heads.cpp -o $(OUTPUT_DIR)/$(LIB_NAME)
	@echo ">>> Pokretanje Python aplikacije..."
	@# Menjamo folder u kome Python trazi biblioteke jer PyBind biblioteka koju smo napravili je tehnicki build artifact, po tom moramo da gledamo folder 'izlaz'
	@PYTHONPATH=$(OUTPUT_DIR):$(PYTHONPATH) $(PYTHON) final_app.py

$(VENV_PY):
	@echo ">>> .venv ne postoji. kreiram i instaliram"
	python3 -m venv .venv
	@$(VENV_PY) -m pip install --upgrade pip
	@$(VENV_PY) -m pip install torch==2.9.1 --index-url https://download.pytorch.org/whl/cpu
	@$(VENV_PY) -m pip install numpy transformers==4.35.0 sounddevice soundfile pybind11

app: $(VENV_PY)
	@echo ">>> [1/4] Kompajliranje glavnog programa i generisanje matrica i golden-a..."
	@mkdir -p $(OUTPUT_DIR)/matrice
	@$(CXX) $(CXXFLAGS) $(PYBIND_FLAGS) $$($(VENV_PY) -m pybind11 --includes) src/pybind_wrapper.cpp src/attention_module_multiple_heads.cpp -o $(OUTPUT_DIR)/$(LIB_NAME)
	@PYTHONPATH=$(OUTPUT_DIR):$$PYTHONPATH $(VENV_PY) final_app.py
	@echo ">>> [2/4] Kompajliranje VP..."
	@$(MAKE) --no-print-directory $(VP_EXE)
	@echo ">>> [3/4] Pokretanje VP simulacije..."
	@./$(VP_EXE)
	@echo ">>> [4/4] Poredjenje VP izlaza sa golden rezultatom:"
	@$(VENV_PY) compare.py $(OUTPUT_DIR)/vp_output.txt $(OUTPUT_DIR)/matrice/output_main_app.txt

%.o: %.cpp
	@echo "Kompajliranje objekta: $@"
	@$(CXX) $(CXXFLAGS) $(SYSTEMC_STD) $(SC_INCLUDE) -c $< -o $@

$(OBJS): $(wildcard header/*.h)


$(VP_EXE): check_deps_vp $(OBJS)
	@echo ">>> Kompajliranje Virtuelne Platforme (TLM)..."
	$(CXX) $(SYSTEMC_STD) -o $@ $(OBJS) $(SC_LIB)

vp: check_deps_vp $(VP_EXE)
	@echo ">>> Pokretanje VP simulacije..."
	./$(VP_EXE)

install_deps: check_venv
	@echo ">>> Instaliranje Python biblioteka..."
	@# Instaliramo PyTorch bez GPU datoteka jer nam stvarno ne trebaju, a ogrmoni su fajlovi
	$(PYTHON) -m pip install torch==2.9.1 --index-url https://download.pytorch.org/whl/cpu
	@# Instaliramo sve ostalo
	$(PYTHON) -m pip install numpy transformers==4.35.0 sounddevice soundfile pybind11

clean:
	@echo ">>> Ciscenje..."
	rm -f $(OUTPUT_DIR)/$(LIB_NAME) $(VP_EXE)
	rm -f src/*.o *.o *.so
	rm -f vp_output.txt
	@echo ">>> Zavrseno."
