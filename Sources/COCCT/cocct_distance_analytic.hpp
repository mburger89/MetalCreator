// The analytic fast path of occt_distances: exact distances to planar and cylindrical faces without BRepExtrema.
// Header-only, used by cocct_distance.cpp alone. Not part of the public C API.
#ifndef COCCT_DISTANCE_ANALYTIC_HPP
#define COCCT_DISTANCE_ANALYTIC_HPP

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepClass_FaceClassifier.hxx>
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <ElSLib.hxx>
#include <GeomAbs_CurveType.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <TopAbs_State.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Vertex.hxx>
#include <TopoDS_Face.hxx>
#include <gp_Ax3.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

#include "cocct_internal.hpp"

namespace cocct {

/// A boundary edge that is a line segment or a circular arc, kept as plain numbers so a distance to it is a few flops.
struct AnalyticEdge {
    bool line = true;
    gp_Pnt start;       // the segment's start, or the arc's start
    gp_Pnt end;         // the segment's end, or the arc's end
    gp_Pnt cornerStart; // the shared vertex's point at `start`: the outline test reads this, so neighbours agree to the bit
    gp_Pnt cornerEnd;   // the same at `end`
    gp_Pnt mid;         // the point halfway along the parameter range
    gp_Pnt center;      // arc only
    gp_Dir axis;        // arc: the circle's normal
    gp_Dir xAxis;       // arc: the direction of parameter 0
    gp_Dir yAxis;       // arc: the direction of parameter pi/2
    double radius = 0;  // arc only
    double first = 0;   // arc: the first parameter
    double span = 0;    // arc: the parameter range (<= 2 pi)

    /// The exact distance from `p` to the segment or the arc.
    double distance(const gp_Pnt &p) const {
        if (line) {
            const gp_Vec along(start, end);
            const double length2 = along.SquareMagnitude();
            if (length2 <= 0) {
                return p.Distance(start);
            }
            const double t = std::clamp(gp_Vec(start, p).Dot(along) / length2, 0.0, 1.0);
            return p.Distance(gp_Pnt(start.XYZ() + t * along.XYZ()));
        }
        const gp_Vec offset(center, p);
        const double height = offset.Dot(gp_Vec(axis));
        const double x = offset.Dot(gp_Vec(xAxis));
        const double y = offset.Dot(gp_Vec(yAxis));
        const double rho = std::hypot(x, y);
        if (rho < 1e-14) {
            return std::hypot(radius, height); // on the axis: every point of the arc is equally near
        }
        double relative = std::fmod(std::atan2(y, x) - first, 2 * M_PI);
        if (relative < 0) {
            relative += 2 * M_PI;
        }
        if (relative <= span) {
            return std::hypot(rho - radius, height);
        }
        return std::min(p.Distance(start), p.Distance(end));
    }
};

/// One piece of a planar face's outline in the plane's (u, v) coordinates, monotone in v, for the even-odd ray test. A
/// straight piece runs from (x0, y0) to (x1, y1); an arc piece is part of the circle at (x0, y0) of radius `radius`, on the
/// side of the centre given by `side` (+1 right, -1 left).
struct OutlinePiece {
    bool arc = false;
    double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    double radius = 0, side = 1;
    double low = 0, high = 0; // the v range, half-open [low, high)
};

inline double wrap_angle(double a) {
    a = std::fmod(a, 2 * M_PI);
    return a < 0 ? a + 2 * M_PI : a;
}

/// Appends the pieces of `edge`, given in (u, v) by `toUV`.
template <typename ToUV>
void add_outline(std::vector<OutlinePiece> &pieces, const AnalyticEdge &edge, ToUV toUV) {
    double x0 = 0, y0 = 0, x1 = 0, y1 = 0, xm = 0, ym = 0;
    toUV(edge.cornerStart, x0, y0);
    toUV(edge.cornerEnd, x1, y1);
    if (edge.line) {
        OutlinePiece piece;
        piece.x0 = x0; piece.y0 = y0; piece.x1 = x1; piece.y1 = y1;
        piece.low = std::min(y0, y1);
        piece.high = std::max(y0, y1);
        pieces.push_back(piece);
        return;
    }
    toUV(edge.mid, xm, ym);
    double cx = 0, cy = 0;
    toUV(edge.center, cx, cy);
    const double a0 = std::atan2(y0 - cy, x0 - cx);
    double lo = a0;
    double span = 2 * M_PI;
    double yFirst = y0, yLast = y0; // the v of the range's two ends, exactly as the neighbouring edges have them
    if (edge.span < 2 * M_PI - 1e-9) {
        const double s = wrap_angle(std::atan2(y1 - cy, x1 - cx) - a0);
        const double m = wrap_angle(std::atan2(ym - cy, xm - cx) - a0);
        if (m < s) {
            span = s; // counter-clockwise from the start
            yLast = y1;
        } else {
            yFirst = y1;
            lo = std::atan2(y1 - cy, x1 - cx); // clockwise: the arc is counter-clockwise from its end
            span = wrap_angle(a0 - lo);
        }
    }
    // Cut the angle range [lo, lo + span] where sin has an extremum (pi/2 and 3 pi/2), so each piece is monotone in v.
    std::vector<double> cuts{lo};
    for (double k = std::ceil((lo - M_PI / 2) / M_PI); M_PI / 2 + k * M_PI < lo + span; k += 1) {
        const double at = M_PI / 2 + k * M_PI;
        if (at > lo + 1e-12) {
            cuts.push_back(at);
        }
    }
    cuts.push_back(lo + span);
    for (std::size_t i = 0; i + 1 < cuts.size(); ++i) {
        const double ta = cuts[i], tb = cuts[i + 1];
        OutlinePiece piece;
        piece.arc = true;
        piece.x0 = cx; piece.y0 = cy;
        piece.radius = edge.radius;
        piece.side = std::cos(0.5 * (ta + tb)) >= 0 ? 1 : -1;
        const double ya = i == 0 ? yFirst : cy + edge.radius * std::sin(ta);
        const double yb = i + 2 == cuts.size() ? yLast : cy + edge.radius * std::sin(tb);
        piece.low = std::min(ya, yb);
        piece.high = std::max(ya, yb);
        pieces.push_back(piece);
    }
}

/// Whether (px, py) lies inside the outline by the even-odd rule: a ray towards +u crosses an odd number of pieces. The
/// half-open v ranges make a ray through a shared vertex count once, and a hole's wire counts like the outer one.
inline bool inside_outline(const std::vector<OutlinePiece> &pieces, double px, double py) {
    bool inside = false;
    for (const OutlinePiece &piece : pieces) {
        if (!(piece.low <= py && py < piece.high)) {
            continue;
        }
        double x;
        if (piece.arc) {
            const double dy = py - piece.y0;
            x = piece.x0 + piece.side * std::sqrt(std::max(0.0, piece.radius * piece.radius - dy * dy));
        } else {
            x = piece.x0 + (py - piece.y0) * (piece.x1 - piece.x0) / (piece.y1 - piece.y0);
        }
        if (x > px) {
            inside = !inside;
        }
    }
    return inside;
}

/// A planar face (kind plane) or a cylindrical face (kind cylinder) with its parametrisation.
struct AnalyticFace {
    bool cylinder = false;
    TopoDS_Face face;
    gp_Ax3 position;
    double radius = 0;
    std::vector<OutlinePiece> outline; // planar only
    double uMin = 0; // cylinder: the low end of the face's u range, to put a computed angle in the right period
};

/// The target of a distance call, split into what has an exact formula and what is left to BRepExtrema. Built once per
/// call and read, never changed, by every thread.
struct AnalyticTarget {
    std::vector<AnalyticFace> faces;
    std::vector<AnalyticEdge> edges;
    TopoDS_Compound rest; // every other face
    bool hasRest = false;
};

/// One point per TopoDS_Vertex, taken once from BRep_Tool::Pnt. Every edge that ends at a vertex reads its corner from here,
/// so two neighbouring edges place a shared corner at bit-identical coordinates (the curves' own end values differ in the
/// last bits, or by the vertex tolerance after a Boolean, and the half-open v ranges of the outline test would then not cancel).
struct VertexPoints {
    TopTools_IndexedMapOfShape map;
    std::vector<gp_Pnt> points;

    gp_Pnt at(const TopoDS_Vertex &vertex) {
        const int index = map.Add(vertex);
        if (index > static_cast<int>(points.size())) {
            points.push_back(BRep_Tool::Pnt(vertex));
        }
        return points[static_cast<std::size_t>(index) - 1];
    }
};

inline bool analytic_edge(const TopoDS_Edge &edge, AnalyticEdge &out, VertexPoints &corners) {
    if (BRep_Tool::Degenerated(edge)) {
        return false;
    }
    // The vertices at the curve's first and last parameter. Not cumulative in the edge's orientation: a reversed edge
    // still has its curve running first to last, and `start` and `end` below follow the curve.
    TopoDS_Vertex firstVertex, lastVertex;
    TopExp::Vertices(edge, firstVertex, lastVertex, false);
    if (firstVertex.IsNull() || lastVertex.IsNull()) {
        return false;
    }
    const BRepAdaptor_Curve curve(edge);
    const double first = curve.FirstParameter();
    const double last = curve.LastParameter();
    if (!std::isfinite(first) || !std::isfinite(last)) {
        return false;
    }
    if (curve.GetType() == GeomAbs_Line) {
        out.line = true;
        out.start = curve.Value(first);
        out.end = curve.Value(last);
        out.mid = curve.Value(0.5 * (first + last));
        out.cornerStart = corners.at(firstVertex);
        out.cornerEnd = corners.at(lastVertex);
        return true;
    }
    if (curve.GetType() == GeomAbs_Circle) {
        const gp_Circ circle = curve.Circle();
        out.line = false;
        out.start = curve.Value(first);
        out.end = curve.Value(last);
        out.mid = curve.Value(0.5 * (first + last));
        out.cornerStart = corners.at(firstVertex);
        out.cornerEnd = corners.at(lastVertex);
        out.center = circle.Location();
        out.axis = circle.Axis().Direction();
        out.xAxis = circle.XAxis().Direction();
        out.yAxis = circle.YAxis().Direction();
        out.radius = circle.Radius();
        out.first = first;
        out.span = std::min(last - first, 2 * M_PI);
        return out.span >= 0;
    }
    return false;
}

/// Sorts `faces` into the analytic ones (a plane or a cylinder whose every boundary edge is a line or a circle arc) and the
/// rest. With `enabled` false every face is rest, which is the plain BRepExtrema path.
inline AnalyticTarget split_target(const std::vector<TopoDS_Face> &faces, bool enabled) {
    AnalyticTarget target;
    BRep_Builder builder;
    builder.MakeCompound(target.rest);
    TopTools_IndexedMapOfShape seen;
    VertexPoints corners;
    for (const TopoDS_Face &face : faces) {
        bool analytic = false;
        AnalyticFace entry;
        std::vector<AnalyticEdge> edges;
        std::vector<bool> fresh; // per edge: not yet listed for an earlier face
        if (enabled) {
            const BRepAdaptor_Surface surface(face);
            const GeomAbs_SurfaceType type = surface.GetType();
            if (type == GeomAbs_Plane) {
                entry.position = surface.Plane().Position();
                analytic = true;
            } else if (type == GeomAbs_Cylinder) {
                const gp_Cylinder cylinder = surface.Cylinder();
                entry.cylinder = true;
                entry.position = cylinder.Position();
                entry.radius = cylinder.Radius();
                double uMin = 0, uMax = 0, vMin = 0, vMax = 0;
                BRepTools::UVBounds(face, uMin, uMax, vMin, vMax);
                entry.uMin = uMin;
                analytic = std::isfinite(uMin) && std::isfinite(uMax) && entry.radius > 1e-9;
            }
            if (analytic) {
                for (TopExp_Explorer it(face, TopAbs_EDGE); it.More() && analytic; it.Next()) {
                    AnalyticEdge edge;
                    if (analytic_edge(TopoDS::Edge(it.Current()), edge, corners)) {
                        edges.push_back(edge);
                        fresh.push_back(seen.FindIndex(it.Current()) == 0);
                    } else {
                        analytic = false;
                    }
                }
            }
        }
        if (analytic && !entry.cylinder) {
            const gp_Ax3 position = entry.position;
            for (const AnalyticEdge &edge : edges) {
                add_outline(entry.outline, edge, [&](const gp_Pnt &point, double &u, double &v) {
                    ElSLib::PlaneParameters(position, point, u, v);
                });
            }
        }
        if (analytic) {
            entry.face = face;
            target.faces.push_back(entry);
            for (TopExp_Explorer it(face, TopAbs_EDGE); it.More(); it.Next()) {
                seen.Add(it.Current());
            }
            for (std::size_t i = 0; i < edges.size(); ++i) {
                if (fresh[i]) {
                    target.edges.push_back(edges[i]);
                }
            }
        } else {
            builder.Add(target.rest, face);
            target.hasRest = true;
        }
    }
    return target;
}

/// The nearest distance from `p` to the analytic part of `target`, at most `best`. Returns `best` unchanged when nothing
/// there is nearer. `fallback` is set when a cylinder cannot decide (the point is on its axis); the caller then measures
/// that face with BRepExtrema.
///
/// Every boundary edge of an analytic face is a candidate, and a face's own surface is one when the point's projection falls
/// inside the face. That is exact: a point whose projection lies outside the face has its nearest point on the boundary.
inline double analytic_distance(const AnalyticTarget &target, const gp_Pnt &p, double best,
                                std::vector<const AnalyticFace *> &fallback) {
    for (const AnalyticEdge &edge : target.edges) {
        best = std::min(best, edge.distance(p));
    }
    for (const AnalyticFace &entry : target.faces) {
        double across = 0;
        double u = 0;
        double v = 0;
        if (entry.cylinder) {
            ElSLib::CylinderParameters(entry.position, entry.radius, p, u, v);
            const gp_Vec offset(entry.position.Location(), p);
            const double axial = offset.Dot(gp_Vec(entry.position.Direction()));
            const gp_Vec radial = offset - axial * gp_Vec(entry.position.Direction());
            const double rho = radial.Magnitude();
            if (rho < 1e-9) {
                fallback.push_back(&entry);
                continue;
            }
            across = std::abs(rho - entry.radius);
            while (u < entry.uMin - 1e-9) {
                u += 2 * M_PI;
            }
            while (u >= entry.uMin + 2 * M_PI - 1e-9) {
                u -= 2 * M_PI;
            }
        } else {
            ElSLib::PlaneParameters(entry.position, p, u, v);
            across = std::abs(gp_Vec(entry.position.Location(), p).Dot(gp_Vec(entry.position.Direction())));
        }
        if (across >= best) {
            continue; // the face cannot be nearer than what is already known
        }
        if (!entry.cylinder) {
            if (inside_outline(entry.outline, u, v)) {
                best = across;
            }
            continue;
        }
        BRepClass_FaceClassifier classifier;
        classifier.Perform(entry.face, gp_Pnt2d(u, v), 1e-9);
        const TopAbs_State state = classifier.State();
        if (state == TopAbs_IN || state == TopAbs_ON) {
            best = across;
        }
    }
    return best;
}

} // namespace cocct

#endif
