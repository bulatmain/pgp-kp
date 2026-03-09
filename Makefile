CXX := g++
NVCC := nvcc

CXXFLAGS := -std=c++17 -O2 -Wall -Wextra -Iinclude
NVCCFLAGS := -std=c++17 -O2 -Iinclude

HAS_NVCC := $(shell command -v $(NVCC) >/dev/null 2>&1 && echo 1 || echo 0)

CPU_SRCS := \
	src/domain/polyhedra.cpp \
	src/application/config.cpp \
	src/application/app.cpp \
	src/adapters/cpu/cpu_renderer.cpp \
	src/adapters/file/ppm_writer.cpp \
	src/adapters/cli/main.cpp

ifeq ($(HAS_NVCC),1)
GPU_SRCS := src/adapters/gpu/cuda_renderer.cu
else
GPU_SRCS := src/adapters/gpu/cuda_renderer_stub.cpp
endif

CPU_OBJS := $(CPU_SRCS:.cpp=.o)
GPU_OBJS := $(GPU_SRCS:.cpp=.o)
GPU_OBJS := $(GPU_OBJS:.cu=.o)

TARGET := kp

all: $(TARGET)

$(TARGET): $(CPU_OBJS) $(GPU_OBJS)
ifeq ($(HAS_NVCC),1)
	$(NVCC) -o $@ $^
else
	$(CXX) -o $@ $^
endif

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.o: %.cu
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

clean:
	rm -f $(CPU_OBJS) $(GPU_OBJS) $(TARGET)

.PHONY: all clean
