// An edge's arc-length table and the nearest-point search used to pair two edges by the fraction of their length. Shared by Match
// Surface and Blend Surface (both start a closed edge's pairing at the point nearest the other edge's seam). Not part of the public
// C API.
#ifndef COCCT_ARC_TABLE_HPP
#define COCCT_ARC_TABLE_HPP

#include <BRepAdaptor_Curve.hxx>
#include <gp_Pnt.hxx>

#include <algorithm>
#include <cmath>
#include <vector>

namespace cocct {

constexpr int kTableIntervals = 1024;
constexpr double kClosedGap = 1e-4; // mm: an edge whose ends are this close is closed

/// A polyline's arc-length table over a parameter range.
struct length_table {
    std::vector<double> parameter;
    std::vector<double> length; // cumulative

    template <typename Point>
    void build(double first, double last, Point point) {
        parameter.resize(kTableIntervals + 1);
        length.assign(kTableIntervals + 1, 0.0);
        gp_Pnt previous;
        for (int i = 0; i <= kTableIntervals; ++i) {
            parameter[i] = first + (last - first) * i / kTableIntervals;
            const gp_Pnt p = point(parameter[i]);
            if (i > 0) {
                length[i] = length[i - 1] + p.Distance(previous);
            }
            previous = p;
        }
    }
    double total() const { return length.back(); }
    /// The arc length from the first parameter to `t`.
    double length_at(double t) const {
        const double first = parameter.front(), last = parameter.back();
        const double position = std::clamp((t - first) / (last - first), 0.0, 1.0) * kTableIntervals;
        const int i = std::min(static_cast<int>(position), kTableIntervals - 1);
        return length[i] + (length[i + 1] - length[i]) * (position - i);
    }
    /// The parameter `wanted` arc length from the first parameter.
    double parameter_at(double wanted) const {
        const auto it = std::upper_bound(length.begin(), length.end(), wanted);
        const int i = std::clamp(static_cast<int>(it - length.begin()) - 1, 0, kTableIntervals - 1);
        const double span = length[i + 1] - length[i];
        const double fraction = span > 1e-300 ? (wanted - length[i]) / span : 0.0;
        return parameter[i] + (parameter[i + 1] - parameter[i]) * std::clamp(fraction, 0.0, 1.0);
    }
};

/// The parameter of the point of the closed edge `curve` (tabulated by `table`) nearest `point`: the nearest table sample, refined
/// by a ternary search in its neighbours. At the first or last sample the search crosses the seam (parameters wrap round the edge's
/// range), so a point right at the seam is found exactly. The result is within the table's range.
inline double nearest_parameter(const BRepAdaptor_Curve &curve, const length_table &table, const gp_Pnt &point) {
    const double first = table.parameter.front(), last = table.parameter.back(), period = last - first;
    const auto wrapped = [&](double t) {
        t = first + std::fmod(t - first, period);
        return t < first ? t + period : t;
    };
    const auto distance = [&](double t) { return curve.Value(wrapped(t)).Distance(point); };
    int nearest = 0;
    double nearest_distance = 1e300;
    for (int i = 0; i <= kTableIntervals; ++i) {
        const double d = curve.Value(table.parameter[i]).Distance(point);
        if (d < nearest_distance) {
            nearest_distance = d, nearest = i;
        }
    }
    double lo = nearest == 0 ? first - (last - table.parameter[kTableIntervals - 1]) : table.parameter[nearest - 1];
    double hi = nearest == kTableIntervals ? last + (table.parameter[1] - first) : table.parameter[nearest + 1];
    for (int step = 0; step < 60; ++step) {
        const double m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
        if (distance(m1) < distance(m2)) {
            hi = m2;
        } else {
            lo = m1;
        }
    }
    return wrapped(0.5 * (lo + hi));
}

} // namespace cocct

#endif
