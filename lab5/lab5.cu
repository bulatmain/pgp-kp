#include <cuda_runtime.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace std;

#define CSC(call)                                                   \
    do {                                                            \
        cudaError_t __res = call;                                   \
        if (__res != cudaSuccess) {                                 \
            fprintf(stderr, "ERROR %s:%d %s\n", __FILE__, __LINE__, \
                    cudaGetErrorString(__res));                     \
            exit(0);                                                \
        }                                                           \
    } while (0)

using Byte = unsigned char;
using Counter = unsigned int;
using ByteArray = vector<Byte>;

const int VALUE_COUNT = 256;
const int SCAN_SIZE = 256;
const int SCAN_THREADS = 128;
const int NUM_BANKS = 32;
const int LOG_NUM_BANKS = 5;

struct KernelConfig {
    int histogramThreads = 256;
    int fillThreads = 128;
    int histogramMaxBlocks = 1024;
};

bool isDebugEnabled() {
    static bool enabled = [] {
        const char* v = std::getenv("LAB5_DEBUG");
        if (!v || !*v) {
            return false;
        }
        return std::string(v) == "1";
    }();
    return enabled;
}

void debug(const string& text) {
    if (isDebugEnabled()) {
        cerr << "[DEBUG] " << text << '\n';
    }
}

int readEnvInt(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (!v || !*v) {
        return fallback;
    }
    int x = std::atoi(v);
    if (x <= 0) {
        return fallback;
    }
    return x;
}

KernelConfig readKernelConfig() {
    KernelConfig cfg;
    cfg.histogramThreads = readEnvInt("LAB5_HIST_THREADS", 256);
    cfg.fillThreads = readEnvInt("LAB5_FILL_THREADS", 128);
    cfg.histogramMaxBlocks = readEnvInt("LAB5_HIST_MAX_BLOCKS", 1024);

    if (cfg.histogramThreads > 1024) cfg.histogramThreads = 1024;
    if (cfg.fillThreads > 1024) cfg.fillThreads = 1024;
    if (cfg.histogramMaxBlocks < 1) cfg.histogramMaxBlocks = 1;
    if (cfg.histogramMaxBlocks > 65535) cfg.histogramMaxBlocks = 65535;

    return cfg;
}

void appendGpuTiming(int n, const KernelConfig& cfg, double kernelMs,
                     double totalMs) {
    const char* path = std::getenv("LAB5_TIMING_FILE");
    if (!path || !*path) {
        path = "timings_gpu_lab5.txt";
    }

    FILE* f = std::fopen(path, "a");
    if (!f) {
        return;
    }

    std::fprintf(f,
                 "n=%d hist_threads=%d fill_threads=%d hist_max_blocks=%d "
                 "kernel_ms=%.6f total_ms=%.6f\n",
                 n, cfg.histogramThreads, cfg.fillThreads,
                 cfg.histogramMaxBlocks, kernelMs, totalMs);
    std::fclose(f);
}

__host__ __device__ int conflictFreeOffset(int index) {
    return index >> LOG_NUM_BANKS;
}

struct InputData {
    int n = 0;
    ByteArray values;
};

InputData readInput() {
    debug("Читаем бинарный вход из stdin");

    InputData data;

    if (fread(&data.n, sizeof(int), 1, stdin) != 1) {
        throw runtime_error("Не удалось прочитать n");
    }

    if (data.n < 0) {
        throw runtime_error("n не может быть отрицательным");
    }

    data.values.resize(static_cast<size_t>(data.n));

    if (data.n > 0) {
        size_t readCount = fread(data.values.data(), sizeof(Byte),
                                 static_cast<size_t>(data.n), stdin);
        if (readCount != static_cast<size_t>(data.n)) {
            throw runtime_error("Не удалось прочитать массив значений");
        }
    }

    debug("Вход успешно прочитан, n = " + to_string(data.n));
    return data;
}

void writeOutput(const ByteArray& values) {
    debug("Записываем отсортированный массив в stdout");

    if (!values.empty()) {
        size_t written =
            fwrite(values.data(), sizeof(Byte), values.size(), stdout);
        if (written != values.size()) {
            throw runtime_error("Не удалось записать выходные данные");
        }
    }

    fflush(stdout);
}

__global__ void clearHistogramKernel(Counter* histogram) {
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index < VALUE_COUNT) {
        histogram[index] = 0;
    }
}

__global__ void buildHistogramKernel(const Byte* data, int n,
                                     Counter* globalHistogram) {
    __shared__ Counter localHistogram[VALUE_COUNT];

    int tid = threadIdx.x;

    if (tid < VALUE_COUNT) {
        localHistogram[tid] = 0;
    }
    __syncthreads();

    int globalIndex = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    while (globalIndex < n) {
        Byte value = data[globalIndex];
        atomicAdd(&localHistogram[value], 1u);
        globalIndex += stride;
    }
    __syncthreads();

    if (tid < VALUE_COUNT) {
        atomicAdd(&globalHistogram[tid], localHistogram[tid]);
    }
}

__global__ void scan256Kernel(const Counter* histogram, Counter* offsets) {
    __shared__ Counter temp[SCAN_SIZE + SCAN_SIZE / NUM_BANKS];

    int tid = threadIdx.x;

    int ai = tid;
    int bi = tid + (SCAN_SIZE / 2);

    int bankAi = conflictFreeOffset(ai);
    int bankBi = conflictFreeOffset(bi);

    temp[ai + bankAi] = histogram[ai];
    temp[bi + bankBi] = histogram[bi];

    int offset = 1;

    for (int d = SCAN_SIZE / 2; d > 0; d >>= 1) {
        __syncthreads();

        if (tid < d) {
            int left = offset * (2 * tid + 1) - 1;
            int right = offset * (2 * tid + 2) - 1;

            left += conflictFreeOffset(left);
            right += conflictFreeOffset(right);

            temp[right] += temp[left];
        }

        offset <<= 1;
    }

    if (tid == 0) {
        int last = SCAN_SIZE - 1;
        temp[last + conflictFreeOffset(last)] = 0;
    }

    for (int d = 1; d < SCAN_SIZE; d <<= 1) {
        offset >>= 1;
        __syncthreads();

        if (tid < d) {
            int left = offset * (2 * tid + 1) - 1;
            int right = offset * (2 * tid + 2) - 1;

            left += conflictFreeOffset(left);
            right += conflictFreeOffset(right);

            Counter value = temp[left];
            temp[left] = temp[right];
            temp[right] += value;
        }
    }

    __syncthreads();

    offsets[ai] = temp[ai + bankAi];
    offsets[bi] = temp[bi + bankBi];
}

__global__ void fillSortedArrayKernel(const Counter* histogram,
                                      const Counter* offsets, Byte* output) {
    int value = blockIdx.x;
    if (value >= VALUE_COUNT) {
        return;
    }

    Counter start = offsets[value];
    Counter count = histogram[value];

    for (Counter i = threadIdx.x; i < count; i += blockDim.x) {
        output[start + i] = static_cast<Byte>(value);
    }
}

struct DeviceMemory {
    Byte* input = nullptr;
    Byte* output = nullptr;
    Counter* histogram = nullptr;
    Counter* offsets = nullptr;
};

void allocateDeviceMemory(DeviceMemory& gpu, int n) {
    debug("Выделяем память на GPU");

    if (n > 0) {
        CSC(cudaMalloc(&gpu.input, static_cast<size_t>(n) * sizeof(Byte)));
        CSC(cudaMalloc(&gpu.output, static_cast<size_t>(n) * sizeof(Byte)));
    }

    CSC(cudaMalloc(&gpu.histogram, VALUE_COUNT * sizeof(Counter)));
    CSC(cudaMalloc(&gpu.offsets, VALUE_COUNT * sizeof(Counter)));
}

void freeDeviceMemory(DeviceMemory& gpu) {
    debug("Освобождаем память GPU");

    if (gpu.input != nullptr) {
        CSC(cudaFree(gpu.input));
    }
    if (gpu.output != nullptr) {
        CSC(cudaFree(gpu.output));
    }
    if (gpu.histogram != nullptr) {
        CSC(cudaFree(gpu.histogram));
    }
    if (gpu.offsets != nullptr) {
        CSC(cudaFree(gpu.offsets));
    }
}

void copyInputToGpu(const ByteArray& values, DeviceMemory& gpu) {
    debug("Копируем входной массив на GPU");

    if (!values.empty()) {
        CSC(cudaMemcpy(gpu.input, values.data(), values.size() * sizeof(Byte),
                       cudaMemcpyHostToDevice));
    }
}

ByteArray copyOutputFromGpu(int n, const DeviceMemory& gpu) {
    debug("Копируем отсортированный массив с GPU на CPU");

    ByteArray values(static_cast<size_t>(n));

    if (n > 0) {
        CSC(cudaMemcpy(values.data(), gpu.output,
                       static_cast<size_t>(n) * sizeof(Byte),
                       cudaMemcpyDeviceToHost));
    }

    return values;
}

int chooseHistogramBlockCount(int n, int threads, int maxBlocks) {
    if (n <= 0) {
        return 1;
    }

    int blocks = (n + threads - 1) / threads;
    if (blocks > maxBlocks) {
        blocks = maxBlocks;
    }
    if (blocks < 1) {
        blocks = 1;
    }

    return blocks;
}

void clearHistogram(DeviceMemory& gpu, const KernelConfig& cfg) {
    debug("Обнуляем глобальную гистограмму");

    const int blocks = (VALUE_COUNT + cfg.histogramThreads - 1) /
                       cfg.histogramThreads;
    clearHistogramKernel<<<blocks, cfg.histogramThreads>>>(gpu.histogram);
    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());
}

void buildHistogram(const DeviceMemory& gpu, int n, const KernelConfig& cfg) {
    debug("Строим гистограмму на GPU через atomicAdd и shared memory");

    if (n <= 0) {
        return;
    }

    const int blocks = chooseHistogramBlockCount(
        n, cfg.histogramThreads, cfg.histogramMaxBlocks);

    debug("histogram blocks = " + to_string(blocks) +
          ", threads = " + to_string(cfg.histogramThreads));

    buildHistogramKernel<<<blocks, cfg.histogramThreads>>>(gpu.input, n,
                                                           gpu.histogram);
    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());
}

void runScan(const DeviceMemory& gpu) {
    debug("Выполняем exclusive scan по гистограмме");

    scan256Kernel<<<1, SCAN_THREADS>>>(gpu.histogram, gpu.offsets);
    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());
}

void buildSortedArray(const DeviceMemory& gpu, int n, const KernelConfig& cfg) {
    debug("Восстанавливаем отсортированный массив по гистограмме и offsets");

    if (n <= 0) {
        return;
    }

    fillSortedArrayKernel<<<VALUE_COUNT, cfg.fillThreads>>>(
        gpu.histogram, gpu.offsets, gpu.output);
    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());
}

void runSortingOnGpu(const InputData& input, DeviceMemory& gpu,
                     const KernelConfig& cfg) {
    clearHistogram(gpu, cfg);
    buildHistogram(gpu, input.n, cfg);
    runScan(gpu);
    buildSortedArray(gpu, input.n, cfg);
}

int main() {
    try {
        ios::sync_with_stdio(false);
        cin.tie(nullptr);

        InputData input = readInput();

        if (input.n == 0) {
            debug("n = 0, сортировать нечего");
            return 0;
        }

        KernelConfig cfg = readKernelConfig();

        DeviceMemory gpu;

        const auto totalStart = std::chrono::steady_clock::now();
        allocateDeviceMemory(gpu, input.n);
        copyInputToGpu(input.values, gpu);

        cudaEvent_t kernelStart;
        cudaEvent_t kernelEnd;
        CSC(cudaEventCreate(&kernelStart));
        CSC(cudaEventCreate(&kernelEnd));
        CSC(cudaEventRecord(kernelStart));

        runSortingOnGpu(input, gpu, cfg);

        CSC(cudaEventRecord(kernelEnd));
        CSC(cudaEventSynchronize(kernelEnd));
        float kernelMsF = 0.0f;
        CSC(cudaEventElapsedTime(&kernelMsF, kernelStart, kernelEnd));

        ByteArray output = copyOutputFromGpu(input.n, gpu);

        const auto totalEnd = std::chrono::steady_clock::now();
        const double totalMs =
            std::chrono::duration<double, std::milli>(totalEnd - totalStart)
                .count();

        appendGpuTiming(input.n, cfg, static_cast<double>(kernelMsF), totalMs);

        writeOutput(output);

        CSC(cudaEventDestroy(kernelStart));
        CSC(cudaEventDestroy(kernelEnd));
        freeDeviceMemory(gpu);
        debug("Программа завершилась успешно");
    } catch (const exception& e) {
        cerr << "[ERROR] " << e.what() << '\n';
        return 1;
    }

    return 0;
}
