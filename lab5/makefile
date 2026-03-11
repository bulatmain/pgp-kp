NVCC := $(shell command -v nvcc 2> /dev/null)
CXX := g++

NVCCFLAGS := -Werror cross-execution-space-call -lm --std=c++11
CXXFLAGS := -O2 -std=c++17

GPU_BIN := lab5
CPU_BIN := lab5-cpu

.PHONY: all clean

all: $(GPU_BIN) $(CPU_BIN)

$(GPU_BIN): lab5.cu
ifdef NVCC
	$(NVCC) $(NVCCFLAGS) -o $@ $<
else
	/usr/bin/nvcc $(NVCCFLAGS) -o $@ $<
endif

$(CPU_BIN): lab5-cpu.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

clean:
	rm -f $(GPU_BIN) $(CPU_BIN)
