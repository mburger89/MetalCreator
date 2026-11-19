// B-spline interpolation through values at increasing parameters, shared by the curvature-continuous fillet's strips and Blend
// Surface (NS-4, R10). Header-only and free of OpenCascade. A singular system throws `singular_system`; the caller says why.
#ifndef COCCT_G2_SKIN_HPP
#define COCCT_G2_SKIN_HPP

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace cocct::g2_skin {

/// What the solves here throw when the interpolation matrix is singular.
struct singular_system {};

/// A B-spline through given values: its poles (each as many numbers as a value has), knots, multiplicities and degree.
struct Spline {
    std::vector<std::vector<double>> poles;
    std::vector<double> knots;
    std::vector<int> mults;
    int degree = 0;
};

/// The values at `x` of the `degree + 1` B-spline basis functions of the flat knot vector `flat` that are nonzero on
/// its span `span` (flat[span] <= x < flat[span + 1]): the functions span - degree ... span (The NURBS Book, A2.2).
inline std::vector<double> basis_at(const std::vector<double> &flat, std::size_t span, double x, int degree) {
    const std::size_t p = static_cast<std::size_t>(degree);
    std::vector<double> n(p + 1, 0.0), left(p + 1, 0.0), right(p + 1, 0.0);
    n[0] = 1;
    for (std::size_t j = 1; j <= p; ++j) {
        left[j] = x - flat[span + 1 - j];
        right[j] = flat[span + j] - x;
        double saved = 0;
        for (std::size_t r = 0; r < j; ++r) {
            const double temp = n[r] / (right[r + 1] + left[j - r]);
            n[r] = saved + right[r + 1] * temp;
            saved = left[j - r] * temp;
        }
        n[j] = saved;
    }
    return n;
}

/// Solves `matrix` x = `rhs` (one column per number of a value) in place, by Gaussian elimination with partial
/// pivoting; the solution replaces `rhs`. False when the matrix is singular.
inline bool solve(std::vector<std::vector<double>> &matrix, std::vector<std::vector<double>> &rhs) {
    const std::size_t n = matrix.size();
    for (std::size_t c = 0; c < n; ++c) {
        std::size_t pivot = c;
        for (std::size_t r = c + 1; r < n; ++r) {
            if (std::abs(matrix[r][c]) > std::abs(matrix[pivot][c])) {
                pivot = r;
            }
        }
        if (std::abs(matrix[pivot][c]) < 1e-12) {
            return false;
        }
        std::swap(matrix[c], matrix[pivot]);
        std::swap(rhs[c], rhs[pivot]);
        for (std::size_t r = c + 1; r < n; ++r) {
            const double factor = matrix[r][c] / matrix[c][c];
            if (factor == 0) {
                continue;
            }
            for (std::size_t k = c; k < n; ++k) {
                matrix[r][k] -= factor * matrix[c][k];
            }
            for (std::size_t k = 0; k < rhs[r].size(); ++k) {
                rhs[r][k] -= factor * rhs[c][k];
            }
        }
    }
    for (std::size_t c = n; c-- > 0;) {
        for (std::size_t k = 0; k < rhs[c].size(); ++k) {
            double value = rhs[c][k];
            for (std::size_t r = c + 1; r < n; ++r) {
                value -= matrix[c][r] * rhs[r][k];
            }
            rhs[c][k] = value / matrix[c][c];
        }
    }
    return true;
}

/// The clamped spline of degree min(`degree`, points - 1) through `values` at the increasing parameters `x`, with
/// de Boor's averaged knots (it reproduces every polynomial of its degree, so its error falls as the spacing to the
/// power degree + 1), then raised to `degree` when it had fewer points than that needs (it is one polynomial then).
/// `poles` and `flat` (the flat knot vector) are the result.
inline void open_piece(const std::vector<std::vector<double>> &values, const std::vector<double> &x, int degree,
                std::vector<std::vector<double>> &poles, std::vector<double> &flat) {
    const std::size_t n = values.size();
    const int own = std::min(degree, static_cast<int>(n) - 1);
    const std::size_t p = static_cast<std::size_t>(own);
    flat.assign(p + 1, x.front());
    for (std::size_t j = 1; j + p < n; ++j) {
        double sum = 0;
        for (std::size_t k = j; k < j + p; ++k) {
            sum += x[k];
        }
        flat.push_back(sum / own);
    }
    flat.insert(flat.end(), p + 1, x.back());
    std::vector<std::vector<double>> matrix(n, std::vector<double>(n, 0.0));
    poles = values;
    for (std::size_t j = 0; j < n; ++j) {
        std::size_t span = p;
        while (span + 1 < n && flat[span + 1] <= x[j]) {
            ++span;
        }
        const std::vector<double> basis = basis_at(flat, span, x[j], own);
        for (std::size_t r = 0; r <= p; ++r) {
            matrix[j][span - p + r] = basis[r];
        }
    }
    if (!solve(matrix, poles)) {
        throw singular_system();
    }
    // One polynomial of a lower degree (a piece of fewer points than the degree needs): raised one degree at a time.
    for (int d = own; d < degree; ++d) {
        std::vector<std::vector<double>> raised(static_cast<std::size_t>(d) + 2, poles.front());
        raised.back() = poles.back();
        for (std::size_t i = 1; i <= static_cast<std::size_t>(d); ++i) {
            const double a = static_cast<double>(i) / (d + 1);
            for (std::size_t k = 0; k < poles[i].size(); ++k) {
                raised[i][k] = a * poles[i - 1][k] + (1 - a) * poles[i][k];
            }
        }
        poles = raised;
        flat.insert(flat.begin(), x.front());
        flat.push_back(x.back());
    }
}

/// The spline of `degree` through `values` at the increasing parameters `x`, made of one open piece (open_piece)
/// between each pair of consecutive breaks (`breaks`: indices into x, the ends excluded), joined with a knot of full
/// multiplicity there: the data need not be smooth across a break, and the spline does not smooth them over it.
inline Spline interpolate_open(const std::vector<std::vector<double>> &values, const std::vector<double> &x,
                        const std::vector<std::size_t> &breaks, int degree) {
    std::vector<std::size_t> ends{0};
    for (const std::size_t b : breaks) {
        ends.push_back(b);
    }
    ends.push_back(values.size() - 1);
    Spline spline;
    spline.degree = degree;
    for (std::size_t piece = 0; piece + 1 < ends.size(); ++piece) {
        const std::size_t from = ends[piece], to = ends[piece + 1];
        const std::vector<std::vector<double>> piece_values(values.begin() + static_cast<std::ptrdiff_t>(from),
                                                            values.begin() + static_cast<std::ptrdiff_t>(to) + 1);
        const std::vector<double> piece_x(x.begin() + static_cast<std::ptrdiff_t>(from),
                                          x.begin() + static_cast<std::ptrdiff_t>(to) + 1);
        std::vector<std::vector<double>> poles;
        std::vector<double> flat;
        open_piece(piece_values, piece_x, degree, poles, flat);
        // A piece's first pole is its first value, which is the previous piece's last pole.
        spline.poles.insert(spline.poles.end(), poles.begin() + (piece == 0 ? 0 : 1), poles.end());
        if (piece == 0) {
            spline.knots.push_back(flat.front());
            spline.mults.push_back(degree + 1);
        } else {
            spline.mults.back() = degree;
        }
        for (std::size_t q = static_cast<std::size_t>(degree) + 1; q + 1 < flat.size(); ++q) {
            if (flat[q] == spline.knots.back()) {
                ++spline.mults.back();
            } else {
                spline.knots.push_back(flat[q]);
                spline.mults.push_back(1);
            }
        }
        spline.mults.back() = degree + 1;
    }
    return spline;
}

/// The periodic spline of odd `degree` through `values` at `x` (the last value repeats the first, a period later),
/// with a knot at every value, so it is as smooth across its junction as anywhere. Its poles are in OpenCascade's
/// order for a periodic B-spline with these knots, all of multiplicity 1.
inline Spline interpolate_periodic(const std::vector<std::vector<double>> &values, const std::vector<double> &x, int degree) {
    const int m = static_cast<int>(values.size()) - 1;
    if (m <= degree) {
        throw singular_system();
    }
    const double period = x.back() - x.front();
    // The knots at the values, carried on periodically past both ends: flat[q] is the knot of value q - degree - 1.
    std::vector<double> flat;
    for (int q = -(degree + 1); q <= m + degree + 1; ++q) {
        const int wraps = static_cast<int>(std::floor(static_cast<double>(q) / m));
        flat.push_back(x[static_cast<std::size_t>(q - wraps * m)] + wraps * period);
    }
    const std::size_t size = static_cast<std::size_t>(m);
    std::vector<std::vector<double>> matrix(size, std::vector<double>(size, 0.0));
    std::vector<std::vector<double>> poles(values.begin(), values.end() - 1);
    for (int j = 0; j < m; ++j) {
        const std::size_t span = static_cast<std::size_t>(j + degree + 1);
        const std::vector<double> basis = basis_at(flat, span, x[static_cast<std::size_t>(j)], degree);
        for (int r = 0; r <= degree; ++r) {
            // Basis function span - degree + r of the unrolled knots is the periodic one of index (that - degree - 1).
            const int column = (((j + r - degree) % m) + m) % m;
            matrix[static_cast<std::size_t>(j)][static_cast<std::size_t>(column)] += basis[static_cast<std::size_t>(r)];
        }
    }
    if (!solve(matrix, poles)) {
        throw singular_system();
    }
    Spline spline;
    spline.degree = degree;
    // OpenCascade's first periodic pole is the function that starts `degree` knots before the first knot.
    std::rotate(poles.begin(), poles.begin() + (m - degree), poles.end());
    spline.poles = poles;
    spline.knots = x;
    spline.mults.assign(x.size(), 1);
    return spline;
}

} // namespace cocct::g2_skin

#endif
