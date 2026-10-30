// The edge-curve classification shared by the topology tables (cocct_inspect.cpp) and the section (cocct_section.cpp).
#ifndef COCCT_EDGE_CURVE_HPP
#define COCCT_EDGE_CURVE_HPP

#include <BRepAdaptor_Curve.hxx>
#include <GeomAbs_CurveType.hxx>

namespace cocct {

/// The kind of an edge's curve as `occt_edge_info.kind` has it: 0 line, 1 circle, 2 ellipse, 3 B-spline, 4 anything else.
inline int edge_curve_kind(const BRepAdaptor_Curve &curve) {
    switch (curve.GetType()) {
    case GeomAbs_Line: return 0;
    case GeomAbs_Circle: return 1;
    case GeomAbs_Ellipse: return 2;
    case GeomAbs_BSplineCurve: return 3;
    default: return 4;
    }
}

} // namespace cocct

#endif
