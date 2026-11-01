// Small Bezier and linear-algebra helpers for the G2 corner patch (cocct_g2_triangle.hpp). Header-only and free of
// OpenCascade.
#ifndef COCCT_G2_BEZIER_HPP
#define COCCT_G2_BEZIER_HPP

#include "cocct_g2_section.hpp"

#include <array>
#include <cmath>
#include <vector>

namespace cocct::g2 {

/// The polygon of the Bezier segment [t0, t1] of the degree-5 Bezier with control points `p` (works on vectors too).
inline std::array<Vec, 6> bezier_segment(const std::array<Vec, 6> &p, double t0, double t1) {
    auto cut = [](const std::array<Vec, 6> &q, double t, bool keep_left) {
        std::array<std::array<Vec, 6>, 6> level{};
        level[0] = q;
        for (int r = 1; r < 6; ++r) {
            for (int i = 0; i < 6 - r; ++i) {
                level[r][i] = add(scale(level[r - 1][i], 1 - t), scale(level[r - 1][i + 1], t));
            }
        }
        std::array<Vec, 6> out{};
        for (int i = 0; i < 6; ++i) {
            out[i] = keep_left ? level[i][0] : level[5 - i][i];
        }
        return out;
    };
    std::array<Vec, 6> right = t0 > 0 ? cut(p, t0, false) : p;
    if (t1 >= 1) {
        return right;
    }
    return cut(right, (t1 - t0) / (1 - t0), true);
}

/// Control points of the degree-5 Bezier that takes `values[j]` at v = j / 5 (solves the Bernstein collocation).
inline std::array<Vec, 6> bezier_through(const std::array<Vec, 6> &values) {
    double m[6][12];
    for (int j = 0; j < 6; ++j) {
        const double v = j / 5.0;
        for (int i = 0; i < 6; ++i) {
            double binom = 1;
            for (int k = 1; k <= i; ++k) {
                binom = binom * (5 - i + k) / k;
            }
            m[j][i] = binom * std::pow(v, i) * std::pow(1 - v, 5 - i);
        }
        for (int c = 0; c < 3; ++c) {
            m[j][6 + c] = values[j][c];
        }
    }
    for (int col = 0; col < 6; ++col) {
        int pivot = col;
        for (int r = col + 1; r < 6; ++r) {
            if (std::abs(m[r][col]) > std::abs(m[pivot][col])) {
                pivot = r;
            }
        }
        for (int c = 0; c < 9 + 3; ++c) {
            std::swap(m[col][c], m[pivot][c]);
        }
        for (int r = 0; r < 6; ++r) {
            if (r == col) {
                continue;
            }
            const double f = m[r][col] / m[col][col];
            for (int c = col; c < 9 + 3; ++c) {
                m[r][c] -= f * m[col][c];
            }
        }
    }
    std::array<Vec, 6> out{};
    for (int i = 0; i < 6; ++i) {
        for (int c = 0; c < 3; ++c) {
            out[i][c] = m[i][6 + c] / m[i][i];
        }
    }
    return out;
}

/// Solves the dense system `a x = b` (n x n, row major) by Gaussian elimination with partial pivoting.
inline bool solve_dense(std::vector<double> &a, std::vector<double> &b, int n) {
    for (int col = 0; col < n; ++col) {
        int pivot = col;
        for (int r = col + 1; r < n; ++r) {
            if (std::abs(a[r * n + col]) > std::abs(a[pivot * n + col])) {
                pivot = r;
            }
        }
        if (std::abs(a[pivot * n + col]) < 1e-14) {
            return false;
        }
        if (pivot != col) {
            for (int c = 0; c < n; ++c) {
                std::swap(a[col * n + c], a[pivot * n + c]);
            }
            std::swap(b[col], b[pivot]);
        }
        for (int r = col + 1; r < n; ++r) {
            const double f = a[r * n + col] / a[col * n + col];
            if (f == 0) {
                continue;
            }
            for (int c = col; c < n; ++c) {
                a[r * n + c] -= f * a[col * n + c];
            }
            b[r] -= f * b[col];
        }
    }
    for (int r = n - 1; r >= 0; --r) {
        double sum = b[r];
        for (int c = r + 1; c < n; ++c) {
            sum -= a[r * n + c] * b[c];
        }
        b[r] = sum / a[r * n + r];
    }
    return true;
}

} // namespace cocct::g2

#endif
