// SPIKE (G-b Task 2d-2): one three-sided Bezier patch for the hole three fillet strips leave at a corner. Header-only and
// free of OpenCascade.
//
// The patch is a triangular Bezier patch of degree n over barycentric coordinates (i, j, k) of the hole's corners
// V0, V1, V2: control points b[i][j] with k = n - i - j. Its three sides are the strips' quintic end curves. Along side
// sigma (V_sigma to V_sigma+1, parameter s) the three layers of control points next to it carry the strip's G2 data:
// with w the barycentric weight of the opposite corner, P(s, w) = sum_k C(n, k) w^k (1 - w)^(n - k) L_k(s), so
//     P(s, 0) = L_0,  P_w = n (L_1 - L_0),  P_ww = n (n - 1) (L_0 - 2 L_1 + L_2)
// and the layers follow from the end curve C, the cross-boundary derivative F and the second one G:
//     L_1 = C + F / n,   L_2 = C + 2 F / n + G / (n (n - 1)).
// F = lambda(s) * (the strip's first cross derivative) and G = lambda(s)^2 * (its second): the same surface, its across
// parameter scaled by lambda(s), which is chosen at both ends so that F is the neighbouring side's tangent there.
// The layers need n >= 9 for exactness (L_2 is of degree 7).
//
// At each corner the layers of the two sides share a 3 x 3 block of control points. The two sides may disagree on them;
// `block_mismatch` is the largest disagreement (the caller decides whether that is a failure), and the block keeps
// the first side's value. The interior (every index >= 3) is the fairest net: the minimum of the sum of squared second
// differences along the three directions, a linear solve.
//
// `to_tensor` writes the same polynomial as a tensor-product Bezier of degree (n, n) over the square (x, y), with
// x = j / n weights: P(x, y) = sum b_ijk * n! / (i! j! k!) * (1 - x - y)^i x^j y^k, exact.
#ifndef COCCT_G2_TRIANGLE_HPP
#define COCCT_G2_TRIANGLE_HPP

#include "cocct_g2_corner.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <vector>

namespace cocct::g2 {

struct TriangleSide {
    std::array<Vec, 6> poles{};  // the end curve, oriented V_sigma -> V_sigma+1
    std::array<Vec, 6> cross1{}; // its first and second cross-boundary derivatives (into the hole), oriented alike
    std::array<Vec, 6> cross2{};
    double lambda0 = 1, lambda1 = 1; // the across scale at both ends
};

inline Vec bezier_value(const std::array<Vec, 6> &p, double t) {
    Vec out{0, 0, 0};
    for (int i = 0; i < 6; ++i) {
        double binom = 1;
        for (int k = 1; k <= i; ++k) {
            binom = binom * (5 - i + k) / k;
        }
        out = add(out, scale(p[i], binom * std::pow(t, i) * std::pow(1 - t, 5 - i)));
    }
    return out;
}

/// The derivative of the quintic at t (a degree-4 Bezier of the differences).
inline Vec bezier_derivative(const std::array<Vec, 6> &p, double t) {
    Vec out{0, 0, 0};
    for (int i = 0; i < 5; ++i) {
        double binom = 1;
        for (int k = 1; k <= i; ++k) {
            binom = binom * (4 - i + k) / k;
        }
        out = add(out, scale(sub(p[i + 1], p[i]), 5 * binom * std::pow(t, i) * std::pow(1 - t, 4 - i)));
    }
    return out;
}

inline Vec bezier_second_derivative(const std::array<Vec, 6> &p, double t) {
    Vec out{0, 0, 0};
    for (int i = 0; i < 4; ++i) {
        double binom = 1;
        for (int k = 1; k <= i; ++k) {
            binom = binom * (3 - i + k) / k;
        }
        const Vec dd = add(sub(p[i + 2], scale(p[i + 1], 2)), p[i]);
        out = add(out, scale(dd, 20 * binom * std::pow(t, i) * std::pow(1 - t, 3 - i)));
    }
    return out;
}

/// The inverse of the degree-d Bernstein collocation matrix at t = m / d (cached per degree: the solver reuses it).
inline const std::vector<double> &collocation_inverse(int d) {
    static thread_local std::vector<std::vector<double>> cache;
    if (static_cast<int>(cache.size()) <= d) {
        cache.resize(d + 1);
    }
    std::vector<double> &inverse = cache[d];
    if (!inverse.empty()) {
        return inverse;
    }
    const int size = d + 1;
    std::vector<double> a(static_cast<std::size_t>(size) * size);
    for (int m = 0; m < size; ++m) {
        const double t = static_cast<double>(m) / d;
        double binom = 1;
        for (int i = 0; i < size; ++i) {
            if (i > 0) {
                binom = binom * (d - i + 1) / i;
            }
            a[static_cast<std::size_t>(m) * size + i] = binom * std::pow(t, i) * std::pow(1 - t, d - i);
        }
    }
    inverse.assign(static_cast<std::size_t>(size) * size, 0.0);
    for (int column = 0; column < size; ++column) {
        std::vector<double> matrix = a;
        std::vector<double> rhs(size, 0.0);
        rhs[column] = 1;
        solve_dense(matrix, rhs, size);
        for (int row = 0; row < size; ++row) {
            inverse[static_cast<std::size_t>(row) * size + column] = rhs[row];
        }
    }
    return inverse;
}

/// The control points of the degree-d Bezier that takes `values[m]` at t = m / d.
inline std::vector<Vec> bernstein_through(const std::vector<Vec> &values) {
    const int d = static_cast<int>(values.size()) - 1;
    const int size = d + 1;
    const std::vector<double> &inverse = collocation_inverse(d);
    std::vector<Vec> out(size, Vec{0, 0, 0});
    for (int i = 0; i < size; ++i) {
        for (int m = 0; m < size; ++m) {
            out[i] = add(out[i], scale(values[m], inverse[static_cast<std::size_t>(i) * size + m]));
        }
    }
    return out;
}

struct TriangleNet {
    int degree = 0;
    std::vector<Vec> b; // (n + 1) x (n + 1): b[i * (n + 1) + j], k = n - i - j
    Vec &at(int i, int j) { return b[static_cast<std::size_t>(i) * (degree + 1) + j]; }
    const Vec &at(int i, int j) const { return b[static_cast<std::size_t>(i) * (degree + 1) + j]; }
};

/// The across scale of side `sigma` at both ends: its first cross derivative there must be the neighbouring side's
/// tangent (reported through `direction_cosine`, the worst cosine between them).
inline bool across_scales(TriangleSide sides[3], double &direction_cosine) {
    direction_cosine = 1;
    for (int s = 0; s < 3; ++s) {
        const TriangleSide &prev = sides[(s + 2) % 3];
        const TriangleSide &next = sides[(s + 1) % 3];
        const Vec leg0 = scale(bezier_derivative(prev.poles, 1.0), -1.0); // away from V_s along the previous side
        const Vec leg1 = bezier_derivative(next.poles, 0.0);              // away from V_s+1 along the next side
        const Vec f0 = sides[s].cross1[0], f1 = sides[s].cross1[5];
        if (norm(f0) < 1e-12 || norm(f1) < 1e-12) {
            return false;
        }
        direction_cosine = std::min({direction_cosine, dot(f0, leg0) / (norm(f0) * norm(leg0)), dot(f1, leg1) / (norm(f1) * norm(leg1))});
        sides[s].lambda0 = norm(leg0) / norm(f0);
        sides[s].lambda1 = norm(leg1) / norm(f1);
    }
    return true;
}

/// Value of the quintic with the given value, first and second derivative at 0 and at 1.
inline double hermite5(const double at0[3], const double at1[3], double s) {
    const double s2 = s * s, s3 = s2 * s, s4 = s3 * s, s5 = s4 * s;
    const double h00 = 1 - 10 * s3 + 15 * s4 - 6 * s5, h10 = s - 6 * s3 + 8 * s4 - 3 * s5;
    const double h20 = 0.5 * s2 - 1.5 * s3 + 1.5 * s4 - 0.5 * s5;
    const double h01 = 10 * s3 - 15 * s4 + 6 * s5, h11 = -4 * s3 + 7 * s4 - 3 * s5, h21 = 0.5 * s3 - s4 + 0.5 * s5;
    return at0[0] * h00 + at0[1] * h10 + at0[2] * h20 + at1[0] * h01 + at1[1] * h11 + at1[2] * h21;
}

/// How a side's across parametrization may be reshaped without changing the surface: the cross-boundary derivative
/// is F = lambda f1 + m C' and the second G = lambda^2 f2 + 2 lambda m f1' + m^2 C'' + nu f1 + q C' (the surface
/// S(u, v) read at u = lambda w, v = s + m w, with nu, q the tangential second-order freedoms). Each of lambda, m, nu, q
/// is a quintic given by its value and first two derivatives at both ends; the values are fixed (lambda by the
/// neighbours' tangents, the others zero), the derivatives are the unknowns: `p[end][0..7]` = lambda', lambda'',
/// m', m'', nu', nu'', q', q'' at that end.
struct SideFreedom {
    double p[2][8] = {{0, 0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0, 0, 0}};
};

/// The three layers (0, 1, 2) of control points of one side, as the degree-(n - layer) polygons.
inline void side_layers(const TriangleSide &side, const SideFreedom &free, int n, std::vector<Vec> layers[3]) {
    for (int layer = 0; layer < 3; ++layer) {
        const int d = n - layer;
        std::vector<Vec> samples(d + 1);
        for (int k = 0; k <= d; ++k) {
            const double t = static_cast<double>(k) / d;
            const double l0[3] = {side.lambda0, free.p[0][0], free.p[0][1]}, l1[3] = {side.lambda1, free.p[1][0], free.p[1][1]};
            const double m0[3] = {0, free.p[0][2], free.p[0][3]}, m1[3] = {0, free.p[1][2], free.p[1][3]};
            const double n0[3] = {0, free.p[0][4], free.p[0][5]}, n1[3] = {0, free.p[1][4], free.p[1][5]};
            const double q0[3] = {0, free.p[0][6], free.p[0][7]}, q1[3] = {0, free.p[1][6], free.p[1][7]};
            const double lambda = hermite5(l0, l1, t), m = hermite5(m0, m1, t), nu = hermite5(n0, n1, t), q = hermite5(q0, q1, t);
            const Vec position = bezier_value(side.poles, t);
            const Vec cp = bezier_derivative(side.poles, t), cpp = bezier_second_derivative(side.poles, t);
            const Vec f1 = bezier_value(side.cross1, t), f1p = bezier_derivative(side.cross1, t), f2 = bezier_value(side.cross2, t);
            const Vec f = add(scale(f1, lambda), scale(cp, m));
            Vec g = scale(f2, lambda * lambda);
            g = add(g, scale(f1p, 2 * lambda * m));
            g = add(g, scale(cpp, m * m));
            g = add(g, add(scale(f1, nu), scale(cp, q)));
            Vec value = position;
            if (layer == 1) {
                value = add(position, scale(f, 1.0 / n));
            } else if (layer == 2) {
                value = add(add(position, scale(f, 2.0 / n)), scale(g, 1.0 / (static_cast<double>(n) * (n - 1))));
            }
            samples[k] = value;
        }
        layers[layer] = bernstein_through(samples);
    }
}

/// Scatters the layers of the three sides into `net`; the slots two sides both claim contribute their difference to
/// `conflicts` (in a fixed order). Returns the largest.
inline double scatter_layers(const std::vector<Vec> layers[3][3], int n, TriangleNet &net, std::vector<double> *conflicts) {
    net.degree = n;
    net.b.assign(static_cast<std::size_t>(n + 1) * (n + 1), Vec{0, 0, 0});
    std::vector<bool> set(net.b.size(), false);
    double worst = 0;
    for (int s = 0; s < 3; ++s) {
        const int a = s, b = (s + 1) % 3, c = (s + 2) % 3;
        for (int layer = 0; layer < 3; ++layer) {
            const int d = n - layer;
            for (int m = 0; m <= d; ++m) {
                int idx[3];
                idx[c] = layer;
                idx[b] = m;
                idx[a] = n - layer - m;
                const std::size_t slot = static_cast<std::size_t>(idx[0]) * (n + 1) + idx[1];
                const Vec &value = layers[s][layer][m];
                if (set[slot]) {
                    const Vec diff = sub(net.b[slot], value);
                    worst = std::max(worst, norm(diff));
                    if (conflicts) {
                        for (int q = 0; q < 3; ++q) {
                            conflicts->push_back(diff[q]);
                        }
                    }
                } else {
                    net.b[slot] = value;
                    set[slot] = true;
                }
            }
        }
    }
    return worst;
}

/// Fills the layers of the three sides and the fair interior. The corner blocks are made to agree by reshaping each
/// side's across parametrization (SideFreedom, a Levenberg-Marquardt solve over its end derivatives); `raw_mismatch` is
/// their disagreement before that, `block_mismatch` after.
inline bool build_triangle(const TriangleSide sides[3], int n, TriangleNet &net, double &block_mismatch, double &raw_mismatch,
                           bool reshape = true, int *iterations = nullptr, double *largest_freedom = nullptr) {
    SideFreedom freedom[3];
    std::vector<Vec> layers[3][3];
    auto load_side = [&](int s, const std::vector<double> &x) {
        for (int e = 0; e < 2; ++e) {
            for (int q = 0; q < 8; ++q) {
                freedom[s].p[e][q] = x[static_cast<std::size_t>(s * 16 + e * 8 + q)];
            }
        }
        side_layers(sides[s], freedom[s], n, layers[s]);
    };
    auto evaluate_all = [&](const std::vector<double> &x, std::vector<double> &r, TriangleNet &out) {
        for (int s = 0; s < 3; ++s) {
            load_side(s, x);
        }
        r.clear();
        return scatter_layers(layers, n, out, &r);
    };
    // The residual with one side's layers recomputed (the others are as the last evaluate_all left them).
    auto evaluate_side = [&](int s, const std::vector<double> &x, std::vector<double> &r, TriangleNet &out) {
        load_side(s, x);
        r.clear();
        return scatter_layers(layers, n, out, &r);
    };
    std::vector<double> x(48, 0.0), r;
    raw_mismatch = evaluate_all(x, r, net);
    int it = 0;
    if (reshape && raw_mismatch > 1e-10) {
        double mu = 1e-3;
        double cost = 0;
        for (double v : r) {
            cost += v * v;
        }
        for (; it < 60 && cost > 1e-24; ++it) {
            // Jacobian by central differences.
            const std::size_t m = r.size();
            std::vector<double> jac(m * 48);
            for (int q = 0; q < 48; ++q) {
                std::vector<double> xp = x, xm = x, rp, rm;
                const double h = 1e-5;
                xp[q] += h;
                xm[q] -= h;
                TriangleNet scratch;
                evaluate_all(x, rp, scratch); // the layers of every side at x
                evaluate_side(q / 16, xp, rp, scratch);
                evaluate_side(q / 16, xm, rm, scratch);
                for (std::size_t k = 0; k < m; ++k) {
                    jac[k * 48 + q] = (rp[k] - rm[k]) / (2 * h);
                }
            }
            bool improved = false;
            for (int attempt = 0; attempt < 12 && !improved; ++attempt) {
                std::vector<double> normal(48 * 48, 0.0), rhs(48, 0.0);
                for (std::size_t k = 0; k < m; ++k) {
                    for (int a = 0; a < 48; ++a) {
                        rhs[a] -= jac[k * 48 + a] * r[k];
                        for (int b = 0; b < 48; ++b) {
                            normal[a * 48 + b] += jac[k * 48 + a] * jac[k * 48 + b];
                        }
                    }
                }
                for (int a = 0; a < 48; ++a) {
                    normal[a * 48 + a] += mu;
                }
                if (!solve_dense(normal, rhs, 48)) {
                    mu *= 10;
                    continue;
                }
                std::vector<double> trial = x, rt;
                for (int a = 0; a < 48; ++a) {
                    trial[a] += rhs[a];
                }
                TriangleNet scratch;
                evaluate_all(trial, rt, scratch);
                double trial_cost = 0;
                for (double v : rt) {
                    trial_cost += v * v;
                }
                if (trial_cost < cost) {
                    x = trial;
                    r = rt;
                    cost = trial_cost;
                    mu = std::max(mu / 10, 1e-12);
                    improved = true;
                } else {
                    mu *= 10;
                }
            }
            if (!improved) {
                break;
            }
        }
    }
    block_mismatch = evaluate_all(x, r, net);
    if (iterations) {
        *iterations = it;
    }
    if (largest_freedom) {
        double big = 0;
        for (double v : x) {
            big = std::max(big, std::abs(v));
        }
        *largest_freedom = big;
    }
    // The interior: every index at least 3. Minimise the squared second differences of the net along the three
    // directions (i-j, j-k and k-i), the discrete thin plate.
    std::vector<int> slot_of(net.b.size(), -1);
    std::vector<std::pair<int, int>> unknown;
    for (int i = 3; i <= n; ++i) {
        for (int j = 3; i + j <= n - 3; ++j) {
            slot_of[static_cast<std::size_t>(i) * (n + 1) + j] = static_cast<int>(unknown.size());
            unknown.push_back({i, j});
        }
    }
    const int count = static_cast<int>(unknown.size());
    if (count == 0) {
        return true;
    }
    std::vector<double> hessian(static_cast<std::size_t>(count) * count, 0.0);
    std::vector<Vec> gradient(count, Vec{0, 0, 0});
    // Directions as steps in (i, j): (1, -1), (0, 1)... the three edge directions of the triangular lattice.
    const int steps[3][2] = {{1, 0}, {0, 1}, {1, -1}};
    for (int i = 0; i <= n; ++i) {
        for (int j = 0; i + j <= n; ++j) {
            for (const auto &step : steps) {
                const int i1 = i + step[0], j1 = j + step[1], i2 = i + 2 * step[0], j2 = j + 2 * step[1];
                if (i2 < 0 || j2 < 0 || j1 < 0 || i1 + j1 > n || i2 + j2 > n) {
                    continue;
                }
                const int ids[3][2] = {{i, j}, {i1, j1}, {i2, j2}};
                const double w[3] = {1, -2, 1};
                Vec fixed{0, 0, 0};
                std::vector<std::pair<int, double>> vars;
                for (int q = 0; q < 3; ++q) {
                    const std::size_t slot = static_cast<std::size_t>(ids[q][0]) * (n + 1) + ids[q][1];
                    if (slot_of[slot] >= 0) {
                        vars.push_back({slot_of[slot], w[q]});
                    } else {
                        fixed = add(fixed, scale(net.b[slot], w[q]));
                    }
                }
                for (const auto &[u, wu] : vars) {
                    gradient[u] = add(gradient[u], scale(fixed, wu));
                    for (const auto &[v, wv] : vars) {
                        hessian[static_cast<std::size_t>(u) * count + v] += wu * wv;
                    }
                }
            }
        }
    }
    for (int u = 0; u < count; ++u) {
        hessian[static_cast<std::size_t>(u) * count + u] += 1e-12;
    }
    for (int c = 0; c < 3; ++c) {
        std::vector<double> matrix = hessian;
        std::vector<double> rhs(count);
        for (int u = 0; u < count; ++u) {
            rhs[u] = -gradient[u][c];
        }
        if (!solve_dense(matrix, rhs, count)) {
            return false;
        }
        for (int u = 0; u < count; ++u) {
            net.at(unknown[u].first, unknown[u].second)[c] = rhs[u];
        }
    }
    return true;
}

/// The same polynomial as a tensor-product Bezier of degree (n, n): `out[a][b]` multiplies B_a(x) B_b(y).
inline std::vector<Vec> to_tensor(const TriangleNet &net) {
    const int n = net.degree;
    auto binomial = [](int top, int bottom) {
        double r = 1;
        for (int k = 1; k <= bottom; ++k) {
            r = r * (top - bottom + k) / k;
        }
        return r;
    };
    // Monomial coefficients c[p][q] of x^p y^q.
    std::vector<Vec> mono(static_cast<std::size_t>(n + 1) * (n + 1), Vec{0, 0, 0});
    for (int i = 0; i <= n; ++i) {
        for (int j = 0; i + j <= n; ++j) {
            const int k = n - i - j;
            // n!/(i!j!k!) * (1-x-y)^i x^j y^k
            const double multinomial = binomial(n, i) * binomial(n - i, j);
            for (int e = 0; e <= i; ++e) { // (1 - x - y)^i = sum_e C(i,e) (-1)^e (x + y)^e
                for (int f = 0; f <= e; ++f) { // (x + y)^e = sum_f C(e,f) x^f y^(e-f)
                    const double coefficient = multinomial * binomial(i, e) * ((e % 2) ? -1.0 : 1.0) * binomial(e, f);
                    const int p = j + f, q = k + e - f;
                    mono[static_cast<std::size_t>(p) * (n + 1) + q] = add(mono[static_cast<std::size_t>(p) * (n + 1) + q], scale(net.at(i, j), coefficient));
                }
            }
        }
    }
    std::vector<Vec> out(static_cast<std::size_t>(n + 1) * (n + 1), Vec{0, 0, 0});
    for (int a = 0; a <= n; ++a) {
        for (int b = 0; b <= n; ++b) {
            Vec sum{0, 0, 0};
            for (int p = 0; p <= a; ++p) {
                for (int q = 0; q <= b; ++q) {
                    const double factor = binomial(a, p) * binomial(b, q) / (binomial(n, p) * binomial(n, q));
                    sum = add(sum, scale(mono[static_cast<std::size_t>(p) * (n + 1) + q], factor));
                }
            }
            out[static_cast<std::size_t>(a) * (n + 1) + b] = sum;
        }
    }
    return out;
}

} // namespace cocct::g2

#endif
