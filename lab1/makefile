CFLAGS = -Werror cross-execution-space-call -lm --std=c++11
SOURCES = lab1.cu
BIN = lab1
NVCC = $(shell command -v nvcc 2> /dev/null)

all:
ifdef NVCC
	$(NVCC) $(CFLAGS) -o $(BIN) $(SOURCES)
else
	/usr/bin/nvcc $(CFLAGS) -o $(BIN) $(SOURCES)
endif