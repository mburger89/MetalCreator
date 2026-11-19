// Where an edge's pcurve lies on a B-spline surface's natural boundary (NS-4: Extend Surface and Match Surface). Not part of the public C API.
#ifndef COCCT_ISO_SIDES_HPP
#define COCCT_ISO_SIDES_HPP

#include <Geom2d_Curve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <gp_Pnt2d.hxx>

#include <algorithm>
#include <cmath>

namespace cocct::iso {

struct bounds {
    double u0 = 0, u1 = 0, v0 = 0, v1 = 0;
};

inline bounds bounds_of(const Handle(Geom_BSplineSurface) &surface) {
    bounds out;
    surface->Bounds(out.u0, out.u1, out.v0, out.v1);
    return out;
}

/// Side codes: where a pcurve lies on the surface's natural boundary.
enum side_code { kUStart = 0, kUEnd = 1, kVStart = 2, kVEnd = 3 };

struct side_curve {
    int side = -1;        // -1: not an iso line on a natural boundary spanning the whole range
    bool increasing = true; // the running coordinate rises along the pcurve
};

/// Classifies a pcurve of `[first, last]`: an axis-parallel line on a natural boundary that runs the surface's whole other range.
inline side_curve classify(const Handle(Geom2d_Curve) &curve, double first, double last, const bounds &b) {
    side_curve out;
    const double scale_u = std::max(1.0, std::abs(b.u1 - b.u0));
    const double scale_v = std::max(1.0, std::abs(b.v1 - b.v0));
    const double tol_u = 1e-9 * scale_u;
    const double tol_v = 1e-9 * scale_v;
    const double fractions[] = {0.0, 0.25, 0.5, 0.75, 1.0};
    gp_Pnt2d points[5];
    for (int k = 0; k < 5; ++k) {
        points[k] = curve->Value(first + (last - first) * fractions[k]);
    }
    bool constant_u = true;
    bool constant_v = true;
    for (int k = 1; k < 5; ++k) {
        constant_u = constant_u && std::abs(points[k].X() - points[0].X()) <= tol_u;
        constant_v = constant_v && std::abs(points[k].Y() - points[0].Y()) <= tol_v;
    }
    if (constant_u == constant_v) {
        return out;
    }
    if (constant_u) {
        const double lo = std::min(points[0].Y(), points[4].Y());
        const double hi = std::max(points[0].Y(), points[4].Y());
        if (std::abs(lo - b.v0) > tol_v || std::abs(hi - b.v1) > tol_v) {
            return out;
        }
        if (std::abs(points[0].X() - b.u0) <= tol_u) {
            out.side = kUStart;
        } else if (std::abs(points[0].X() - b.u1) <= tol_u) {
            out.side = kUEnd;
        }
        out.increasing = points[4].Y() > points[0].Y();
    } else {
        const double lo = std::min(points[0].X(), points[4].X());
        const double hi = std::max(points[0].X(), points[4].X());
        if (std::abs(lo - b.u0) > tol_u || std::abs(hi - b.u1) > tol_u) {
            return out;
        }
        if (std::abs(points[0].Y() - b.v0) <= tol_v) {
            out.side = kVStart;
        } else if (std::abs(points[0].Y() - b.v1) <= tol_v) {
            out.side = kVEnd;
        }
        out.increasing = points[4].X() > points[0].X();
    }
    return out;
}

} // namespace cocct::iso

#endif
