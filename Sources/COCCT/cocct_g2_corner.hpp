// SPIKE (G-b Task 2d): the control net of one quadrilateral of a G2 corner patch. Header-only and free of OpenCascade.
//
// A corner where n fillet strips meet leaves an n-sided hole bounded by the strips' end curves. It is split into n
// quadrilaterals, one per hole corner V: the quadrilateral has V, the midpoints M of the two end curves that meet at V,
// and the centre C. Each is a degree-5 Bezier patch P[a][b], a running from V along one end curve's half and b along the
// other's. Its first three rows along each outer side come from the strip behind that side (the end curve and its first
// and second cross-boundary derivatives), so the patch joins that strip with matching position, tangent plane and
// normal curvature. The two inner sides (M to C) lie in the planes in which the neighbouring quadrilaterals mirror this
// one; the control rows next to them satisfy the mirror conditions (the row differences perpendicular to the plane for
// C1, the second difference in the plane for C2), so the mirrored pair joins G2 by construction. The 3 x 3 block at
// the centre is what is left; it is chosen to be as fair as the constraints allow.
#ifndef COCCT_G2_CORNER_HPP
#define COCCT_G2_CORNER_HPP

#include "cocct_g2_section.hpp"

#include <array>
#include <cmath>
#include <vector>

namespace cocct::g2 {

using Net = std::array<std::array<Vec, 6>, 6>;

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

/// What one quadrilateral is built from. `rows_x[r][a]` is row r (0 = the end curve's half, 1 and 2 the cross-boundary
/// rows) of the side along a, `rows_y[r][b]` of the side along b; both start at V. The inner side a = 1 runs from the
/// midpoint of the x curve to `centre` and lies in the plane through `seam_x_point` with normal `seam_x_normal`; the
/// inner side b = 1 likewise.
struct QuadInput {
    std::array<std::array<Vec, 6>, 3> rows_x{}, rows_y{};
    Vec centre{};
    Vec seam_x_point{}, seam_x_normal{};
    Vec seam_y_point{}, seam_y_normal{};
};

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

/// Builds the net. Returns false if the data are inconsistent (the corner block the two sides share differs by more than
/// `tolerance`, or the system has no solution); `mismatch` gets the largest difference of the shared block.
inline bool build_quad(const QuadInput &in, Net &net, double &mismatch, double tolerance) {
    mismatch = 0;
    for (int a = 0; a < 6; ++a) {
        for (int b = 0; b < 6; ++b) {
            net[a][b] = {0, 0, 0};
        }
    }
    for (int r = 0; r < 3; ++r) {
        for (int a = 0; a < 6; ++a) {
            net[a][r] = in.rows_x[r][a];
        }
    }
    for (int r = 0; r < 3; ++r) {
        for (int b = 0; b < 6; ++b) {
            if (b >= 3 || r >= 3) {
                net[r][b] = in.rows_y[r][b];
            } else {
                mismatch = std::max(mismatch, norm(sub(net[r][b], in.rows_y[r][b])));
            }
        }
    }
    if (mismatch > tolerance) {
        return false;
    }
    // Unknowns: the 3 x 3 block a, b in 3...5 except (5, 5), which is the centre.
    net[5][5] = in.centre;
    struct Index {
        int a, b;
    };
    std::vector<Index> unknown;
    int slot[6][6];
    for (auto &row : slot) {
        for (int &s : row) {
            s = -1;
        }
    }
    for (int a = 3; a < 6; ++a) {
        for (int b = 3; b < 6; ++b) {
            if (a == 5 && b == 5) {
                continue;
            }
            slot[a][b] = static_cast<int>(unknown.size());
            unknown.push_back({a, b});
        }
    }
    const int n = static_cast<int>(unknown.size()) * 3;
    // Equality constraints: sum coefficient * unknown component = rhs.
    struct Row {
        std::vector<std::pair<int, double>> terms;
        double rhs = 0;
    };
    std::vector<Row> constraints;
    // Adds `weight * (n . P[a][b])` (for unknown or fixed points) to a row.
    auto add_dot = [&](Row &row, int a, int b, const Vec &direction, double weight) {
        if (slot[a][b] >= 0) {
            for (int c = 0; c < 3; ++c) {
                row.terms.push_back({slot[a][b] * 3 + c, weight * direction[c]});
            }
        } else {
            row.rhs -= weight * dot(direction, net[a][b]);
        }
    };
    auto unit = [](Vec v) {
        const double len = norm(v);
        return scale(v, 1 / len);
    };
    auto in_plane_basis = [&](const Vec &normal) {
        const Vec n_unit = unit(normal);
        Vec helper = std::abs(n_unit[0]) < 0.9 ? Vec{1, 0, 0} : Vec{0, 1, 0};
        Vec t1 = sub(helper, scale(n_unit, dot(helper, n_unit)));
        t1 = unit(t1);
        const Vec t2 = {n_unit[1] * t1[2] - n_unit[2] * t1[1], n_unit[2] * t1[0] - n_unit[0] * t1[2],
                        n_unit[0] * t1[1] - n_unit[1] * t1[0]};
        return std::array<Vec, 2>{t1, t2};
    };
    // seam along b at a = 5 (plane x), and seam along a at b = 5 (plane y); `along_first`: the seam row index runs over
    // b (true) or a (false).
    auto seam = [&](bool along_b, const Vec &point, const Vec &normal) {
        const Vec nu = unit(normal);
        const auto basis = in_plane_basis(nu);
        for (int s = 3; s < 6; ++s) {
            auto at = [&](int depth) { return along_b ? Index{5 - depth, s} : Index{s, 5 - depth}; };
            const Index p5 = at(0), p4 = at(1), p3 = at(2);
            if (!(p5.a == 5 && p5.b == 5)) {
                Row row; // the seam curve lies in the plane
                add_dot(row, p5.a, p5.b, nu, 1);
                row.rhs += dot(nu, point);
                constraints.push_back(row);
            }
            for (const Vec &t : basis) { // C1: P4 - P5 is perpendicular to the plane
                Row row;
                add_dot(row, p4.a, p4.b, t, 1);
                add_dot(row, p5.a, p5.b, t, -1);
                constraints.push_back(row);
            }
            Row c2; // C2: the second difference has no component perpendicular to the plane
            add_dot(c2, p3.a, p3.b, nu, 1);
            add_dot(c2, p4.a, p4.b, nu, -2);
            add_dot(c2, p5.a, p5.b, nu, 1);
            constraints.push_back(c2);
        }
    };
    seam(true, in.seam_x_point, in.seam_x_normal);
    seam(false, in.seam_y_point, in.seam_y_normal);

    // Objective: the sum of squared second differences of the net along a and along b (fairness).
    // Quadratic form 1/2 x'Hx + g'x built from the stencils.
    std::vector<double> hessian(n * n, 0.0), gradient(n, 0.0);
    auto stencil = [&](const std::array<Index, 3> &idx) {
        const double w[3] = {1, -2, 1};
        for (int c = 0; c < 3; ++c) {
            // residual r = sum w_k P_k[c]; objective r^2
            double fixed = 0;
            std::vector<std::pair<int, double>> vars;
            for (int k = 0; k < 3; ++k) {
                if (slot[idx[k].a][idx[k].b] >= 0) {
                    vars.push_back({slot[idx[k].a][idx[k].b] * 3 + c, w[k]});
                } else {
                    fixed += w[k] * net[idx[k].a][idx[k].b][c];
                }
            }
            for (const auto &[i, wi] : vars) {
                gradient[i] += 2 * wi * fixed;
                for (const auto &[j, wj] : vars) {
                    hessian[i * n + j] += 2 * wi * wj;
                }
            }
        }
    };
    for (int a = 0; a < 6; ++a) {
        for (int b = 0; b < 4; ++b) {
            stencil({Index{a, b}, Index{a, b + 1}, Index{a, b + 2}});
        }
    }
    for (int b = 0; b < 6; ++b) {
        for (int a = 0; a < 4; ++a) {
            stencil({Index{a, b}, Index{a + 1, b}, Index{a + 2, b}});
        }
    }
    // KKT: [H A'; A -eps] [x; lambda] = [-g; rhs]
    const int m = static_cast<int>(constraints.size());
    const int size = n + m;
    std::vector<double> kkt(size * size, 0.0), rhs(size, 0.0);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            kkt[i * size + j] = hessian[i * n + j];
        }
        kkt[i * size + i] += 1e-9; // keeps the fairness term definite where it is flat
        rhs[i] = -gradient[i];
    }
    for (int r = 0; r < m; ++r) {
        for (const auto &[i, w] : constraints[r].terms) {
            kkt[(n + r) * size + i] += w;
            kkt[i * size + (n + r)] += w;
        }
        kkt[(n + r) * size + (n + r)] = -1e-12;
        rhs[n + r] = constraints[r].rhs;
    }
    if (!solve_dense(kkt, rhs, size)) {
        return false;
    }
    for (std::size_t u = 0; u < unknown.size(); ++u) {
        for (int c = 0; c < 3; ++c) {
            net[unknown[u].a][unknown[u].b][c] = rhs[u * 3 + c];
        }
    }
    return true;
}

} // namespace cocct::g2

#endif
