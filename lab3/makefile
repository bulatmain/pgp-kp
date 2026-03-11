CFLAGS = -Werror cross-execution-space-call -lm --std=c++11
SOURCES = lab3.cu
BIN = lab3
CPU_BIN = lab3-cpu
CPU_SRC = lab3-cpu.cpp
NVCC = $(shell command -v nvcc 2> /dev/null)
CXX = g++
CXXFLAGS = -O2 -std=c++11

all: $(BIN) $(CPU_BIN)

$(BIN): $(SOURCES)
ifdef NVCC
	$(NVCC) $(CFLAGS) -o $(BIN) $(SOURCES)
else
	/usr/bin/nvcc $(CFLAGS) -o $(BIN) $(SOURCES)
endif

$(CPU_BIN): $(CPU_SRC)
	$(CXX) $(CXXFLAGS) -o $(CPU_BIN) $(CPU_SRC)

clean:
	rm -f $(BIN) $(CPU_BIN)
