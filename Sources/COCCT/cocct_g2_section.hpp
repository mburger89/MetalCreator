// The quintic Hermite section of a curvature-continuous fillet strip. Header-only and free of OpenCascade, so a test
// can reach it through `occt_g2_section_test`.
#ifndef COCCT_G2_SECTION_HPP
#define COCCT_G2_SECTION_HPP

#include <algorithm>
#include <array>
#include <cmath>

namespace cocct::g2 {

using Vec = std::array<double, 3>;

inline Vec add(const Vec &a, const Vec &b) { return {a[0] + b[0], a[1] + b[1], a[2] + b[2]}; }
inline Vec sub(const Vec &a, const Vec &b) { return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}; }
inline Vec scale(const Vec &a, double s) { return {a[0] * s, a[1] * s, a[2] * s}; }
inline double dot(const Vec &a, const Vec &b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
inline double norm(const Vec &a) { return std::sqrt(dot(a, a)); }

/// What a section must match at one end. `direction` is the unit direction of travel along the section at this end
/// (at the start: into the blend; at the finish: out of it, into the neighbour). `acceleration` is the second
/// derivative with respect to arc length: the neighbour's normal curvature across the spring edge times its normal.
struct EndCondition {
    Vec position{};
    Vec direction{};
    Vec acceleration{};
};

/// The tangent-length convention. A circular arc of radius r and turning angle theta, written as a cubic Bezier on
/// [0, 1], has end derivative of length 4 r tan(theta / 4). With chord c = 2 r sin(theta / 2) that is
/// c / cos(theta / 4)^2. The section's end derivative has length weight * this (weight 1: the circle's proportions).
inline double circular_tangent_length(double chord, double turning_angle) {
    const double c = std::cos(turning_angle / 4);
    return chord / (c * c);
}

inline double turning_angle(const Vec &d0, const Vec &d1) {
    return std::acos(std::clamp(dot(d0, d1), -1.0, 1.0));
}

/// The six poles of the quintic Bezier on [0, 1] with C(0), C'(0) = len0 * direction, C''(0) = len0^2 * acceleration
/// (no tangential part is added) and the same at 1. Hermite G2 data: the tangential part of C'' is zero when the
/// acceleration is normal to the direction, which holds for a normal curvature.
inline std::array<Vec, 6> quintic_poles(const EndCondition &a, double len0, const EndCondition &b, double len1) {
    std::array<Vec, 6> p{};
    const Vec d0 = scale(a.direction, len0);
    const Vec dd0 = scale(a.acceleration, len0 * len0);
    const Vec d1 = scale(b.direction, len1);
    const Vec dd1 = scale(b.acceleration, len1 * len1);
    p[0] = a.position;
    p[1] = add(p[0], scale(d0, 1.0 / 5));
    p[2] = add(sub(scale(p[1], 2), p[0]), scale(dd0, 1.0 / 20));
    p[5] = b.position;
    p[4] = sub(p[5], scale(d1, 1.0 / 5));
    p[3] = add(sub(scale(p[4], 2), p[5]), scale(dd1, 1.0 / 20));
    return p;
}

/// Position, first and second derivative of the Bezier with `poles` at t.
inline void evaluate(const std::array<Vec, 6> &poles, double t, Vec &position, Vec &d1, Vec &d2) {
    auto bernstein = [](int n, int i, double u) {
        double binom = 1;
        for (int k = 1; k <= i; ++k) {
            binom = binom * (n - i + k) / k;
        }
        return binom * std::pow(u, i) * std::pow(1 - u, n - i);
    };
    position = d1 = d2 = {0, 0, 0};
    for (int i = 0; i <= 5; ++i) {
        position = add(position, scale(poles[i], bernstein(5, i, t)));
    }
    for (int i = 0; i <= 4; ++i) {
        d1 = add(d1, scale(sub(poles[i + 1], poles[i]), 5 * bernstein(4, i, t)));
    }
    for (int i = 0; i <= 3; ++i) {
        const Vec second = add(sub(poles[i + 2], scale(poles[i + 1], 2)), poles[i]);
        d2 = add(d2, scale(second, 20 * bernstein(3, i, t)));
    }
}

} // namespace cocct::g2

#endif
