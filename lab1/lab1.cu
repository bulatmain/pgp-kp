    #include <cuda_runtime.h>
    #include <cstdio>
    #include <vector>
    #include <cstdlib>
    #include <chrono>
    #include <cstring>

    #define CSC(call) \
        do { \
            cudaError_t err = call; \
            if (err != cudaSuccess) { \
                fprintf(stderr, "CUDA error at %s:%d: %s\n", __FILE__, __LINE__, cudaGetErrorString(err)); \
                exit(EXIT_FAILURE); \
            } \
        } while(0)

    __global__ void vectorMulKernel(const double *a, const double *b, double *c, int n) {
        int idx = blockIdx.x * blockDim.x + threadIdx.x;
        
        if (idx < n) {
            c[idx] = a[idx] * b[idx];
        }
    }

    int main() {
        int n;
        
        if (scanf("%d", &n) != 1) {
            return 1;
        } else if (n <= 0) {
            return 0;
        }

        std::vector<double> h_a(n);
        std::vector<double> h_b(n);
        std::vector<double> h_c(n);

        for (int i = 0; i < n; ++i) {
            scanf("%lf", &h_a[i]);
        }
        
        for (int i = 0; i < n; ++i) {
            scanf("%lf", &h_b[i]);
        }

        const auto total_start = std::chrono::steady_clock::now();

        double *d_a = nullptr;
        double *d_b = nullptr;
        double *d_c = nullptr;

        size_t mem_size = n * sizeof(double);

        CSC(cudaMalloc(&d_a, mem_size));
        CSC(cudaMalloc(&d_b, mem_size));
        CSC(cudaMalloc(&d_c, mem_size));

        CSC(cudaMemcpy(d_a, h_a.data(), mem_size, cudaMemcpyHostToDevice));
        CSC(cudaMemcpy(d_b, h_b.data(), mem_size, cudaMemcpyHostToDevice));

        const int threadsPerBlock = 256;
        const int blocksPerGrid = (n + threadsPerBlock - 1) / threadsPerBlock;

        cudaEvent_t kernel_start;
        cudaEvent_t kernel_end;
        CSC(cudaEventCreate(&kernel_start));
        CSC(cudaEventCreate(&kernel_end));

        CSC(cudaEventRecord(kernel_start));

        vectorMulKernel<<<blocksPerGrid, threadsPerBlock>>>(d_a, d_b, d_c, n);

        CSC(cudaGetLastError());
        CSC(cudaDeviceSynchronize());
        CSC(cudaEventRecord(kernel_end));
        CSC(cudaEventSynchronize(kernel_end));

        float kernel_ms = 0.0f;
        CSC(cudaEventElapsedTime(&kernel_ms, kernel_start, kernel_end));

        CSC(cudaMemcpy(h_c.data(), d_c, mem_size, cudaMemcpyDeviceToHost));

        const auto total_end = std::chrono::steady_clock::now();
        const double total_ms = std::chrono::duration<double, std::milli>(total_end - total_start).count();

        const char *timing_path = std::getenv("LAB1_TIMING_FILE");
        if (timing_path == nullptr || std::strlen(timing_path) == 0) {
            timing_path = "timings_gpu.txt";
        }

        FILE *timing_file = std::fopen(timing_path, "a");
        if (timing_file != nullptr) {
            std::fprintf(
                timing_file,
                "n=%d grid=%d block=%d kernel_ms=%.6f total_ms=%.6f\n",
                n,
                blocksPerGrid,
                threadsPerBlock,
                static_cast<double>(kernel_ms),
                total_ms
            );
            std::fclose(timing_file);
        }

        for (int i = 0; i < n; ++i) {
            printf("%.10e%c", h_c[i], (i == n - 1) ? '\n' : ' ');
        }

        CSC(cudaFree(d_a));
        CSC(cudaFree(d_b));
        CSC(cudaFree(d_c));
        CSC(cudaEventDestroy(kernel_start));
        CSC(cudaEventDestroy(kernel_end));

        return 0;
    }
