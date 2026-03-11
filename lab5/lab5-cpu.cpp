#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using Byte = unsigned char;
using ByteArray = std::vector<Byte>;

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

void debug(const std::string& text) {
    if (isDebugEnabled()) {
        std::cerr << "[DEBUG] " << text << '\n';
    }
}

struct InputData {
    int n = 0;
    ByteArray values;
};

InputData readInput() {
    debug("Читаем бинарный вход из stdin");

    InputData data;

    if (fread(&data.n, sizeof(int), 1, stdin) != 1) {
        throw std::runtime_error("Не удалось прочитать n");
    }

    if (data.n < 0) {
        throw std::runtime_error("n не может быть отрицательным");
    }

    data.values.resize(static_cast<size_t>(data.n));

    if (data.n > 0) {
        size_t readCount = fread(data.values.data(), sizeof(Byte),
                                 static_cast<size_t>(data.n), stdin);
        if (readCount != static_cast<size_t>(data.n)) {
            throw std::runtime_error("Не удалось прочитать массив значений");
        }
    }

    return data;
}

void writeOutput(const ByteArray& values) {
    if (!values.empty()) {
        size_t written =
            fwrite(values.data(), sizeof(Byte), values.size(), stdout);
        if (written != values.size()) {
            throw std::runtime_error("Не удалось записать выходные данные");
        }
    }
    fflush(stdout);
}

void appendCpuTiming(int n, double totalMs) {
    const char* path = std::getenv("LAB5_CPU_TIMING_FILE");
    if (!path || !*path) {
        path = "timings_cpu_lab5.txt";
    }

    FILE* f = std::fopen(path, "a");
    if (!f) {
        return;
    }

    std::fprintf(f, "n=%d total_ms=%.6f\n", n, totalMs);
    std::fclose(f);
}

ByteArray countingSort(const ByteArray& input) {
    std::array<unsigned int, 256> histogram{};

    for (Byte v : input) {
        ++histogram[v];
    }

    ByteArray output(input.size());
    size_t pos = 0;

    for (int value = 0; value < 256; ++value) {
        unsigned int count = histogram[static_cast<size_t>(value)];
        for (unsigned int i = 0; i < count; ++i) {
            output[pos++] = static_cast<Byte>(value);
        }
    }

    return output;
}

int main() {
    try {
        std::ios::sync_with_stdio(false);
        std::cin.tie(nullptr);

        InputData input = readInput();
        if (input.n == 0) {
            return 0;
        }

        const auto start = std::chrono::steady_clock::now();
        ByteArray sorted = countingSort(input.values);
        const auto end = std::chrono::steady_clock::now();

        const double totalMs =
            std::chrono::duration<double, std::milli>(end - start).count();
        appendCpuTiming(input.n, totalMs);

        writeOutput(sorted);
    } catch (const std::exception& e) {
        std::cerr << "[ERROR] " << e.what() << '\n';
        return 1;
    }

    return 0;
}
