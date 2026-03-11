#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace std;

using Matrix = vector<double>;
using Vector = vector<double>;

const double EPS = 1e-12;

static inline int id(int row, int col, int cols) { return row * cols + col; }

void readInput(int& n, Matrix& a, Vector& b) {
    cin >> n;
    if (!cin || n <= 0) {
        throw runtime_error("Не удалось прочитать размер матрицы");
    }
    a.resize(n * n);
    b.resize(n);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            cin >> a[id(i, j, n)];
            if (!cin) throw runtime_error("Ошибка чтения матрицы A");
        }
    }
    for (int i = 0; i < n; ++i) {
        cin >> b[i];
        if (!cin) throw runtime_error("Ошибка чтения вектора b");
    }
}

Matrix makeAugmented(int n, const Matrix& a, const Vector& b) {
    Matrix m(n * (n + 1));
    int cols = n + 1;
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) m[id(i, j, cols)] = a[id(i, j, n)];
        m[id(i, n, cols)] = b[i];
    }
    return m;
}

void swapRows(Matrix& m, int cols, int r1, int r2) {
    if (r1 == r2) return;
    for (int c = 0; c < cols; ++c) {
        std::swap(m[id(r1, c, cols)], m[id(r2, c, cols)]);
    }
}

void forwardElimination(Matrix& m, int n) {
    int cols = n + 1;
    for (int k = 0; k < n; ++k) {
        int pivotRow = k;
        double best = std::fabs(m[id(k, k, cols)]);
        for (int r = k + 1; r < n; ++r) {
            double v = std::fabs(m[id(r, k, cols)]);
            if (v > best) {
                best = v;
                pivotRow = r;
            }
        }
        if (best < EPS) {
            throw runtime_error("Система не имеет единственного решения");
        }
        swapRows(m, cols, k, pivotRow);

        const double pivot = m[id(k, k, cols)];
        for (int r = k + 1; r < n; ++r) {
            double factor = m[id(r, k, cols)] / pivot;
            m[id(r, k, cols)] = 0.0;
            for (int c = k + 1; c < cols; ++c) {
                m[id(r, c, cols)] -= factor * m[id(k, c, cols)];
            }
        }
    }
}

Vector backSubstitution(const Matrix& m, int n) {
    int cols = n + 1;
    Vector x(n, 0.0);
    for (int i = n - 1; i >= 0; --i) {
        double sum = m[id(i, n, cols)];
        for (int j = i + 1; j < n; ++j) sum -= m[id(i, j, cols)] * x[j];
        double diag = m[id(i, i, cols)];
        if (std::fabs(diag) < EPS) {
            throw runtime_error("Ноль на диагонали при обратном ходе");
        }
        x[i] = sum / diag;
    }
    return x;
}

void appendTiming(int n, double totalMs) {
    const char* path = std::getenv("LAB4_TIMING_FILE");
    if (!path || !*path) path = "timings_cpu_lab4.txt";
    FILE* f = std::fopen(path, "a");
    if (!f) return;
    std::fprintf(f, "n=%d total_ms=%.6f\n", n, totalMs);
    std::fclose(f);
}

int main() {
    try {
        ios::sync_with_stdio(false);
        cin.tie(nullptr);

        int n = 0;
        Matrix a;
        Vector b;
        readInput(n, a, b);
        Matrix m = makeAugmented(n, a, b);

        const auto t0 = std::chrono::steady_clock::now();
        forwardElimination(m, n);
        Vector x = backSubstitution(m, n);
        const auto t1 = std::chrono::steady_clock::now();

        appendTiming(
            n, std::chrono::duration<double, std::milli>(t1 - t0).count());

        cout << scientific << setprecision(10);
        for (int i = 0; i < n; ++i) {
            if (i) cout << ' ';
            cout << x[i];
        }
        cout << '\n';
    } catch (const exception& e) {
        cerr << "[ERROR] " << e.what() << '\n';
        return 1;
    }
    return 0;
}
