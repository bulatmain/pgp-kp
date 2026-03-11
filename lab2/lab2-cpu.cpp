#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <vector>

using namespace std;

struct Pixel {
    unsigned char x;
    unsigned char y;
    unsigned char z;
    unsigned char w;
};

static inline int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

void readImage(const string& path, int& w, int& h, vector<Pixel>& img) {
    ifstream f(path, ios::binary);
    if (!f) {
        fprintf(stderr, "Failed to open input file: %s\n", path.c_str());
        exit(1);
    }

    f.read((char*)&w, 4);
    f.read((char*)&h, 4);

    if (w <= 0 || h <= 0) {
        fprintf(stderr, "Invalid image size: %d x %d\n", w, h);
        exit(1);
    }

    img.resize((size_t)w * (size_t)h);
    for (int i = 0; i < w * h; i++) {
        uint32_t p = 0;
        f.read((char*)&p, 4);
        img[i].x = p & 255;
        img[i].y = (p >> 8) & 255;
        img[i].z = (p >> 16) & 255;
        img[i].w = (p >> 24) & 255;
    }
}

void writeImage(const string& path, int w, int h, const vector<Pixel>& img) {
    ofstream f(path, ios::binary);
    if (!f) {
        fprintf(stderr, "Failed to open output file: %s\n", path.c_str());
        exit(1);
    }

    f.write((char*)&w, 4);
    f.write((char*)&h, 4);
    for (const auto& p : img) {
        uint32_t v = p.x | (p.y << 8) | (p.z << 16) | (p.w << 24);
        f.write((char*)&v, 4);
    }
}

int main() {
    string inFile, outFile;
    getline(cin, inFile);
    getline(cin, outFile);

    int w = 0, h = 0;
    vector<Pixel> img;
    readImage(inFile, w, h, img);

    const int kx[3][3] = {{-1, 0, 1}, {-1, 0, 1}, {-1, 0, 1}};
    const int ky[3][3] = {{1, 1, 1}, {0, 0, 0}, {-1, -1, -1}};

    vector<Pixel> out((size_t)w * (size_t)h);

    const auto total_start = std::chrono::steady_clock::now();

    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            float gx = 0.0f;
            float gy = 0.0f;
            for (int j = -1; j <= 1; ++j) {
                for (int i = -1; i <= 1; ++i) {
                    const int xx = clampi(x + i, 0, w - 1);
                    const int yy = clampi(y + j, 0, h - 1);
                    const Pixel c = img[(size_t)yy * (size_t)w + (size_t)xx];

                    const float gray = 0.299f * c.x + 0.587f * c.y + 0.114f * c.z;
                    gx += gray * kx[j + 1][i + 1];
                    gy += gray * ky[j + 1][i + 1];
                }
            }

            const float g = sqrtf(gx * gx + gy * gy);
            const unsigned char vv =
                (unsigned char)fminf(255.0f, fmaxf(0.0f, g));
            Pixel r;
            r.x = r.y = r.z = vv;
            r.w = 0;
            out[(size_t)y * (size_t)w + (size_t)x] = r;
        }
    }

    const auto total_end = std::chrono::steady_clock::now();
    const double total_ms =
        std::chrono::duration<double, std::milli>(total_end - total_start)
            .count();

    const char* timing_path = std::getenv("LAB2_TIMING_FILE");
    if (timing_path == nullptr || std::strlen(timing_path) == 0) {
        timing_path = "timings_cpu_lab2.txt";
    }

    FILE* timing_file = std::fopen(timing_path, "a");
    if (timing_file != nullptr) {
        std::fprintf(timing_file, "w=%d h=%d total_ms=%.6f\n", w, h, total_ms);
        std::fclose(timing_file);
    }

    writeImage(outFile, w, h, out);
    return 0;
}
