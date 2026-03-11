#include <cuda_runtime.h>

#include <chrono>
#include <cfloat>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
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

using Pixel = uchar4;
using Point = pair<int, int>;
using ClassPixels = vector<Point>;
using AllClassesPixels = vector<ClassPixels>;

const int MAX_CLASSES = 32;

__constant__ float d_classAverages[MAX_CLASSES * 3];
__constant__ int d_classCount;

struct Image {
    int width;
    int height;
    vector<Pixel> pixels;
};

size_t getPixelIndex(int x, int y, int width) {
    return static_cast<size_t>(y) * width + x;
}

void printDebug(const string& text) { cerr << "[DEBUG] " << text << '\n'; }

Image readImageFromFile(const string& fileName) {
    printDebug("Открываем входной файл изображения: " + fileName);

    ifstream file(fileName, ios::binary);
    if (!file) {
        throw runtime_error("Не удалось открыть входной файл");
    }

    Image image;
    file.read(reinterpret_cast<char*>(&image.width), sizeof(int));
    file.read(reinterpret_cast<char*>(&image.height), sizeof(int));

    if (!file) {
        throw runtime_error("Не удалось прочитать размеры изображения");
    } else if (image.width <= 0 || image.height <= 0) {
        throw runtime_error("Некорректные размеры изображения");
    }

    size_t pixelCount = static_cast<size_t>(image.width) * image.height;
    image.pixels.resize(pixelCount);

    file.read(reinterpret_cast<char*>(image.pixels.data()),
              pixelCount * sizeof(Pixel));

    if (!file) {
        throw runtime_error("Не удалось прочитать пиксели изображения");
    }

    printDebug("Изображение прочитано: width = " + to_string(image.width) +
               ", height = " + to_string(image.height) +
               ", pixels = " + to_string(pixelCount));

    return image;
}

void writeImageToFile(const string& fileName, const Image& image) {
    printDebug("Сохраняем выходное изображение: " + fileName);

    ofstream file(fileName, ios::binary);
    if (!file) {
        throw runtime_error("Не удалось открыть выходной файл");
    }

    file.write(reinterpret_cast<const char*>(&image.width), sizeof(int));
    file.write(reinterpret_cast<const char*>(&image.height), sizeof(int));
    file.write(reinterpret_cast<const char*>(image.pixels.data()),
               image.pixels.size() * sizeof(Pixel));

    if (!file) {
        throw runtime_error("Ошибка при записи выходного файла");
    }

    printDebug("Выходное изображение успешно сохранено");
}

void readProgramInput(string& inputFileName, string& outputFileName,
                      int& classCount, AllClassesPixels& samplePixels) {
    printDebug("Читаем параметры программы из stdin");

    cin >> inputFileName;
    cin >> outputFileName;
    cin >> classCount;

    if (!cin) {
        throw runtime_error(
            "Не удалось прочитать имена файлов и число классов");
    } else if (classCount <= 0 || classCount > MAX_CLASSES) {
        throw runtime_error("Число классов должно быть от 1 до 32");
    }

    samplePixels.resize(classCount);

    for (int classId = 0; classId < classCount; ++classId) {
        int sampleCount;
        cin >> sampleCount;

        if (!cin) {
            throw runtime_error(
                "Не удалось прочитать число обучающих пикселей класса");
        } else if (sampleCount <= 0) {
            throw runtime_error(
                "У каждого класса должен быть хотя бы один обучающий пиксель");
        }

        samplePixels[classId].resize(sampleCount);

        for (int i = 0; i < sampleCount; ++i) {
            int x, y;
            cin >> x >> y;

            if (!cin) {
                throw runtime_error(
                    "Не удалось прочитать координаты обучающего пикселя");
            }

            samplePixels[classId][i] = {x, y};
        }

        printDebug("Класс " + to_string(classId) +
                   ": обучающих пикселей = " + to_string(sampleCount));
    }
}

void checkSamplePixelsInsideImage(const Image& image,
                                  const AllClassesPixels& samplePixels) {
    printDebug("Проверяем, что все обучающие пиксели лежат внутри изображения");

    for (int classId = 0; classId < static_cast<int>(samplePixels.size()); ++classId) {
        for (const Point& point : samplePixels[classId]) {
            int x = point.first;
            int y = point.second;

            if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
                throw runtime_error(
                    "Обучающий пиксель выходит за границы изображения");
            }
        }
    }

    printDebug("Все обучающие пиксели корректны");
}

vector<float> computeClassAverages(const Image& image,
                                   const AllClassesPixels& samplePixels) {
    printDebug("Считаем средние цвета для каждого класса");

    int classCount = static_cast<int>(samplePixels.size());
    vector<float> averages(classCount * 3, 0.0f);

    for (int classId = 0; classId < classCount; ++classId) {
        double sumR = 0.0;
        double sumG = 0.0;
        double sumB = 0.0;

        for (const Point& point : samplePixels[classId]) {
            int x = point.first;
            int y = point.second;

            Pixel pixel = image.pixels[getPixelIndex(x, y, image.width)];

            sumR += pixel.x;
            sumG += pixel.y;
            sumB += pixel.z;
        }

        double count = static_cast<double>(samplePixels[classId].size());

        averages[classId * 3 + 0] = static_cast<float>(sumR / count);
        averages[classId * 3 + 1] = static_cast<float>(sumG / count);
        averages[classId * 3 + 2] = static_cast<float>(sumB / count);

        cerr << "[DEBUG] Класс " << classId
             << ": avgR = " << averages[classId * 3 + 0]
             << ", avgG = " << averages[classId * 3 + 1]
             << ", avgB = " << averages[classId * 3 + 2] << '\n';
    }

    return averages;
}

void copyAveragesToConstantMemory(const vector<float>& averages,
                                  int classCount) {
    printDebug("Копируем средние цвета классов в constant memory GPU");

    CSC(cudaMemcpyToSymbol(d_classAverages, averages.data(),
                           classCount * 3 * sizeof(float)));

    CSC(cudaMemcpyToSymbol(d_classCount, &classCount, sizeof(int)));
}

Pixel* copyImageToGpu(const Image& image) {
    printDebug("Выделяем память на GPU и копируем туда изображение");

    Pixel* gpuPixels = nullptr;
    size_t bytes = image.pixels.size() * sizeof(Pixel);

    CSC(cudaMalloc(&gpuPixels, bytes));
    CSC(cudaMemcpy(gpuPixels, image.pixels.data(), bytes,
                   cudaMemcpyHostToDevice));

    return gpuPixels;
}

void copyImageFromGpu(Image& image, Pixel* gpuPixels) {
    printDebug("Копируем результат с GPU обратно на CPU");

    size_t bytes = image.pixels.size() * sizeof(Pixel);

    CSC(cudaMemcpy(image.pixels.data(), gpuPixels, bytes,
                   cudaMemcpyDeviceToHost));
}

void freeGpuMemory(Pixel* gpuPixels) {
    printDebug("Освобождаем память GPU");
    CSC(cudaFree(gpuPixels));
}

__global__ void classifyPixelsKernel(Pixel* pixels, int pixelCount) {
    int globalIndex = blockIdx.x * blockDim.x + threadIdx.x;

    if (globalIndex >= pixelCount) {
        return;
    }

    Pixel pixel = pixels[globalIndex];

    float r = static_cast<float>(pixel.x);
    float g = static_cast<float>(pixel.y);
    float b = static_cast<float>(pixel.z);

    float bestDistance = FLT_MAX;
    int bestClass = 0;

    for (int classId = 0; classId < d_classCount; ++classId) {
        float avgR = d_classAverages[classId * 3 + 0];
        float avgG = d_classAverages[classId * 3 + 1];
        float avgB = d_classAverages[classId * 3 + 2];

        float dr = r - avgR;
        float dg = g - avgG;
        float db = b - avgB;

        float distanceSquared = dr * dr + dg * dg + db * db;

        if (distanceSquared < bestDistance) {
            bestDistance = distanceSquared;
            bestClass = classId;
        }
    }

    pixel.w = static_cast<unsigned char>(bestClass);
    pixels[globalIndex] = pixel;
}

void runClassificationOnGpu(Pixel* gpuPixels, int pixelCount) {
    printDebug("Запускаем CUDA-ядро классификации");

    int threadsPerBlock = 256;
    int blocksPerGrid = (pixelCount + threadsPerBlock - 1) / threadsPerBlock;

    cerr << "[DEBUG] threadsPerBlock = " << threadsPerBlock
         << ", blocksPerGrid = " << blocksPerGrid << '\n';

    classifyPixelsKernel<<<blocksPerGrid, threadsPerBlock>>>(gpuPixels,
                                                             pixelCount);

    CSC(cudaGetLastError());
    CSC(cudaDeviceSynchronize());

    printDebug("CUDA-ядро завершило работу");
}

int getThreadsPerBlockFromEnv() {
    const char* env = std::getenv("LAB3_BLOCK_SIZE");
    if (!env || !*env) {
        return 256;
    }
    int value = std::atoi(env);
    if (value <= 0 || value > 1024) {
        return 256;
    }
    return value;
}

void appendTiming(int width, int height, int classCount, int pixelCount,
                  int blockSize, int gridSize, double kernelMs,
                  double totalMs) {
    const char* timingPath = std::getenv("LAB3_TIMING_FILE");
    if (!timingPath || !*timingPath) {
        timingPath = "timings_gpu_lab3.txt";
    }

    FILE* timingFile = std::fopen(timingPath, "a");
    if (!timingFile) {
        return;
    }

    std::fprintf(
        timingFile,
        "w=%d h=%d pixels=%d classes=%d grid=%d block=%d kernel_ms=%.6f total_ms=%.6f\n",
        width,
        height,
        pixelCount,
        classCount,
        gridSize,
        blockSize,
        kernelMs,
        totalMs);

    std::fclose(timingFile);
}

int main() {
    try {
        ios::sync_with_stdio(false);
        cin.tie(nullptr);

        string inputFileName;
        string outputFileName;
        int classCount;
        AllClassesPixels samplePixels;

        readProgramInput(inputFileName, outputFileName, classCount,
                         samplePixels);

        Image image = readImageFromFile(inputFileName);

        checkSamplePixelsInsideImage(image, samplePixels);

        vector<float> classAverages = computeClassAverages(image, samplePixels);

        copyAveragesToConstantMemory(classAverages, classCount);

        int pixelCount = image.width * image.height;
        int threadsPerBlock = getThreadsPerBlockFromEnv();
        int blocksPerGrid = (pixelCount + threadsPerBlock - 1) / threadsPerBlock;

        const auto totalStart = std::chrono::steady_clock::now();

        Pixel* gpuPixels = copyImageToGpu(image);

        cudaEvent_t kernelStart;
        cudaEvent_t kernelEnd;
        CSC(cudaEventCreate(&kernelStart));
        CSC(cudaEventCreate(&kernelEnd));
        CSC(cudaEventRecord(kernelStart));

        classifyPixelsKernel<<<blocksPerGrid, threadsPerBlock>>>(gpuPixels,
                                                                  pixelCount);

        CSC(cudaGetLastError());
        CSC(cudaDeviceSynchronize());
        CSC(cudaEventRecord(kernelEnd));
        CSC(cudaEventSynchronize(kernelEnd));

        float kernelMsF = 0.0f;
        CSC(cudaEventElapsedTime(&kernelMsF, kernelStart, kernelEnd));

        copyImageFromGpu(image, gpuPixels);

        const auto totalEnd = std::chrono::steady_clock::now();
        const double totalMs =
            std::chrono::duration<double, std::milli>(totalEnd - totalStart)
                .count();

        appendTiming(image.width, image.height, classCount, pixelCount,
                     threadsPerBlock, blocksPerGrid,
                     static_cast<double>(kernelMsF), totalMs);

        CSC(cudaEventDestroy(kernelStart));
        CSC(cudaEventDestroy(kernelEnd));

        freeGpuMemory(gpuPixels);

        writeImageToFile(outputFileName, image);

        printDebug("Программа завершилась успешно");
    } catch (const exception& e) {
        cerr << "[ERROR] " << e.what() << '\n';
        return 1;
    }

    return 0;
}
