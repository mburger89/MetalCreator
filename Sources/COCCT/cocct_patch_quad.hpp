// NS-2 Task 5: the four-sided G2 patch (a biquintic Coons patch with quintic Hermite blending and G2 boundary data).
// Header-only and free of OpenCascade.
//
// The patch S(u, v) on [0, 1]^2 is to take, along each of its four sides, the side's curve C, its first cross-boundary
// derivative F and its second G (all quintic Bezier curves): along the bottom side (v = 0) S = C0(u), S_v = F0(u),
// S_vv = G0(u), and the same on the other three sides, F pointing into the patch (so S_u(1, v) = -F1(v) on the right side and
// S_v(u, 1) = -F2(1 - u) on the top; the loop runs bottom, right, top, left and the top and left sides are traversed against
// u and v).
//
// The Boolean sum. Let h0_k(t) and h1_k(t) (k = 0, 1, 2) be the quintic Hermite basis: h0_k has value, first and second
// derivative (delta_k0, delta_k1, delta_k2) at t = 0 and zero jets at t = 1, and h1_k the same with the ends swapped. Write
// D_b^k(u) for the data along v = b (k = 0: C, 1: F, 2: G, with the top side's reversed and negated as above) and E_a^p(v)
// along u = a. Then
//     P_v(u, v)  = sum_{b, k} h_b_k(v) D_b^k(u)       interpolates the bottom and top sides to second order in v,
//     P_u(u, v)  = sum_{a, p} h_a_p(u) E_a^p(v)       the left and right sides to second order in u,
//     P_uv(u, v) = sum_{a, b, p, q} h_a_p(u) h_b_q(v) J_ab[p][q]
// where J_ab[p][q] = d^p/du^p D_b^q at u = a is the corner's 3 x 3 block of mixed derivatives S_{u^p v^q}. The Boolean sum
//     S = P_u + P_v - P_uv
// interpolates all twelve boundary functions. On v = 0, P_v = C0 and P_uv(u, 0) = sum_{a, p} h_a_p(u) J_a0[p][0], the Hermite
// interpolant of C0's own end jets, which is C0 itself because a quintic is determined by its jets at two ends; so
// S(u, 0) = C0(u) + (P_u(u, 0) - C0(u)) and the bracket is the Hermite interpolant of (the left and right sides' jets minus
// C0's): it vanishes exactly when the corner blocks the two sides at a corner give agree. The same holds for S_v and S_vv on
// v = 0 (entries [p][1] and [p][2]) and for the other sides. So the whole construction rests on one condition: at every corner
// the nine mixed derivatives read from the horizontal side's data and from the vertical side's data are the same. `corner_gap`
// measures how far they are from it, and the patch is made only when they agree to `kCornerAgreement` (relative, entry by
// entry, against the largest entry of the same total order or a hundredth of the block's largest derivative, whichever is
// more). With quintic sides the Boolean sum is itself the bi-quintic
// tensor Hermite interpolant of the four corner blocks, and the control net is written exactly in Bernstein form (degree 5 in
// each direction, no sampling).
#ifndef COCCT_PATCH_QUAD_HPP
#define COCCT_PATCH_QUAD_HPP

#include "cocct_g2_triangle.hpp"

#include <array>
#include <cmath>

namespace cocct::g2 {

using Quintic = std::array<Vec, 6>;

/// The derivatives of orders 0, 1 and 2 of a quintic Bezier at one end (t = 0 or 1).
using Jet = std::array<Vec, 3>;

inline Jet jet_of(const Quintic &p, int end) {
    const double t = end == 0 ? 0.0 : 1.0;
    return {bezier_value(p, t), bezier_derivative(p, t), bezier_second_derivative(p, t)};
}

/// The quintic with the given end jets (order 0 to 2 at t = 0 and at t = 1).
inline Quintic quintic_from_jets(const Jet &at0, const Jet &at1) {
    Quintic out{};
    for (int c = 0; c < 3; ++c) {
        const double a0[3] = {at0[0][c], at0[1][c], at0[2][c]};
        const double a1[3] = {at1[0][c], at1[1][c], at1[2][c]};
        const Scalar poles = hermite_poles(a0, a1);
        for (int i = 0; i < 6; ++i) {
            out[i][c] = poles[i];
        }
    }
    return out;
}

inline Quintic reversed(const Quintic &p) {
    Quintic out{};
    for (int i = 0; i < 6; ++i) {
        out[i] = p[5 - i];
    }
    return out;
}

inline Quintic negated(const Quintic &p) {
    Quintic out{};
    for (int i = 0; i < 6; ++i) {
        out[i] = scale(p[i], -1.0);
    }
    return out;
}

/// One side of the loop, oriented along it: the curve and its cross-boundary derivatives (into the hole).
struct QuadSide {
    Quintic c{}, f{}, g{};
    bool supported = false; // F and G are a face's; else they are filled from the corner blocks
};

/// The 3 x 3 block of mixed derivatives S_{u^p v^q} at a corner, `known` marking the entries a side gave.
struct CornerBlock {
    Vec d[3][3]{};
    bool known[3][3]{};
};

constexpr double kCornerAgreement = 1e-6;

struct QuadPatch {
    std::array<std::array<Vec, 6>, 6> net{}; // net[i][j]: Bernstein index i in u and j in v
    double gap[4] = {0, 0, 0, 0};            // the disagreement at the corner at the end of loop side k
};

/// The quintic Hermite basis function for jet order `k` at `end`: its Bernstein coefficients.
inline Scalar hermite_basis(int end, int k) {
    double at0[3] = {0, 0, 0}, at1[3] = {0, 0, 0};
    (end == 0 ? at0 : at1)[k] = 1;
    return hermite_poles(at0, at1);
}

/// The block a side gives at one of its ends, as the derivatives S_{u^p v^q} of the patch at the corner.
/// `horizontal`: the side runs along u (bottom or top), else along v. `tau_end`: the end of the side's own parameter at this
/// corner. `reverse`: the side runs against u (or v), `cross_sign`: the sign of its F in the patch's own direction (-1 on the
/// top and right sides, whose cross derivatives point against v and u).
inline CornerBlock block_from(const QuadSide &side, bool horizontal, int tau_end, bool reverse, double cross_sign) {
    CornerBlock block;
    const Quintic *data[3] = {&side.c, &side.f, &side.g};
    const int known_orders = side.supported ? 3 : 1;
    for (int q = 0; q < known_orders; ++q) {
        const Jet jet = jet_of(*data[q], tau_end);
        const double sign = q == 1 ? cross_sign : 1.0;
        for (int p = 0; p < 3; ++p) {
            const double along = (reverse && p % 2 == 1) ? -1.0 : 1.0;
            // The jet's order p is the derivative along the side; q the cross order.
            const int pu = horizontal ? p : q, qv = horizontal ? q : p;
            block.d[pu][qv] = scale(jet[p], sign * along);
            block.known[pu][qv] = true;
        }
    }
    return block;
}

/// Builds the patch from four sides in loop order (bottom, right, top, left). Returns false when a corner's two blocks
/// disagree by more than `kCornerAgreement`; `patch.gap` then holds each corner's disagreement (the first over the limit
/// is the one to name). `gap[k]` is the corner at the end of side k.
inline bool build_quad(const QuadSide sides[4], QuadPatch &patch) {
    // Corner (a, b): u = a, v = b. The horizontal side there, its parameter end and direction; likewise the vertical side.
    struct Place {
        int a, b;
        int horizontal_side, horizontal_end;
        int vertical_side, vertical_end;
        int corner; // the loop corner at the end of side `corner`
    };
    const Place places[4] = {
        {0, 0, 0, 0, 3, 1, 3}, // start of the bottom, end of the left
        {1, 0, 0, 1, 1, 0, 0}, // end of the bottom, start of the right
        {1, 1, 2, 0, 1, 1, 1}, // start of the top, end of the right
        {0, 1, 2, 1, 3, 0, 2}, // end of the top, start of the left
    };
    bool agree = true;
    CornerBlock blocks[2][2];
    for (const Place &place : places) {
        const bool top = place.horizontal_side == 2, left = place.vertical_side == 3;
        const CornerBlock horizontal = block_from(sides[place.horizontal_side], true, place.horizontal_end, top, top ? -1.0 : 1.0);
        const CornerBlock vertical = block_from(sides[place.vertical_side], false, place.vertical_end, left, left ? 1.0 : -1.0);
        CornerBlock joined;
        double worst = 0;
        // The block's own scale: its largest derivative (position left out), so that entries of high order, which are small,
        // are not judged against their own noise.
        double block_scale = 0;
        for (int p = 0; p < 3; ++p) {
            for (int q = 0; q < 3; ++q) {
                if (p + q > 0) {
                    block_scale = std::max(block_scale, std::max(horizontal.known[p][q] ? norm(horizontal.d[p][q]) : 0.0,
                                                                  vertical.known[p][q] ? norm(vertical.d[p][q]) : 0.0));
                }
            }
        }
        for (int order = 0; order <= 4; ++order) {
            double reference = std::max(1e-12, 1e-2 * block_scale);
            for (int p = 0; p < 3; ++p) {
                for (int q = 0; q < 3; ++q) {
                    if (p + q == order) {
                        if (horizontal.known[p][q]) {
                            reference = std::max(reference, norm(horizontal.d[p][q]));
                        }
                        if (vertical.known[p][q]) {
                            reference = std::max(reference, norm(vertical.d[p][q]));
                        }
                    }
                }
            }
            for (int p = 0; p < 3; ++p) {
                for (int q = 0; q < 3; ++q) {
                    if (p + q != order) {
                        continue;
                    }
                    const bool h = horizontal.known[p][q], v = vertical.known[p][q];
                    if (h && v) {
                        worst = std::max(worst, norm(sub(horizontal.d[p][q], vertical.d[p][q])) / reference);
                    }
                    joined.d[p][q] = h ? horizontal.d[p][q] : (v ? vertical.d[p][q] : Vec{0, 0, 0});
                    joined.known[p][q] = h || v;
                }
            }
        }
        patch.gap[place.corner] = worst;
        agree = agree && worst <= kCornerAgreement;
        blocks[place.a][place.b] = joined;
    }
    // The control net: the Boolean sum of P_u + P_v - P_uv, written in Bernstein form. With the sides quintic Hermite
    // interpolants of the corner blocks it equals P_uv alone, which is what is built.
    Scalar basis[2][3];
    for (int end = 0; end < 2; ++end) {
        for (int k = 0; k < 3; ++k) {
            basis[end][k] = hermite_basis(end, k);
        }
    }
    for (int i = 0; i < 6; ++i) {
        for (int j = 0; j < 6; ++j) {
            Vec sum{0, 0, 0};
            for (int a = 0; a < 2; ++a) {
                for (int b = 0; b < 2; ++b) {
                    for (int p = 0; p < 3; ++p) {
                        for (int q = 0; q < 3; ++q) {
                            sum = add(sum, scale(blocks[a][b].d[p][q], basis[a][p][i] * basis[b][q][j]));
                        }
                    }
                }
            }
            patch.net[i][j] = sum;
        }
    }
    return agree;
}

} // namespace cocct::g2

#endif
