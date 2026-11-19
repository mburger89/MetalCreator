// Extending a sheet's one face across untrimmed iso-boundary edges (NURBS spec, NS-4, Task 7; ruling R8).
//
// Natural is `GeomLib::ExtendSurfByLength` at continuity 2. Linear is ours: one span appended across the edge whose poles lie evenly
// on the line from each boundary pole along P0 - P1 (the cross tangent), in homogeneous coordinates for a rational surface, so it stays
// exact (deviation from R8: GeomConvert_ApproxSurface misses by micrometres while reporting 1e-8, so no approximation is made), and
// scaled so the extension at the middle of the edge is `length`. After each side the map from the old to the new parameters is found
// (affine per direction, checked at 25 points), the join is graded across the old iso line, and at the end the face's pcurves are put
// on the new surface by `replace_face_surface`, which keeps the faces, edges and vertices in their order.
#include "cocct_control_net.hpp"
#include "cocct_sheet.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <GeomLib.hxx>
#include <Geom2d_Curve.hxx>
#include <Geom2d_Line.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Geom_BoundedSurface.hxx>
#include <Geom_Curve.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColStd_Array2OfReal.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <gp_Dir2d.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace cocct;

namespace {

constexpr int kNatural = 0;
constexpr int kLinear = 1;
constexpr double kPositionLimit = 1e-4;           // mm, the thresholds of Kernel.continuity
constexpr double kAngleLimit = 0.01 * kPi / 180;   // rad
constexpr double kCurvatureFloor = 1e-4;          // 1/mm
constexpr double kMapTolerance = 1e-7;            // mm

const char *const kMoved = "The extension moved the surface; this edge can't be extended.";

/// t' = a t + b.
struct affine {
    double a = 1.0;
    double b = 0.0;
    double operator()(double t) const { return a * t + b; }
    bool is_identity() const { return std::abs(a - 1.0) <= 1e-12 && std::abs(b) <= 1e-12 * (1.0 + std::abs(b)); }
};

affine then(const affine &first, const affine &second) { return affine{second.a * first.a, second.a * first.b + second.b}; }

struct bounds {
    double u0 = 0, u1 = 0, v0 = 0, v1 = 0;
};

bounds bounds_of(const Handle(Geom_BSplineSurface) &surface) {
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
side_curve classify(const Handle(Geom2d_Curve) &curve, double first, double last, const bounds &b) {
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

/// `source` grown by one span at the end of direction `in_u`, straight along the cross tangent (R8's Linear). The poles (in homogeneous
/// coordinates when the surface is rational, so the extension stays exact and a straight line in 3D) of each new row lie evenly on the line
/// from the last row along (last row - the one before), scaled by `factor` so the extension at the middle pole is `length`.
Handle(Geom_BSplineSurface) append_linear(const Handle(Geom_BSplineSurface) &source, bool in_u, bool after, double length) {
    Handle(Geom_BSplineSurface) s = Handle(Geom_BSplineSurface)::DownCast(source->Copy());
    if (!after) {
        if (in_u) {
            s->UReverse();
        } else {
            s->VReverse();
        }
    }
    const int p = in_u ? s->UDegree() : s->VDegree();
    const int nd = in_u ? s->NbUPoles() : s->NbVPoles();
    const int no = in_u ? s->NbVPoles() : s->NbUPoles();
    const bool rational = s->IsURational() || s->IsVRational();
    const auto pole = [&](int d, int o) { return in_u ? s->Pole(d, o) : s->Pole(o, d); };
    const auto weight = [&](int d, int o) { return rational ? (in_u ? s->Weight(d, o) : s->Weight(o, d)) : 1.0; };
    // The scale: the extension at the pole nearest the middle of the edge whose cross step is not zero is `length`.
    double step = 0.0;
    const int middle = (no + 1) / 2;
    for (int spread = 0; spread < no && step <= 1e-12; ++spread) {
        for (const int o : {middle - spread, middle + spread}) {
            if (o >= 1 && o <= no && step <= 1e-12) {
                step = pole(nd, o).Distance(pole(nd - 1, o));
            }
        }
    }
    if (step <= 1e-12) {
        throw user_error("This edge can't be extended Linear: the surface doesn't run across it; use Natural.");
    }
    const double factor = length / step;

    const int nk = in_u ? s->NbUKnots() : s->NbVKnots();
    TColStd_Array1OfReal knots(1, nk + 1);
    TColStd_Array1OfInteger mults(1, nk + 1);
    for (int k = 1; k <= nk; ++k) {
        knots(k) = in_u ? s->UKnot(k) : s->VKnot(k);
        mults(k) = in_u ? s->UMultiplicity(k) : s->VMultiplicity(k);
    }
    // The new span is as long, in parameter, as the old last span times the scale, so the parameter's speed across the cross direction
    // is continuous too (C1 parametrically, which area and mesh integration rely on), not only the tangent plane.
    const double span = (nk >= 2 ? knots(nk) - knots(nk - 1) : 1.0) * factor;
    mults(nk) = p;
    knots(nk + 1) = knots(nk) + span;
    mults(nk + 1) = p + 1;

    TColgp_Array2OfPnt poles(1, in_u ? nd + p : no, 1, in_u ? no : nd + p);
    TColStd_Array2OfReal weights(1, in_u ? nd + p : no, 1, in_u ? no : nd + p);
    for (int o = 1; o <= no; ++o) {
        for (int d = 1; d <= nd + p; ++d) {
            gp_Pnt point;
            double w = 1.0;
            if (d <= nd) {
                point = pole(d, o);
                w = weight(d, o);
            } else {
                const double w_last = weight(nd, o);
                const double w_before = weight(nd - 1, o);
                const gp_Pnt last = pole(nd, o);
                const gp_Pnt before = pole(nd - 1, o);
                const double t = factor * static_cast<double>(d - nd) / p;
                w = w_last + t * (w_last - w_before);
                if (!(w > 1e-3 * w_last)) {
                    throw user_error("This edge can't be extended Linear: the surface weakens too fast across it; use Natural.");
                }
                const auto along = [&](double a, double b) { return (w_last * a + t * (w_last * a - w_before * b)) / w; };
                point = gp_Pnt(along(last.X(), before.X()), along(last.Y(), before.Y()), along(last.Z(), before.Z()));
            }
            (in_u ? poles(d, o) : poles(o, d)) = point;
            (in_u ? weights(d, o) : weights(o, d)) = w;
        }
    }
    const int ku = s->NbUKnots();
    const int kv = s->NbVKnots();
    TColStd_Array1OfReal other_knots(1, in_u ? kv : ku);
    TColStd_Array1OfInteger other_mults(1, in_u ? kv : ku);
    for (int k = 1; k <= (in_u ? kv : ku); ++k) {
        other_knots(k) = in_u ? s->VKnot(k) : s->UKnot(k);
        other_mults(k) = in_u ? s->VMultiplicity(k) : s->UMultiplicity(k);
    }
    Handle(Geom_BSplineSurface) grown;
    if (rational) {
        grown = in_u ? new Geom_BSplineSurface(poles, weights, knots, other_knots, mults, other_mults, p, s->VDegree(), false,
                                               s->IsVPeriodic())
                     : new Geom_BSplineSurface(poles, weights, other_knots, knots, other_mults, mults, s->UDegree(), p,
                                               s->IsUPeriodic(), false);
    } else {
        grown = in_u ? new Geom_BSplineSurface(poles, knots, other_knots, mults, other_mults, p, s->VDegree(), false, s->IsVPeriodic())
                     : new Geom_BSplineSurface(poles, other_knots, knots, other_mults, mults, s->UDegree(), p, s->IsUPeriodic(), false);
    }
    if (!after) {
        if (in_u) {
            grown->UReverse();
        } else {
            grown->VReverse();
        }
    }
    return grown;
}

/// Where the old surface's moved end lies in the new surface, and so the map of both directions from old to new parameters.
struct step_map {
    affine u;
    affine v;
};

affine between_bounds(double old0, double old1, double new0, double new1) {
    affine out;
    const double width = old1 - old0;
    if (std::abs(width) > 1e-300) {
        out.a = (new1 - new0) / width;
        out.b = new0 - out.a * old0;
    }
    return out;
}

step_map find_map(const Handle(Geom_BSplineSurface) &before, const Handle(Geom_BSplineSurface) &grown, bool in_u, bool after) {
    const bounds o = bounds_of(before);
    const bounds n = bounds_of(grown);
    step_map map;
    (in_u ? map.v : map.u) = in_u ? between_bounds(o.v0, o.v1, n.v0, n.v1) : between_bounds(o.u0, o.u1, n.u0, n.u1);
    const double old_lo = in_u ? o.u0 : o.v0;
    const double old_hi = in_u ? o.u1 : o.v1;
    const double new_lo = in_u ? n.u0 : n.v0;
    const double new_hi = in_u ? n.u1 : n.v1;
    const double fixed_old = after ? old_lo : old_hi;
    const double fixed_new = after ? new_lo : new_hi;
    const double moved_old = after ? old_hi : old_lo;
    const double other_old = in_u ? 0.5 * (o.v0 + o.v1) : 0.5 * (o.u0 + o.u1);
    const double other_new = (in_u ? map.v : map.u)(other_old);
    const gp_Pnt target = in_u ? before->Value(moved_old, other_old) : before->Value(other_old, moved_old);
    const auto distance = [&](double s) {
        return (in_u ? grown->Value(s, other_new) : grown->Value(other_new, s)).Distance(target);
    };
    constexpr int kSamples = 400;
    int best = 0;
    double best_distance = distance(new_lo);
    for (int k = 1; k <= kSamples; ++k) {
        const double d = distance(new_lo + (new_hi - new_lo) * k / kSamples);
        if (d < best_distance) {
            best_distance = d;
            best = k;
        }
    }
    double lo = new_lo + (new_hi - new_lo) * std::max(best - 1, 0) / kSamples;
    double hi = new_lo + (new_hi - new_lo) * std::min(best + 1, kSamples) / kSamples;
    for (int iteration = 0; iteration < 80; ++iteration) {
        const double a = lo + (hi - lo) / 3.0;
        const double b = hi - (hi - lo) / 3.0;
        if (distance(a) < distance(b)) {
            hi = b;
        } else {
            lo = a;
        }
    }
    const double found = 0.5 * (lo + hi);
    if (distance(found) > kMapTolerance || std::abs(moved_old - fixed_old) < 1e-300) {
        throw user_error(kMoved);
    }
    affine moved;
    moved.a = (found - fixed_new) / (moved_old - fixed_old);
    moved.b = fixed_new - moved.a * fixed_old;
    (in_u ? map.u : map.v) = moved;
    // 25 points of the old surface at their mapped parameters.
    for (int i = 0; i < 5; ++i) {
        for (int j = 0; j < 5; ++j) {
            const double u = o.u0 + (o.u1 - o.u0) * (i + 0.5) / 5.0;
            const double v = o.v0 + (o.v1 - o.v0) * (j + 0.5) / 5.0;
            if (before->Value(u, v).Distance(grown->Value(map.u(u), map.v(v))) > kMapTolerance) {
                throw user_error(kMoved);
            }
        }
    }
    return map;
}

/// The distance from the old edge's middle point to the new edge's, which is where `length` is measured.
double middle_distance(const Handle(Geom_BSplineSurface) &before, const Handle(Geom_BSplineSurface) &grown, const step_map &map,
                       bool in_u, bool after) {
    const bounds o = bounds_of(before);
    const bounds n = bounds_of(grown);
    const double other_old = in_u ? 0.5 * (o.v0 + o.v1) : 0.5 * (o.u0 + o.u1);
    const double other_new = (in_u ? map.v : map.u)(other_old);
    const double end_old = in_u ? (after ? o.u1 : o.u0) : (after ? o.v1 : o.v0);
    const double end_new = in_u ? (after ? n.u1 : n.u0) : (after ? n.v1 : n.v0);
    const gp_Pnt a = in_u ? before->Value(end_old, other_old) : before->Value(other_old, end_old);
    const gp_Pnt b = in_u ? grown->Value(end_new, other_new) : grown->Value(other_new, end_new);
    return a.Distance(b);
}

/// The grade the promise names: G2 for Natural (position, normal and the normal curvature across the join), G1 for Linear. The
/// surface is read on each side of the knot where the old end now lies, span by span.
void grade_join(const Handle(Geom_BSplineSurface) &grown, bool in_u, double join, int mode) {
    const char *const miss = mode == kNatural ? "The extension isn't curvature continuous with the surface; use Linear."
                                              : "The extension isn't tangent continuous with the surface.";
    const int nk = in_u ? grown->NbUKnots() : grown->NbVKnots();
    const bounds b = bounds_of(grown);
    const double scale = 1e-9 * (1.0 + std::abs(in_u ? b.u1 - b.u0 : b.v1 - b.v0));
    int at = 0;
    for (int k = 2; k < nk; ++k) {
        if (std::abs((in_u ? grown->UKnot(k) : grown->VKnot(k)) - join) <= scale) {
            at = k;
        }
    }
    if (at == 0) {
        return; // the old end is inside one polynomial span: nothing joins there
    }
    const int ku = grown->NbUKnots();
    const int kv = grown->NbVKnots();
    const double lo = in_u ? b.v0 : b.u0;
    const double hi = in_u ? b.v1 : b.u1;
    constexpr int kSamples = 32;
    struct reading {
        gp_Pnt point;
        gp_Vec normal;
        double curvature = 0;
        bool ok = false;
    };
    const auto read = [&](double along, bool after_join) {
        reading out;
        gp_Vec du, dv, duu, dvv, duv;
        const int from = after_join ? at : at - 1;
        const int to = after_join ? at + 1 : at;
        if (in_u) {
            grown->LocalD2(join, along, from, to, 1, kv, out.point, du, dv, duu, dvv, duv);
        } else {
            grown->LocalD2(along, join, 1, ku, from, to, out.point, du, dv, duu, dvv, duv);
        }
        gp_Vec n = du.Crossed(dv);
        if (n.Magnitude() < 1e-12) {
            return out;
        }
        n.Normalize();
        const gp_Vec &cross = in_u ? du : dv;
        const gp_Vec &second = in_u ? duu : dvv;
        const double speed = cross.SquareMagnitude();
        if (speed < 1e-24) {
            return out;
        }
        out.normal = n;
        out.curvature = second.Dot(n) / speed;
        out.ok = true;
        return out;
    };
    for (int i = 0; i < kSamples; ++i) {
        const double along = lo + (hi - lo) * (i + 0.5) / kSamples;
        const reading left = read(along, false);
        const reading right = read(along, true);
        if (!left.ok || !right.ok) {
            continue;
        }
        const double angle = std::atan2(left.normal.Crossed(right.normal).Magnitude(), left.normal.Dot(right.normal));
        bool pass = left.point.Distance(right.point) <= kPositionLimit && angle <= kAngleLimit;
        if (mode == kNatural) {
            const double diff = std::abs(left.curvature - right.curvature);
            pass = pass && diff <= std::max(kCurvatureFloor, 0.01 * std::max(std::abs(left.curvature), std::abs(right.curvature)));
        }
        if (!pass) {
            throw user_error(miss);
        }
    }
}

struct edge_work {
    TopoDS_Edge edge;
    Handle(Geom2d_Curve) first;
    Handle(Geom2d_Curve) second;
    double start = 0;
    double end = 0;
    side_curve first_side;
    side_curve second_side;
};

} // namespace

extern "C" {

occt_shape *occt_extend_face(const occt_shape *shape, int face_index, const int *edge_indices, int edge_count, double length, int mode,
                             occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!shape || shape->shape.IsNull() || !edge_indices || edge_count <= 0) {
            throw user_error("That surface no longer exists.");
        }
        if (!std::isfinite(length) || length <= 0.0) {
            throw user_error("The length must be greater than 0 mm.");
        }
        const bool input_valid = BRepCheck_Analyzer(shape->shape).IsValid();
        edit_copy edit = make_edit_copy(shape, face_index);
        const TopoDS_Face face = edit.face();
        const Handle(Geom_BSplineSurface) original = edit.surface;
        const bounds start_bounds = bounds_of(original);

        // The face's edges, each with its pcurve(s) and the natural boundary they lie on: all must be untrimmed iso lines.
        const TopTools_IndexedMapOfShape face_edges = map_of(face, TopAbs_EDGE);
        std::vector<edge_work> edges;
        for (int k = 1; k <= face_edges.Extent(); ++k) {
            edge_work entry;
            entry.edge = TopoDS::Edge(face_edges(k).Oriented(TopAbs_FORWARD));
            entry.first = BRep_Tool::CurveOnSurface(entry.edge, face, entry.start, entry.end);
            if (entry.first.IsNull()) {
                throw user_error("A face's edge has no curve on its surface.");
            }
            entry.first_side = classify(entry.first, entry.start, entry.end, start_bounds);
            if (BRep_Tool::IsClosed(entry.edge, face)) {
                double s = 0;
                double e = 0;
                entry.second = BRep_Tool::CurveOnSurface(TopoDS::Edge(entry.edge.Oriented(TopAbs_REVERSED)), face, s, e);
                if (!entry.second.IsNull()) {
                    entry.second_side = classify(entry.second, s, e, start_bounds);
                }
            }
            edges.push_back(entry);
        }

        // The sides to extend, from the picked edges.
        const TopTools_IndexedMapOfShape shape_edges = map_of(edit.work, TopAbs_EDGE);
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(edit.work, TopAbs_EDGE, TopAbs_FACE, edge_faces);
        bool wanted[4] = {false, false, false, false};
        for (int k = 0; k < edge_count; ++k) {
            const int index = edge_indices[k];
            if (index < 1 || index > shape_edges.Extent()) {
                throw user_error("That edge no longer exists.");
            }
            const TopoDS_Edge picked = TopoDS::Edge(shape_edges(index));
            const std::vector<TopoDS_Face> adjacent = distinct_faces(picked, edge_faces);
            if (!is_boundary_edge(picked, adjacent)) {
                throw user_error("Only a sheet's open edges can be extended.");
            }
            const int in_face = face_edges.FindIndex(picked);
            if (in_face < 1) {
                throw user_error("That edge no longer exists.");
            }
            const int side = edges[in_face - 1].first_side.side;
            if (side < 0) {
                throw user_error("Only an untrimmed edge can be extended; this edge is a trim.");
            }
            wanted[side] = true;
        }
        for (const edge_work &entry : edges) {
            if (entry.first_side.side < 0 || (!entry.second.IsNull() && entry.second_side.side < 0)) {
                throw user_error("Extend Surface can't extend a sheet whose face is trimmed.");
            }
        }

        // Grow the surface one side at a time; the parameters of every earlier step are carried along.
        Handle(Geom_BSplineSurface) current = Handle(Geom_BSplineSurface)::DownCast(original->Copy());
        affine total_u;
        affine total_v;
        for (int side = 0; side < 4; ++side) {
            if (!wanted[side]) {
                continue;
            }
            const bool in_u = side == kUStart || side == kUEnd;
            const bool after = side == kUEnd || side == kVEnd;
            if (in_u ? current->IsUPeriodic() : current->IsVPeriodic()) {
                throw user_error("Only a sheet's open edges can be extended.");
            }
            // Each build is as long as asked at the middle of the edge, measured between the old and the new edge's middle points:
            // a first try is corrected by what it measured (exactly once for Linear, which is linear in its scale).
            Handle(Geom_BSplineSurface) base = current;
            Handle(Geom_BSplineSurface) grown;
            step_map map;
            double asked = length;
            double previous_asked = 0.0;
            double previous_achieved = 0.0;
            double achieved = 0.0;
            for (int attempt = 0; attempt < 12; ++attempt) {
                if (mode == kLinear) {
                    grown = append_linear(base, in_u, after, asked);
                } else {
                    Handle(Geom_BoundedSurface) bounded = Handle(Geom_BSplineSurface)::DownCast(current->Copy());
                    GeomLib::ExtendSurfByLength(bounded, asked, 2, in_u, after);
                    grown = Handle(Geom_BSplineSurface)::DownCast(bounded);
                    if (grown.IsNull()) {
                        throw user_error("This surface couldn't be extended.");
                    }
                }
                map = find_map(base, grown, in_u, after);
                achieved = middle_distance(base, grown, map, in_u, after);
                if (achieved <= 1e-9 || std::abs(achieved - length) <= 1e-7 * length) {
                    break;
                }
                // Secant on the achieved length once two tries are known, else proportional.
                double next = asked * length / achieved;
                if (attempt > 0 && std::abs(achieved - previous_achieved) > 1e-12) {
                    const double slope = (achieved - previous_achieved) / (asked - previous_asked);
                    const double secant = asked + (length - achieved) / slope;
                    if (std::isfinite(secant) && secant > 0.0) {
                        next = secant;
                    }
                }
                previous_asked = asked;
                previous_achieved = achieved;
                asked = next;
            }
            if (achieved > 1e-9 && std::abs(achieved - length) > 1e-4 * length) {
                throw user_error("The extension couldn't be made the length asked.");
            }
            const bounds old_bounds = bounds_of(base);
            const double join = in_u ? map.u(after ? old_bounds.u1 : old_bounds.u0) : map.v(after ? old_bounds.v1 : old_bounds.v0);
            grade_join(grown, in_u, join, mode);
            total_u = then(total_u, map.u);
            total_v = then(total_v, map.v);
            current = grown;
        }

        // The pcurves on the new surface: an untouched side keeps its own; the others become lines on the new boundary.
        const bounds grown_bounds = bounds_of(current);
        const bool same_parameters = total_u.is_identity() && total_v.is_identity();
        BRep_Builder builder;
        const double tolerance = std::max(BRep_Tool::Tolerance(face), 1e-7);
        const auto moved_curve = [&](const side_curve &kind, double &length_out) {
            double constant = 0, low = 0, high = 0;
            const bool along_u = kind.side == kVStart || kind.side == kVEnd;
            switch (kind.side) {
            case kUStart: constant = grown_bounds.u0; break;
            case kUEnd: constant = grown_bounds.u1; break;
            case kVStart: constant = grown_bounds.v0; break;
            default: constant = grown_bounds.v1; break;
            }
            low = along_u ? grown_bounds.u0 : grown_bounds.v0;
            high = along_u ? grown_bounds.u1 : grown_bounds.v1;
            length_out = high - low;
            const double from = kind.increasing ? low : high;
            const gp_Pnt2d origin = along_u ? gp_Pnt2d(from, constant) : gp_Pnt2d(constant, from);
            const double sign = kind.increasing ? 1.0 : -1.0;
            const gp_Dir2d direction = along_u ? gp_Dir2d(sign, 0.0) : gp_Dir2d(0.0, sign);
            return Handle(Geom2d_Curve)(new Geom2d_Line(origin, direction));
        };
        const auto unchanged = [&](const side_curve &kind) {
            if (!same_parameters) {
                return false;
            }
            const bool along_u = kind.side == kVStart || kind.side == kVEnd;
            const double old_lo = along_u ? start_bounds.u0 : start_bounds.v0;
            const double old_hi = along_u ? start_bounds.u1 : start_bounds.v1;
            const double new_lo = along_u ? grown_bounds.u0 : grown_bounds.v0;
            const double new_hi = along_u ? grown_bounds.u1 : grown_bounds.v1;
            const double old_c = kind.side == kUStart ? start_bounds.u0 : kind.side == kUEnd ? start_bounds.u1
                                                    : kind.side == kVStart ? start_bounds.v0 : start_bounds.v1;
            const double new_c = kind.side == kUStart ? grown_bounds.u0 : kind.side == kUEnd ? grown_bounds.u1
                                                    : kind.side == kVStart ? grown_bounds.v0 : grown_bounds.v1;
            const double scale = 1e-12 * (1.0 + std::abs(old_hi - old_lo));
            return std::abs(old_lo - new_lo) <= scale && std::abs(old_hi - new_hi) <= scale && std::abs(old_c - new_c) <= scale;
        };
        for (edge_work &entry : edges) {
            const bool keep_first = unchanged(entry.first_side);
            const bool keep_second = entry.second.IsNull() || unchanged(entry.second_side);
            if (keep_first && keep_second) {
                continue;
            }
            // Both pcurves of a seam run the same range, so one line each over the new range.
            double span = 0;
            const Handle(Geom2d_Curve) first = moved_curve(entry.first_side, span);
            Handle(Geom2d_Curve) second;
            if (!entry.second.IsNull()) {
                double second_span = 0;
                second = moved_curve(entry.second_side, second_span);
                // A seam must still close on the new surface.
                for (int k = 0; k <= 8; ++k) {
                    const double t = span * k / 8.0;
                    const gp_Pnt2d a = first->Value(t);
                    const gp_Pnt2d b = second->Value(t);
                    if (current->Value(a.X(), a.Y()).Distance(current->Value(b.X(), b.Y())) > 10 * kNetCoincidence) {
                        throw user_error("Extending opens the surface along its seam.");
                    }
                }
            }
            const double new_end = span;
            const double new_start = 0.0;
            if (second.IsNull()) {
                builder.UpdateEdge(entry.edge, first, face, tolerance);
            } else {
                builder.UpdateEdge(entry.edge, first, second, face, tolerance);
            }
            builder.Range(entry.edge, face, new_start, new_end);
        }

        replace_face_surface(face, current, edit.converted ? edit.original : TopoDS_Face(), false, false);
        if (input_valid && !BRepCheck_Analyzer(edit.work).IsValid()) {
            throw user_error("Extending gives an invalid surface.");
        }
        return new occt_shape{edit.work};
    });
}

int occt_test_pcurve_gap(const occt_shape *shape, int face_index, double *gap, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
        if (face_index < 1 || face_index > faces.Extent() || !gap) {
            throw user_error("That face no longer exists.");
        }
        const TopoDS_Face face = TopoDS::Face(faces(face_index));
        const Handle(Geom_Surface) surface = BRep_Tool::Surface(face);
        double worst = 0.0;
        const TopTools_IndexedMapOfShape edge_map = map_of(face, TopAbs_EDGE);
        for (int k = 1; k <= edge_map.Extent(); ++k) {
            const TopoDS_Edge edge = TopoDS::Edge(edge_map(k).Oriented(TopAbs_FORWARD));
            if (BRep_Tool::Degenerated(edge)) {
                continue;
            }
            double first = 0, last = 0;
            const Handle(Geom_Curve) curve = BRep_Tool::Curve(edge, first, last);
            if (curve.IsNull()) {
                throw user_error("An edge has no curve.");
            }
            for (const TopAbs_Orientation orientation : {TopAbs_FORWARD, TopAbs_REVERSED}) {
                if (orientation == TopAbs_REVERSED && !BRep_Tool::IsClosed(edge, face)) {
                    continue;
                }
                double s = 0, e = 0;
                const Handle(Geom2d_Curve) pcurve = BRep_Tool::CurveOnSurface(TopoDS::Edge(edge.Oriented(orientation)), face, s, e);
                if (pcurve.IsNull()) {
                    throw user_error("An edge has no curve on its surface.");
                }
                for (int i = 0; i <= 8; ++i) {
                    const gp_Pnt2d uv = pcurve->Value(s + (e - s) * i / 8.0);
                    const gp_Pnt point = surface->Value(uv.X(), uv.Y());
                    double nearest = std::min(point.Distance(curve->Value(first)), point.Distance(curve->Value(last)));
                    GeomAPI_ProjectPointOnCurve projection(point, curve, first, last);
                    if (projection.NbPoints() >= 1) {
                        nearest = std::min(nearest, projection.LowerDistance());
                    }
                    worst = std::max(worst, nearest);
                }
            }
        }
        *gap = worst;
        return 1;
    });
}

} // extern "C"
