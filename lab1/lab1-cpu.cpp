#include <cstdio>
#include <vector>
#include <chrono>
#include <cstdlib>
#include <cstring>

int main() {
    int n;
    if (scanf("%d", &n) != 1) {
        return 1;
    }
    if (n <= 0) {
        return 0;
    }

    std::vector<double> a(n), b(n), c(n);

    for (int i = 0; i < n; ++i) {
        if (scanf("%lf", &a[i]) != 1) {
            return 1;
        }
    }
    for (int i = 0; i < n; ++i) {
        if (scanf("%lf", &b[i]) != 1) {
            return 1;
        }
    }

    const auto total_start = std::chrono::steady_clock::now();

    for (int i = 0; i < n; ++i) {
        c[i] = a[i] * b[i];
    }

    const auto total_end = std::chrono::steady_clock::now();
    const double total_ms = std::chrono::duration<double, std::milli>(total_end - total_start).count();

    const char *timing_path = std::getenv("LAB1_TIMING_FILE");
    if (timing_path == nullptr || std::strlen(timing_path) == 0) {
        timing_path = "timings_cpu.txt";
    }

    FILE *timing_file = std::fopen(timing_path, "a");
    if (timing_file != nullptr) {
        std::fprintf(timing_file, "n=%d total_ms=%.6f\n", n, total_ms);
        std::fclose(timing_file);
    }

    for (int i = 0; i < n; ++i) {
        printf("%.10e%c", c[i], (i == n - 1) ? '\n' : ' ');
    }

    return 0;
}
