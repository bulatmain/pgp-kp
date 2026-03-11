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

struct Pixel {
    unsigned char x;
    unsigned char y;
    unsigned char z;
    unsigned char w;
};

using Point = pair<int, int>;
using ClassPixels = vector<Point>;
using AllClassesPixels = vector<ClassPixels>;

struct Image {
    int width = 0;
    int height = 0;
    vector<Pixel> pixels;
};

static inline size_t pixelIndex(int x, int y, int width) {
    return static_cast<size_t>(y) * static_cast<size_t>(width) + static_cast<size_t>(x);
}

Image readImage(const string& path) {
    ifstream file(path, ios::binary);
    if (!file) {
        throw runtime_error("Cannot open input image");
    }

    Image img;
    file.read(reinterpret_cast<char*>(&img.width), sizeof(int));
    file.read(reinterpret_cast<char*>(&img.height), sizeof(int));
    if (!file || img.width <= 0 || img.height <= 0) {
        throw runtime_error("Invalid image header");
    }

    const size_t count = static_cast<size_t>(img.width) * static_cast<size_t>(img.height);
    img.pixels.resize(count);
    file.read(reinterpret_cast<char*>(img.pixels.data()), count * sizeof(Pixel));
    if (!file) {
        throw runtime_error("Invalid image data");
    }
    return img;
}

void writeImage(const string& path, const Image& img) {
    ofstream file(path, ios::binary);
    if (!file) {
        throw runtime_error("Cannot open output image");
    }
    file.write(reinterpret_cast<const char*>(&img.width), sizeof(int));
    file.write(reinterpret_cast<const char*>(&img.height), sizeof(int));
    file.write(reinterpret_cast<const char*>(img.pixels.data()),
               img.pixels.size() * sizeof(Pixel));
    if (!file) {
        throw runtime_error("Write error");
    }
}

void readInput(string& inPath, string& outPath, int& classCount, AllClassesPixels& samples) {
    cin >> inPath;
    cin >> outPath;
    cin >> classCount;
    if (!cin || classCount <= 0 || classCount > 32) {
        throw runtime_error("Invalid class count");
    }

    samples.assign(classCount, {});
    for (int c = 0; c < classCount; ++c) {
        int n = 0;
        cin >> n;
        if (!cin || n <= 0) {
            throw runtime_error("Invalid sample count");
        }
        samples[c].resize(n);
        for (int i = 0; i < n; ++i) {
            int x = 0, y = 0;
            cin >> x >> y;
            if (!cin) {
                throw runtime_error("Invalid sample coords");
            }
            samples[c][i] = {x, y};
        }
    }
}

vector<float> computeAverages(const Image& img, const AllClassesPixels& samples) {
    const int classCount = static_cast<int>(samples.size());
    vector<float> avg(classCount * 3, 0.0f);

    for (int c = 0; c < classCount; ++c) {
        double sumR = 0.0, sumG = 0.0, sumB = 0.0;
        for (const auto& p : samples[c]) {
            const int x = p.first;
            const int y = p.second;
            if (x < 0 || x >= img.width || y < 0 || y >= img.height) {
                throw runtime_error("Sample point out of image bounds");
            }
            const Pixel px = img.pixels[pixelIndex(x, y, img.width)];
            sumR += px.x;
            sumG += px.y;
            sumB += px.z;
        }
        const double n = static_cast<double>(samples[c].size());
        avg[c * 3 + 0] = static_cast<float>(sumR / n);
        avg[c * 3 + 1] = static_cast<float>(sumG / n);
        avg[c * 3 + 2] = static_cast<float>(sumB / n);
    }
    return avg;
}

void classify(Image& img, const vector<float>& avg, int classCount) {
    for (size_t i = 0; i < img.pixels.size(); ++i) {
        Pixel& px = img.pixels[i];
        const float r = static_cast<float>(px.x);
        const float g = static_cast<float>(px.y);
        const float b = static_cast<float>(px.z);

        float bestDist = FLT_MAX;
        int bestClass = 0;
        for (int c = 0; c < classCount; ++c) {
            const float dr = r - avg[c * 3 + 0];
            const float dg = g - avg[c * 3 + 1];
            const float db = b - avg[c * 3 + 2];
            const float d2 = dr * dr + dg * dg + db * db;
            if (d2 < bestDist) {
                bestDist = d2;
                bestClass = c;
            }
        }
        px.w = static_cast<unsigned char>(bestClass);
    }
}

void appendTiming(const Image& img, int classCount, double totalMs) {
    const char* path = std::getenv("LAB3_TIMING_FILE");
    if (!path || !*path) {
        path = "timings_cpu_lab3.txt";
    }
    FILE* f = std::fopen(path, "a");
    if (!f) {
        return;
    }
    std::fprintf(f, "w=%d h=%d pixels=%zu classes=%d total_ms=%.6f\n",
                 img.width, img.height, img.pixels.size(), classCount, totalMs);
    std::fclose(f);
}

int main() {
    try {
        ios::sync_with_stdio(false);
        cin.tie(nullptr);

        string inPath, outPath;
        int classCount = 0;
        AllClassesPixels samples;

        readInput(inPath, outPath, classCount, samples);
        Image img = readImage(inPath);
        vector<float> avg = computeAverages(img, samples);

        const auto t0 = std::chrono::steady_clock::now();
        classify(img, avg, classCount);
        const auto t1 = std::chrono::steady_clock::now();

        const double totalMs =
            std::chrono::duration<double, std::milli>(t1 - t0).count();
        appendTiming(img, classCount, totalMs);

        writeImage(outPath, img);
    } catch (const exception& e) {
        cerr << "[ERROR] " << e.what() << '\n';
        return 1;
    }
    return 0;
}
