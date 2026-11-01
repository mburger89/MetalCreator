// G-b: one three-sided Bezier patch for the hole three fillet strips leave at a corner. Header-only and
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
// The layers are built exactly in Bernstein form (products and degree elevation, no sampling): L_0 is of degree 5, L_1
// of degree 10 and L_2 of degree 15 (F is a quintic times a quintic, G a product of three), so n = 17 is the least degree
// that holds all of them, and `kTriangleDegree` is that.
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

#include "cocct_g2_bezier.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <vector>

namespace cocct::g2 {

constexpr int kTriangleDegree = 17;

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

/// The interior: every index at least 3. Minimises the squared second differences of the net along the three
/// directions (i-j, j-k and k-i), the discrete thin plate: a linear solve.
inline bool fair_interior(TriangleNet &net) {
    const int n = net.degree;
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


using Scalar = std::vector<double>; // a polynomial in Bernstein form
using Curve = std::vector<Vec>;     // a vector polynomial in Bernstein form

inline double binomial(int top, int bottom) {
    if (bottom < 0 || bottom > top) {
        return 0;
    }
    double r = 1;
    for (int k = 1; k <= bottom; ++k) {
        r = r * (top - bottom + k) / k;
    }
    return r;
}

inline Curve to_curve(const std::array<Vec, 6> &p) { return Curve(p.begin(), p.end()); }

/// The same polynomial written in degree `to` (>= its own).
template <typename T, typename Ops>
std::vector<T> elevate_with(const std::vector<T> &c, int to, const Ops &ops) {
    const int d = static_cast<int>(c.size()) - 1;
    const int extra = to - d;
    std::vector<T> out(static_cast<std::size_t>(to) + 1, ops.zero());
    for (int k = 0; k <= to; ++k) {
        for (int i = std::max(0, k - extra); i <= std::min(d, k); ++i) {
            out[k] = ops.add(out[k], ops.scale(c[i], binomial(d, i) * binomial(extra, k - i) / binomial(to, k)));
        }
    }
    return out;
}

struct ScalarOps {
    double zero() const { return 0; }
    double add(double a, double b) const { return a + b; }
    double scale(double a, double s) const { return a * s; }
};

struct VecOps {
    Vec zero() const { return {0, 0, 0}; }
    Vec add(const Vec &a, const Vec &b) const { return g2::add(a, b); }
    Vec scale(const Vec &a, double s) const { return g2::scale(a, s); }
};

inline Scalar elevate(const Scalar &c, int to) { return elevate_with(c, to, ScalarOps{}); }
inline Curve elevate(const Curve &c, int to) { return elevate_with(c, to, VecOps{}); }

/// The product of a scalar and a vector polynomial (degrees add).
inline Curve multiply(const Scalar &a, const Curve &b) {
    const int da = static_cast<int>(a.size()) - 1, db = static_cast<int>(b.size()) - 1;
    Curve out(static_cast<std::size_t>(da + db) + 1, Vec{0, 0, 0});
    for (int k = 0; k <= da + db; ++k) {
        for (int i = std::max(0, k - db); i <= std::min(da, k); ++i) {
            out[k] = add(out[k], scale(b[k - i], a[i] * binomial(da, i) * binomial(db, k - i) / binomial(da + db, k)));
        }
    }
    return out;
}

inline Scalar multiply(const Scalar &a, const Scalar &b) {
    const int da = static_cast<int>(a.size()) - 1, db = static_cast<int>(b.size()) - 1;
    Scalar out(static_cast<std::size_t>(da + db) + 1, 0.0);
    for (int k = 0; k <= da + db; ++k) {
        for (int i = std::max(0, k - db); i <= std::min(da, k); ++i) {
            out[k] += a[i] * b[k - i] * binomial(da, i) * binomial(db, k - i) / binomial(da + db, k);
        }
    }
    return out;
}

/// The derivative: a polynomial of one degree less.
inline Curve derivative(const Curve &c) {
    const int d = static_cast<int>(c.size()) - 1;
    Curve out(static_cast<std::size_t>(d), Vec{0, 0, 0});
    for (int i = 0; i < d; ++i) {
        out[i] = scale(sub(c[i + 1], c[i]), d);
    }
    return out;
}

/// `sum coefficient_i * curve_i` in degree `to`.
inline Curve combine(const std::vector<std::pair<double, const Curve *>> &terms, int to) {
    Curve out(static_cast<std::size_t>(to) + 1, Vec{0, 0, 0});
    for (const auto &[coefficient, curve] : terms) {
        const Curve raised = elevate(*curve, to);
        for (int k = 0; k <= to; ++k) {
            out[k] = add(out[k], scale(raised[k], coefficient));
        }
    }
    return out;
}

inline double value_at(const Scalar &c, double t) {
    const int d = static_cast<int>(c.size()) - 1;
    double sum = 0;
    for (int i = 0; i <= d; ++i) {
        sum += c[i] * binomial(d, i) * std::pow(t, i) * std::pow(1 - t, d - i);
    }
    return sum;
}

/// The quintic with the given value, first and second derivative at 0 and at 1, in Bernstein form.
inline Scalar hermite_poles(const double at0[3], const double at1[3]) {
    Scalar p(6);
    p[0] = at0[0];
    p[1] = p[0] + at0[1] / 5;
    p[2] = 2 * p[1] - p[0] + at0[2] / 20;
    p[5] = at1[0];
    p[4] = p[5] - at1[1] / 5;
    p[3] = 2 * p[4] - p[5] + at1[2] / 20;
    return p;
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

struct SideScalars {
    Scalar lambda, m, nu, q;
};

inline SideScalars side_scalars(const TriangleSide &side, const SideFreedom &free) {
    auto make = [&](double value0, double value1, int slot) {
        const double a0[3] = {value0, free.p[0][slot], free.p[0][slot + 1]};
        const double a1[3] = {value1, free.p[1][slot], free.p[1][slot + 1]};
        return hermite_poles(a0, a1);
    };
    return {make(side.lambda0, side.lambda1, 0), make(0, 0, 2), make(0, 0, 4), make(0, 0, 6)};
}

/// The change of the scalars when parameter `index` (0 to 15: end * 8 + slot) grows by one.
inline SideScalars side_scalar_direction(int index) {
    const int end = index / 8, slot = index % 8;
    double a0[3] = {0, 0, 0}, a1[3] = {0, 0, 0};
    (end == 0 ? a0 : a1)[1 + slot % 2] = 1;
    SideScalars out;
    const Scalar zero(6, 0.0), one = hermite_poles(a0, a1);
    out.lambda = out.m = out.nu = out.q = zero;
    (slot < 2 ? out.lambda : slot < 4 ? out.m : slot < 6 ? out.nu : out.q) = one;
    return out;
}

/// What a side's layers are built from, computed once.
struct SideBase {
    Curve c, cp, cpp, f1, f1p, f2;
};

inline SideBase side_base(const TriangleSide &side) {
    SideBase base;
    base.c = to_curve(side.poles);
    base.cp = derivative(base.c);
    base.cpp = derivative(base.cp);
    base.f1 = to_curve(side.cross1);
    base.f1p = derivative(base.f1);
    base.f2 = to_curve(side.cross2);
    return base;
}

/// F = lambda f1 + m C' (degree 10).
inline Curve cross_first(const SideBase &base, const Scalar &lambda, const Scalar &m) {
    const Curve a = multiply(lambda, base.f1), b = multiply(m, base.cp);
    return combine({{1.0, &a}, {1.0, &b}}, 10);
}

/// G = lambda^2 f2 + 2 lambda m f1' + m^2 C'' + nu f1 + q C' (degree 15).
inline Curve cross_second(const SideBase &base, const SideScalars &s) {
    const Curve a = multiply(multiply(s.lambda, s.lambda), base.f2);
    const Curve b = multiply(multiply(s.lambda, s.m), base.f1p);
    const Curve c = multiply(multiply(s.m, s.m), base.cpp);
    const Curve d = multiply(s.nu, base.f1);
    const Curve e = multiply(s.q, base.cp);
    return combine({{1.0, &a}, {2.0, &b}, {1.0, &c}, {1.0, &d}, {1.0, &e}}, 15);
}

/// The change of G when the scalars change by `d` (G is quadratic in them; this is its derivative along `d`).
inline Curve cross_second_change(const SideBase &base, const SideScalars &s, const SideScalars &d) {
    const Curve a = multiply(multiply(s.lambda, d.lambda), base.f2);
    const Curve b = multiply(multiply(d.lambda, s.m), base.f1p);
    const Curve b2 = multiply(multiply(s.lambda, d.m), base.f1p);
    const Curve c = multiply(multiply(s.m, d.m), base.cpp);
    const Curve e = multiply(d.nu, base.f1);
    const Curve f = multiply(d.q, base.cp);
    return combine({{2.0, &a}, {2.0, &b}, {2.0, &b2}, {2.0, &c}, {1.0, &e}, {1.0, &f}}, 15);
}

/// The three layers (0, 1, 2) of control points of one side, as the exact degree-(n - layer) polygons (n >= 17).
inline void side_layers(const SideBase &base, const SideScalars &s, int n, Curve layers[3]) {
    const Curve f = cross_first(base, s.lambda, s.m), g = cross_second(base, s);
    layers[0] = elevate(base.c, n);
    layers[1] = combine({{1.0, &base.c}, {1.0 / n, &f}}, n - 1);
    layers[2] = combine({{1.0, &base.c}, {2.0 / n, &f}, {1.0 / (static_cast<double>(n) * (n - 1)), &g}}, n - 2);
}

/// The derivative of the layers along `d`.
inline void side_layer_change(const SideBase &base, const SideScalars &s, const SideScalars &d, int n, Curve layers[3]) {
    const Curve f = cross_first(base, d.lambda, d.m), g = cross_second_change(base, s, d);
    layers[0] = Curve(static_cast<std::size_t>(n) + 1, Vec{0, 0, 0});
    layers[1] = combine({{1.0 / n, &f}}, n - 1);
    layers[2] = combine({{2.0 / n, &f}, {1.0 / (static_cast<double>(n) * (n - 1)), &g}}, n - 2);
}

/// One control point of one side's layers.
struct Claim {
    int side = 0, layer = 0, index = 0;
};

/// The slot of the net a claim fills.
inline std::size_t claim_slot(const Claim &claim, int n) {
    const int a = claim.side, b = (claim.side + 1) % 3, c = (claim.side + 2) % 3;
    int idx[3];
    idx[c] = claim.layer;
    idx[b] = claim.index;
    idx[a] = n - claim.layer - claim.index;
    return static_cast<std::size_t>(idx[0]) * (n + 1) + idx[1];
}

/// The slots two sides both claim: the first claimant's value is kept, the difference is the mismatch.
struct Conflict {
    Claim first, second;
};

inline std::vector<Conflict> conflict_structure(int n, std::vector<Claim> &first_claims) {
    std::vector<Conflict> conflicts;
    std::vector<int> owner(static_cast<std::size_t>(n + 1) * (n + 1), -1);
    first_claims.clear();
    for (int s = 0; s < 3; ++s) {
        for (int layer = 0; layer < 3; ++layer) {
            for (int m = 0; m <= n - layer; ++m) {
                const Claim claim{s, layer, m};
                const std::size_t slot = claim_slot(claim, n);
                if (owner[slot] >= 0) {
                    conflicts.push_back({first_claims[static_cast<std::size_t>(owner[slot])], claim});
                } else {
                    owner[slot] = static_cast<int>(first_claims.size());
                    first_claims.push_back(claim);
                }
            }
        }
    }
    return conflicts;
}

struct TriangleStats {
    double block_mismatch = 0, raw_mismatch = 0, largest_freedom = 0;
    double min_lambda = 0; // the least value of any side's across scale over its length
    int iterations = 0;
};

/// Fills the layers of the three sides and the fair interior. The corner blocks are made to agree by reshaping each
/// side's across parametrization (SideFreedom, a Levenberg-Marquardt solve over its end derivatives, with the exact
/// Jacobian: the layers are polynomial in them); `raw_mismatch` is their disagreement before that, `block_mismatch` after.
inline bool build_triangle(const TriangleSide sides[3], TriangleNet &net, TriangleStats &stats) {
    const int n = kTriangleDegree;
    SideBase bases[3];
    for (int s = 0; s < 3; ++s) {
        bases[s] = side_base(sides[s]);
    }
    std::vector<Claim> first_claims;
    const std::vector<Conflict> conflicts = conflict_structure(n, first_claims);
    const std::size_t rows = conflicts.size() * 3;
    SideFreedom freedom[3];
    SideScalars scalars[3];
    Curve layers[3][3];
    auto load = [&](const std::vector<double> &x) {
        for (int s = 0; s < 3; ++s) {
            for (int e = 0; e < 2; ++e) {
                for (int q = 0; q < 8; ++q) {
                    freedom[s].p[e][q] = x[static_cast<std::size_t>(s * 16 + e * 8 + q)];
                }
            }
            scalars[s] = side_scalars(sides[s], freedom[s]);
            side_layers(bases[s], scalars[s], n, layers[s]);
        }
    };
    auto residual = [&](std::vector<double> &r) {
        r.assign(rows, 0.0);
        double worst = 0;
        for (std::size_t k = 0; k < conflicts.size(); ++k) {
            const Vec &a = layers[conflicts[k].first.side][conflicts[k].first.layer][conflicts[k].first.index];
            const Vec &b = layers[conflicts[k].second.side][conflicts[k].second.layer][conflicts[k].second.index];
            const Vec d = sub(a, b);
            worst = std::max(worst, norm(d));
            for (int c = 0; c < 3; ++c) {
                r[k * 3 + c] = d[c];
            }
        }
        return worst;
    };
    std::vector<double> x(48, 0.0), r;
    load(x);
    stats.raw_mismatch = residual(r);
    int it = 0;
    if (stats.raw_mismatch > 1e-10) {
        double mu = 1e-3, cost = 0;
        for (double v : r) {
            cost += v * v;
        }
        for (; it < 60 && cost > 1e-24; ++it) {
            // The exact Jacobian: the layers at x are loaded; parameter p of side s moves only side s's layers.
            std::vector<double> jac(rows * 48, 0.0);
            for (int s = 0; s < 3; ++s) {
                for (int p = 0; p < 16; ++p) {
                    Curve change[3];
                    side_layer_change(bases[s], scalars[s], side_scalar_direction(p), n, change);
                    for (std::size_t k = 0; k < conflicts.size(); ++k) {
                        for (int sign = 0; sign < 2; ++sign) {
                            const Claim &claim = sign == 0 ? conflicts[k].first : conflicts[k].second;
                            if (claim.side != s) {
                                continue;
                            }
                            const Vec &d = change[claim.layer][claim.index];
                            for (int c = 0; c < 3; ++c) {
                                jac[(k * 3 + c) * 48 + s * 16 + p] += (sign == 0 ? 1.0 : -1.0) * d[c];
                            }
                        }
                    }
                }
            }
            std::vector<double> normal(48 * 48, 0.0), gradient(48, 0.0);
            for (std::size_t k = 0; k < rows; ++k) {
                for (int a = 0; a < 48; ++a) {
                    const double ja = jac[k * 48 + a];
                    if (ja == 0) {
                        continue;
                    }
                    gradient[a] -= ja * r[k];
                    for (int b = 0; b < 48; ++b) {
                        normal[a * 48 + b] += ja * jac[k * 48 + b];
                    }
                }
            }
            bool improved = false;
            for (int attempt = 0; attempt < 12 && !improved; ++attempt) {
                std::vector<double> matrix = normal, step = gradient;
                for (int a = 0; a < 48; ++a) {
                    matrix[a * 48 + a] += mu;
                }
                if (!solve_dense(matrix, step, 48)) {
                    mu *= 10;
                    continue;
                }
                std::vector<double> trial = x, rt;
                for (int a = 0; a < 48; ++a) {
                    trial[a] += step[a];
                }
                load(trial);
                residual(rt);
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
            load(x); // the layers of the accepted point (a rejected trial left its own)
            if (!improved) {
                break;
            }
        }
    }
    load(x);
    stats.block_mismatch = residual(r);
    stats.iterations = it;
    stats.largest_freedom = 0;
    for (double v : x) {
        stats.largest_freedom = std::max(stats.largest_freedom, std::abs(v));
    }
    stats.min_lambda = 1e300;
    for (int s = 0; s < 3; ++s) {
        for (int k = 0; k <= 64; ++k) {
            stats.min_lambda = std::min(stats.min_lambda, value_at(scalars[s].lambda, k / 64.0));
        }
    }
    net.degree = n;
    net.b.assign(static_cast<std::size_t>(n + 1) * (n + 1), Vec{0, 0, 0});
    for (const Claim &claim : first_claims) {
        net.b[claim_slot(claim, n)] = layers[claim.side][claim.layer][claim.index];
    }
    return fair_interior(net);
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
