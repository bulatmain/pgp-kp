#include <cuda_runtime.h>

#include <cmath>
#include <chrono>
#include <cstring>
#include <fstream>
#include <iostream>
#include <vector>

using namespace std;

#define BLOCK 16

#define CSC(call)                                                   \
    do {                                                            \
        cudaError_t __res = call;                                   \
        if (__res != cudaSuccess) {                                 \
            fprintf(stderr, "ERROR %s:%d %s\n", __FILE__, __LINE__, \
                    cudaGetErrorString(__res));                     \
            exit(0);                                                \
        }                                                           \
    } while (0)

__global__ void prewittKernel(cudaTextureObject_t tex, uchar4* out, int w,
                              int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    if (x >= w || y >= h) return;

    int kx[3][3] = {{-1, 0, 1}, {-1, 0, 1}, {-1, 0, 1}};

    int ky[3][3] = {{1, 1, 1}, {0, 0, 0}, {-1, -1, -1}};

    float gx = 0, gy = 0;

    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            uchar4 c = tex2D<uchar4>(tex, x + i, y + j);
            
            float gray = 0.299f * c.x + 0.587f * c.y + 0.114f * c.z;

            gx += gray * kx[j + 1][i + 1];
            gy += gray * ky[j + 1][i + 1];
        }
    }

    float g = sqrtf(gx*gx + gy*gy);

    uchar4 r; 
    r.x = r.y = r.z = (unsigned char) fminf(255.0f, fmaxf(0.0f, g)); 
    r.w = 0;

    out[y * w + x] = r;
}

void readImage(string path, int& w, int& h, vector<uchar4>& img) {
    fprintf(stderr, "Reading %s\n", path.c_str());

    ifstream f(path, ios::binary);

    f.read((char*)&w, 4);
    f.read((char*)&h, 4);

    img.resize(w * h);

    for (int i = 0; i < w * h; i++) {
        uint32_t p;
        f.read((char*)&p, 4);
        img[i].x = p & 255;
        img[i].y = (p >> 8) & 255;
        img[i].z = (p >> 16) & 255;
        img[i].w = (p >> 24) & 255;
    }

    fprintf(stderr, "Image %dx%d\n", w, h);
}

void writeImage(string path, int w, int h, vector<uchar4>& img) {
    fprintf(stderr, "Writing %s\n", path.c_str());

    ofstream f(path, ios::binary);

    f.write((char*)&w, 4);
    f.write((char*)&h, 4);

    for (auto& p : img) {
        uint32_t v = p.x | (p.y << 8) | (p.z << 16) | (p.w << 24);
        f.write((char*)&v, 4);
    }
}

int main() {
    string inFile, outFile;

    getline(cin, inFile);
    getline(cin, outFile);

    int w, h;
    vector<uchar4> img;

    readImage(inFile, w, h, img);

    const auto total_start = std::chrono::steady_clock::now();

    cudaArray* arr;
    cudaChannelFormatDesc ch = cudaCreateChannelDesc<uchar4>();

    CSC(cudaMallocArray(&arr, &ch, w, h));

    CSC(cudaMemcpy2DToArray(arr, 0, 0, img.data(), w * sizeof(uchar4),
                            w * sizeof(uchar4), h, cudaMemcpyHostToDevice));

    fprintf(stderr, "Image copied to GPU\n");

    cudaResourceDesc resourceDesc{};
    resourceDesc.resType = cudaResourceTypeArray;
    resourceDesc.res.array.array = arr;

    cudaTextureDesc texDesc{};
    texDesc.addressMode[0] = cudaAddressModeClamp;
    texDesc.addressMode[1] = cudaAddressModeClamp;
    texDesc.filterMode = cudaFilterModePoint;
    texDesc.readMode = cudaReadModeElementType;

    cudaTextureObject_t tex;

    CSC(cudaCreateTextureObject(&tex, &resourceDesc, &texDesc, NULL));

    uchar4* d_out;
    CSC(cudaMalloc(&d_out, w * h * sizeof(uchar4)));

    dim3 block(BLOCK, BLOCK);
    dim3 grid((w + BLOCK - 1) / BLOCK, (h + BLOCK - 1) / BLOCK);

    fprintf(stderr, "Kernel launch %dx%d\n", grid.x, grid.y);

    cudaEvent_t kernel_start;
    cudaEvent_t kernel_end;
    CSC(cudaEventCreate(&kernel_start));
    CSC(cudaEventCreate(&kernel_end));
    CSC(cudaEventRecord(kernel_start));

    prewittKernel<<<grid, block>>>(tex, d_out, w, h);

    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());
    CSC(cudaEventRecord(kernel_end));
    CSC(cudaEventSynchronize(kernel_end));

    float kernel_ms = 0.0f;
    CSC(cudaEventElapsedTime(&kernel_ms, kernel_start, kernel_end));

    vector<uchar4> out(w * h);

    CSC(cudaMemcpy(out.data(), d_out, w * h * sizeof(uchar4),
                   cudaMemcpyDeviceToHost));

    const auto total_end = std::chrono::steady_clock::now();
    const double total_ms =
        std::chrono::duration<double, std::milli>(total_end - total_start)
            .count();

    const char* timing_path = std::getenv("LAB2_TIMING_FILE");
    if (timing_path == nullptr || std::strlen(timing_path) == 0) {
        timing_path = "timings_gpu_lab2.txt";
    }

    FILE* timing_file = std::fopen(timing_path, "a");
    if (timing_file != nullptr) {
        std::fprintf(
            timing_file,
            "w=%d h=%d grid_x=%d grid_y=%d block_x=%d block_y=%d kernel_ms=%.6f total_ms=%.6f\n",
            w,
            h,
            grid.x,
            grid.y,
            block.x,
            block.y,
            static_cast<double>(kernel_ms),
            total_ms);
        std::fclose(timing_file);
    }

    writeImage(outFile, w, h, out);

    CSC(cudaDestroyTextureObject(tex));
    CSC(cudaFreeArray(arr));
    CSC(cudaFree(d_out));
    CSC(cudaEventDestroy(kernel_start));
    CSC(cudaEventDestroy(kernel_end));

    fprintf(stderr, "Done\n");
}
