#include <cuda_runtime.h>
#include <thrust/extrema.h>
#include <thrust/iterator/counting_iterator.h>
#include <thrust/iterator/transform_iterator.h>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iomanip>
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

using Matrix = vector<double>;
using Vector = vector<double>;

const double EPS = 1e-12;

void debug(const string& text) { cerr << "[DEBUG] " << text << '\n'; }

int id(int row, int col, int cols) { return row * cols + col; }

struct KernelConfig {
    int swapThreads = 256;
    int factorThreads = 256;
    int eliminateBlockX = 16;
    int eliminateBlockY = 16;
};

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
    cfg.swapThreads = readEnvInt("LAB4_SWAP_THREADS", 256);
    cfg.factorThreads = readEnvInt("LAB4_FACTOR_THREADS", 256);
    cfg.eliminateBlockX = readEnvInt("LAB4_ELIM_BLOCK_X", 16);
    cfg.eliminateBlockY = readEnvInt("LAB4_ELIM_BLOCK_Y", 16);

    if (cfg.swapThreads > 1024) cfg.swapThreads = 1024;
    if (cfg.factorThreads > 1024) cfg.factorThreads = 1024;
    if (cfg.eliminateBlockX > 32) cfg.eliminateBlockX = 32;
    if (cfg.eliminateBlockY > 32) cfg.eliminateBlockY = 32;
    if (cfg.eliminateBlockX * cfg.eliminateBlockY > 1024) {
        cfg.eliminateBlockX = 16;
        cfg.eliminateBlockY = 16;
    }
    return cfg;
}

void appendGpuTiming(int n, const KernelConfig& cfg, double kernelMs,
                     double totalMs) {
    const char* path = std::getenv("LAB4_TIMING_FILE");
    if (!path || !*path) {
        path = "timings_gpu_lab4.txt";
    }
    FILE* f = std::fopen(path, "a");
    if (!f) {
        return;
    }
    std::fprintf(
        f,
        "n=%d swap_threads=%d factor_threads=%d elim_block_x=%d elim_block_y=%d kernel_ms=%.6f total_ms=%.6f\n",
        n, cfg.swapThreads, cfg.factorThreads, cfg.eliminateBlockX,
        cfg.eliminateBlockY, kernelMs, totalMs);
    std::fclose(f);
}

void readInput(int& n, Matrix& a, Vector& b) {
    debug("Читаем входные данные");

    cin >> n;
    if (!cin || n <= 0) {
        throw runtime_error("Не удалось прочитать размер матрицы");
    }

    a.resize(n * n);
    b.resize(n);

    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            cin >> a[id(i, j, n)];
            if (!cin) {
                throw runtime_error("Не удалось прочитать элементы матрицы A");
            }
        }
    }

    for (int i = 0; i < n; ++i) {
        cin >> b[i];
        if (!cin) {
            throw runtime_error("Не удалось прочитать элементы вектора b");
        }
    }

    debug("Входные данные успешно прочитаны");
}

Matrix makeAugmentedMatrix(int n, const Matrix& a, const Vector& b) {
    debug("Собираем расширенную матрицу [A | b]");

    int cols = n + 1;
    Matrix m(n * cols);

    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            m[id(i, j, cols)] = a[id(i, j, n)];
        }
        m[id(i, n, cols)] = b[i];
    }

    return m;
}

struct ColumnAbsValue {
    double* data;
    int cols;
    int startRow;
    int col;

    __host__ __device__ double operator()(int offset) const {
        int row = startRow + offset;
        double value = data[row * cols + col];
        return value >= 0.0 ? value : -value;
    }
};

int findPivotRow(double* d_matrix, int n, int cols, int k) {
    auto beginIndex = thrust::counting_iterator<int>(0);
    auto begin = thrust::make_transform_iterator(
        beginIndex, ColumnAbsValue{d_matrix, cols, k, k});
    auto end = begin + (n - k);

    auto best = thrust::max_element(begin, end);
    int offset = static_cast<int>(best - begin);
    int pivotRow = k + offset;

    return pivotRow;
}

double readDeviceValue(double* d_matrix, int row, int col, int cols) {
    double value = 0.0;
    CSC(cudaMemcpy(&value, d_matrix + id(row, col, cols), sizeof(double),
                   cudaMemcpyDeviceToHost));
    return value;
}

__global__ void swapRowsKernel(double* matrix, int cols, int row1, int row2) {
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (col >= cols) {
        return;
    }

    double tmp = matrix[row1 * cols + col];
    matrix[row1 * cols + col] = matrix[row2 * cols + col];
    matrix[row2 * cols + col] = tmp;
}

void swapRowsOnGpu(double* d_matrix, int cols, int row1, int row2,
                   int threads) {
    if (row1 == row2) {
        return;
    }

    debug("Меняем строки " + to_string(row1) + " и " + to_string(row2));

    int blocks = (cols + threads - 1) / threads;

    swapRowsKernel<<<blocks, threads>>>(d_matrix, cols, row1, row2);
    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());
}

__global__ void computeFactorsKernel(const double* matrix, double* factors,
                                     int n, int cols, int k) {
    int row = k + 1 + blockIdx.x * blockDim.x + threadIdx.x;

    if (row >= n) {
        return;
    }

    double pivot = matrix[k * cols + k];
    factors[row] = matrix[row * cols + k] / pivot;
}

void computeFactors(double* d_matrix, double* d_factors, int n, int cols,
                    int k, int threads) {
    debug("Считаем коэффициенты исключения для шага k = " + to_string(k));

    int rowsBelow = n - (k + 1);
    if (rowsBelow <= 0) {
        return;
    }

    int blocks = (rowsBelow + threads - 1) / threads;

    computeFactorsKernel<<<blocks, threads>>>(d_matrix, d_factors, n, cols, k);
    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());
}

__global__ void eliminateKernel(double* matrix, const double* factors, int n,
                                int cols, int k) {
    int col = k + blockIdx.x * blockDim.x + threadIdx.x;
    int row = k + 1 + blockIdx.y * blockDim.y + threadIdx.y;

    if (row >= n || col >= cols) {
        return;
    }

    double factor = factors[row];

    if (col == k) {
        matrix[row * cols + col] = 0.0;
        return;
    }

    matrix[row * cols + col] -= factor * matrix[k * cols + col];
}

void eliminateBelowPivot(double* d_matrix, double* d_factors, int n, int cols,
                         int k, int blockX, int blockY) {
    debug("Обнуляем элементы ниже главного элемента для шага k = " +
          to_string(k));

    int rowsBelow = n - (k + 1);
    int colsToUpdate = cols - k;

    if (rowsBelow <= 0 || colsToUpdate <= 0) {
        return;
    }

    dim3 threads(blockX, blockY);
    dim3 blocks((colsToUpdate + threads.x - 1) / threads.x,
                (rowsBelow + threads.y - 1) / threads.y);

    eliminateKernel<<<blocks, threads>>>(d_matrix, d_factors, n, cols, k);
    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());
}

void forwardElimination(double* d_matrix, double* d_factors, int n,
                        const KernelConfig& cfg) {
    debug("Начинаем прямой ход метода Гаусса");

    int cols = n + 1;

    for (int k = 0; k < n; ++k) {
        int pivotRow = findPivotRow(d_matrix, n, cols, k);
        double pivotValue = readDeviceValue(d_matrix, pivotRow, k, cols);

        cerr << "[DEBUG] k = " << k << ", pivotRow = " << pivotRow
             << ", pivotValue = " << pivotValue << '\n';

        if (fabs(pivotValue) < EPS) {
            throw runtime_error(
                "Система не имеет единственного решения: найден нулевой "
                "главный элемент");
        }

        swapRowsOnGpu(d_matrix, cols, k, pivotRow, cfg.swapThreads);
        computeFactors(d_matrix, d_factors, n, cols, k, cfg.factorThreads);
        eliminateBelowPivot(d_matrix, d_factors, n, cols, k,
                            cfg.eliminateBlockX, cfg.eliminateBlockY);
    }

    debug("Прямой ход завершён");
}

Matrix copyMatrixFromGpu(double* d_matrix, int n, int cols) {
    debug("Копируем расширенную матрицу с GPU на CPU");

    Matrix m(n * cols);
    CSC(cudaMemcpy(m.data(), d_matrix, sizeof(double) * n * cols,
                   cudaMemcpyDeviceToHost));
    return m;
}

Vector backSubstitution(const Matrix& m, int n) {
    debug("Начинаем обратный ход");

    int cols = n + 1;
    Vector x(n, 0.0);

    for (int i = n - 1; i >= 0; --i) {
        double sum = m[id(i, n, cols)];

        for (int j = i + 1; j < n; ++j) {
            sum -= m[id(i, j, cols)] * x[j];
        }

        double diag = m[id(i, i, cols)];
        if (fabs(diag) < EPS) {
            throw runtime_error(
                "Система не имеет единственного решения: ноль на диагонали при "
                "обратном ходе");
        }

        x[i] = sum / diag;
    }

    debug("Обратный ход завершён");
    return x;
}

void printAnswer(const Vector& x) {
    cout << scientific << setprecision(10);
    for (int i = 0; i < static_cast<int>(x.size()); ++i) {
        if (i > 0) {
            cout << ' ';
        }
        cout << x[i];
    }
    cout << '\n';
}

int main() {
    try {
        ios::sync_with_stdio(false);
        cin.tie(nullptr);

        int n = 0;
        Matrix a;
        Vector b;

        readInput(n, a, b);
        KernelConfig cfg = readKernelConfig();

        Matrix augmented = makeAugmentedMatrix(n, a, b);

        int cols = n + 1;
        double* d_matrix = nullptr;
        double* d_factors = nullptr;

        debug("Выделяем память на GPU");
        const auto totalStart = std::chrono::steady_clock::now();
        CSC(cudaMalloc(&d_matrix, sizeof(double) * n * cols));
        CSC(cudaMalloc(&d_factors, sizeof(double) * n));

        debug("Копируем расширенную матрицу на GPU");
        CSC(cudaMemcpy(d_matrix, augmented.data(), sizeof(double) * n * cols,
                       cudaMemcpyHostToDevice));

        cudaEvent_t kernelStart;
        cudaEvent_t kernelEnd;
        CSC(cudaEventCreate(&kernelStart));
        CSC(cudaEventCreate(&kernelEnd));
        CSC(cudaEventRecord(kernelStart));

        forwardElimination(d_matrix, d_factors, n, cfg);

        CSC(cudaEventRecord(kernelEnd));
        CSC(cudaEventSynchronize(kernelEnd));
        float kernelMsF = 0.0f;
        CSC(cudaEventElapsedTime(&kernelMsF, kernelStart, kernelEnd));

        Matrix upper = copyMatrixFromGpu(d_matrix, n, cols);
        Vector x = backSubstitution(upper, n);

        const auto totalEnd = std::chrono::steady_clock::now();
        const double totalMs =
            std::chrono::duration<double, std::milli>(totalEnd - totalStart)
                .count();
        appendGpuTiming(n, cfg, static_cast<double>(kernelMsF), totalMs);

        printAnswer(x);

        debug("Освобождаем память GPU");
        CSC(cudaFree(d_matrix));
        CSC(cudaFree(d_factors));
        CSC(cudaEventDestroy(kernelStart));
        CSC(cudaEventDestroy(kernelEnd));

        debug("Программа завершилась успешно");
    } catch (const exception& e) {
        cerr << "[ERROR] " << e.what() << '\n';
        return 1;
    }

    return 0;
}
