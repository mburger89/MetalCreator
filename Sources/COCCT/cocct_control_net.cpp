// Control nets (NURBS spec, NS-3): the B-spline poles of a sheet's one face or a curve's one piece, and a face's surface kind.
#include "cocct_control_net.hpp"
#include "cocct_sheet.hpp"

#include <BRepAdaptor_Surface.hxx>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepClass_FaceClassifier.hxx>
#include <Bnd_Box.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepLib.hxx>
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <Geom2d_Curve.hxx>
#include <Precision.hxx>
#include <TopExp.hxx>
#include <TopLoc_Location.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <BRepBuilderAPI_NurbsConvert.hxx>
#include <BRep_Tool.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <GeomConvert.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Geom_BezierSurface.hxx>
#include <Geom_Circle.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <Geom_Curve.hxx>
#include <Geom_Line.hxx>
#include <Geom_RectangularTrimmedSurface.hxx>
#include <Geom_Surface.hxx>
#include <Geom_TrimmedCurve.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <new>
#include <vector>

using namespace cocct;

namespace {

// `occt_surface_net.kind` and `converted_from` codes; Swift's SurfaceKind in this order.
enum surface_code {
    kPlane = 0, kCylinder, kCone, kSphere, kTorus, kBSpline, kOther, kBezier, kRevolution, kExtrusion, kOffset
};

int code_of(GeomAbs_SurfaceType type) {
    switch (type) {
    case GeomAbs_Plane: return kPlane;
    case GeomAbs_Cylinder: return kCylinder;
    case GeomAbs_Cone: return kCone;
    case GeomAbs_Sphere: return kSphere;
    case GeomAbs_Torus: return kTorus;
    case GeomAbs_BezierSurface: return kBezier;
    case GeomAbs_BSplineSurface: return kBSpline;
    case GeomAbs_SurfaceOfRevolution: return kRevolution;
    case GeomAbs_SurfaceOfExtrusion: return kExtrusion;
    case GeomAbs_OffsetSurface: return kOffset;
    default: return kOther;
    }
}

constexpr int kMaxDegree = 11;

template <typename T>
T *zeroed(size_t count) {
    T *memory = static_cast<T *>(std::calloc(count > 0 ? count : 1, sizeof(T)));
    if (!memory) {
        throw std::bad_alloc();
    }
    return memory;
}

Handle(Geom_Surface) unwrapped(Handle(Geom_Surface) surface) {
    while (!surface.IsNull()) {
        Handle(Geom_RectangularTrimmedSurface) trimmed = Handle(Geom_RectangularTrimmedSurface)::DownCast(surface);
        if (trimmed.IsNull()) {
            break;
        }
        surface = trimmed->BasisSurface();
    }
    return surface;
}

TopoDS_Face face_at(const occt_shape *shape, int face_index) {
    if (!shape) {
        throw user_error("That face no longer exists.");
    }
    const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
    if (face_index < 1 || face_index > faces.Extent()) {
        throw user_error("That face no longer exists.");
    }
    return TopoDS::Face(faces(face_index));
}

/// Greville abscissa of every pole of one direction: the mean of the `degree` knots after the pole's own first knot in the flat
/// sequence. A clamped direction reads it from the usual flat sequence. A periodic one has the flat sequence of one period
/// (every knot but the last, each repeated by its multiplicity: as many as poles), continued by the period in both directions.
/// OpenCascade's periodic flat knots begin `degree + 1 - first multiplicity` knots before that sequence, and pole j is the
/// basis function whose support starts at its own flat knot j, so pole j's support starts that many places before flat knot j.
/// Values are folded into [first, last].
std::vector<double> greville_all(const Handle(Geom_BSplineSurface) &surface, bool u_direction, double first, double last) {
    const int count = u_direction ? surface->NbUPoles() : surface->NbVPoles();
    const int degree = u_direction ? surface->UDegree() : surface->VDegree();
    const bool periodic = u_direction ? surface->IsUPeriodic() : surface->IsVPeriodic();
    std::vector<double> flat;
    int shift = 0;
    if (periodic) {
        shift = degree + 1 - (u_direction ? surface->UMultiplicity(1) : surface->VMultiplicity(1));
        const int knots = u_direction ? surface->NbUKnots() : surface->NbVKnots();
        for (int k = 1; k < knots; ++k) {
            const int multiplicity = u_direction ? surface->UMultiplicity(k) : surface->VMultiplicity(k);
            for (int m = 0; m < multiplicity; ++m) {
                flat.push_back(u_direction ? surface->UKnot(k) : surface->VKnot(k));
            }
        }
        if (static_cast<int>(flat.size()) != count) {
            throw user_error("This surface's periodic knots couldn't be read.");
        }
    }
    const double period = last - first;
    std::vector<double> out(count);
    for (int j = 0; j < count; ++j) {
        double sum = 0;
        for (int k = 1; k <= degree; ++k) {
            if (periodic) {
                const int at = j + k - shift;
                const int wraps = at >= 0 ? at / count : -((-at + count - 1) / count);
                sum += flat[at - wraps * count] + wraps * period;
            } else {
                const TColStd_Array1OfReal &sequence = u_direction ? surface->UKnotSequence() : surface->VKnotSequence();
                sum += sequence(std::min(sequence.Upper(), sequence.Lower() + j + k));
            }
        }
        double value = sum / degree;
        if (periodic && period > 0) {
            while (value > last) {
                value -= period;
            }
            while (value < first) {
                value += period;
            }
        }
        out[j] = std::min(std::max(value, first), last);
    }
    return out;
}

void unit_normal(const Handle(Geom_BSplineSurface) &surface, double u, double v, bool flip, double (&out)[3]) {
    double u0, u1, v0, v1;
    surface->Bounds(u0, u1, v0, v1);
    const double mid_u = 0.5 * (u0 + u1);
    const double mid_v = 0.5 * (v0 + v1);
    for (int attempt = 0; attempt < 4; ++attempt) {
        // A pole or apex gives a zero cross product: step toward the middle of the domain until it doesn't.
        const double t = attempt == 0 ? 0.0 : std::pow(10.0, attempt - 5);
        const double pu = u + t * (mid_u - u);
        const double pv = v + t * (mid_v - v);
        gp_Pnt point;
        gp_Vec du, dv;
        surface->D1(pu, pv, point, du, dv);
        const gp_Vec n = du.Crossed(dv);
        const double length = n.Magnitude();
        if (length > 1e-12) {
            const double sign = flip ? -1.0 : 1.0;
            out[0] = sign * n.X() / length;
            out[1] = sign * n.Y() / length;
            out[2] = sign * n.Z() / length;
            return;
        }
    }
    out[0] = 0;
    out[1] = 0;
    out[2] = 1;
}

struct converted_face {
    TopoDS_Face face;
    Handle(Geom_BSplineSurface) surface;
    int original = 0;
    bool converted = false;
};

/// Face `face_index`'s surface as a B-spline: itself when it is one, else an exact conversion of a copy.
converted_face convert_face(const occt_shape *shape, int face_index) {
    converted_face out;
    const TopoDS_Face source = face_at(shape, face_index);
    const BRepAdaptor_Surface adaptor(source, Standard_True);
    out.original = code_of(adaptor.GetType());
    out.face = source;
    if (out.original == kBSpline) {
        out.surface = Handle(Geom_BSplineSurface)::DownCast(unwrapped(BRep_Tool::Surface(source)));
    }
    if (out.surface.IsNull()) {
        BRepBuilderAPI_NurbsConvert converter(source, Standard_True);
        if (!converter.IsDone() || converter.Shape().IsNull() || converter.Shape().ShapeType() != TopAbs_FACE) {
            throw user_error("This surface couldn't be converted to a B-spline.");
        }
        out.face = TopoDS::Face(converter.Shape());
        out.surface = Handle(Geom_BSplineSurface)::DownCast(unwrapped(BRep_Tool::Surface(out.face)));
        if (out.surface.IsNull()) {
            throw user_error("This surface couldn't be converted to a B-spline.");
        }
        out.converted = true;
    }
    return out;
}

/// Copies `surface`'s net into `out`; with `normals` also the unit normal at each pole's Greville point.
void fill_net(const Handle(Geom_BSplineSurface) &surface, bool normals, bool flip, occt_surface_net &out) {
    const int nu = surface->NbUPoles();
    const int nv = surface->NbVPoles();
    out.degree_u = surface->UDegree();
    out.degree_v = surface->VDegree();
    out.u_count = nu;
    out.v_count = nv;
    out.periodic_u = surface->IsUPeriodic() ? 1 : 0;
    out.periodic_v = surface->IsVPeriodic() ? 1 : 0;
    out.rational = surface->IsURational() || surface->IsVRational() ? 1 : 0;
    out.poles = zeroed<double>(static_cast<size_t>(nu) * nv * 3);
    if (out.rational) {
        out.weights = zeroed<double>(static_cast<size_t>(nu) * nv);
    }
    for (int i = 0; i < nu; ++i) {
        for (int j = 0; j < nv; ++j) {
            const size_t at = static_cast<size_t>(i) * nv + j;
            const gp_Pnt p = surface->Pole(i + 1, j + 1);
            out.poles[3 * at] = p.X();
            out.poles[3 * at + 1] = p.Y();
            out.poles[3 * at + 2] = p.Z();
            if (out.weights) {
                out.weights[at] = surface->Weight(i + 1, j + 1);
            }
        }
    }
    out.knot_u_count = surface->NbUKnots();
    out.knot_v_count = surface->NbVKnots();
    out.knots_u = zeroed<double>(out.knot_u_count);
    out.mult_u = zeroed<int>(out.knot_u_count);
    out.knots_v = zeroed<double>(out.knot_v_count);
    out.mult_v = zeroed<int>(out.knot_v_count);
    for (int k = 0; k < out.knot_u_count; ++k) {
        out.knots_u[k] = surface->UKnot(k + 1);
        out.mult_u[k] = surface->UMultiplicity(k + 1);
    }
    for (int k = 0; k < out.knot_v_count; ++k) {
        out.knots_v[k] = surface->VKnot(k + 1);
        out.mult_v[k] = surface->VMultiplicity(k + 1);
    }
    if (!normals) {
        return;
    }
    out.normals = zeroed<double>(static_cast<size_t>(nu) * nv * 3);
    double u0, u1, v0, v1;
    surface->Bounds(u0, u1, v0, v1);
    const std::vector<double> us = greville_all(surface, true, u0, u1);
    const std::vector<double> vs = greville_all(surface, false, v0, v1);
    for (int i = 0; i < nu; ++i) {
        for (int j = 0; j < nv; ++j) {
            double n[3];
            unit_normal(surface, us[i], vs[j], flip, n);
            const size_t at = static_cast<size_t>(i) * nv + j;
            out.normals[3 * at] = n[0];
            out.normals[3 * at + 1] = n[1];
            out.normals[3 * at + 2] = n[2];
        }
    }
}


/// Whether `face` is the whole of its surface: one wire of axis-aligned straight pcurves lying on the surface's four natural
/// boundaries (a degenerate pole edge is such a side), so every point inside the surface's parameter box is on the face and
/// needs no classification. Conservative: anything else (a trim, a hole, a periodic seam) answers false.
bool is_untrimmed(const TopoDS_Face &face, const Handle(Geom_Surface) &surface) {
    if (surface.IsNull() || surface->IsUPeriodic() || surface->IsVPeriodic()) {
        return false;
    }
    double s0, s1, t0, t1;
    surface->Bounds(s0, s1, t0, t1);
    if (Precision::IsInfinite(s0) || Precision::IsInfinite(s1) || Precision::IsInfinite(t0) || Precision::IsInfinite(t1)) {
        return false;
    }
    const double tol_u = 1e-9 * std::max(1.0, std::abs(s1 - s0));
    const double tol_v = 1e-9 * std::max(1.0, std::abs(t1 - t0));
    int wires = 0;
    for (TopExp_Explorer it(face, TopAbs_WIRE); it.More(); it.Next()) {
        ++wires;
    }
    if (wires != 1) {
        return false;
    }
    bool seen[4] = {false, false, false, false}; // u = s0, u = s1, v = t0, v = t1
    int edges = 0;
    for (TopExp_Explorer it(face, TopAbs_EDGE); it.More(); it.Next()) {
        ++edges;
        const TopoDS_Edge edge = TopoDS::Edge(it.Current());
        double first, last;
        const Handle(Geom2d_Curve) curve = BRep_Tool::CurveOnSurface(edge, face, first, last);
        if (curve.IsNull()) {
            return false;
        }
        const gp_Pnt2d a = curve->Value(first);
        const gp_Pnt2d b = curve->Value(last);
        // A straight side, whatever its curve class (a rebuilt face's is a degree-1 B-spline): three sample points on one axis line.
        const gp_Pnt2d mid = curve->Value(0.5 * (first + last));
        const gp_Pnt2d quarter = curve->Value(0.75 * first + 0.25 * last);
        const bool along_v = std::abs(a.X() - b.X()) <= tol_u;
        if (along_v ? (std::abs(mid.X() - a.X()) > tol_u || std::abs(quarter.X() - a.X()) > tol_u)
                    : (std::abs(mid.Y() - a.Y()) > tol_v || std::abs(quarter.Y() - a.Y()) > tol_v)) {
            return false;
        }
        if (std::abs(a.X() - b.X()) <= tol_u) {
            if (std::abs(a.X() - s0) <= tol_u) {
                seen[0] = true;
            } else if (std::abs(a.X() - s1) <= tol_u) {
                seen[1] = true;
            } else {
                return false;
            }
        } else if (std::abs(a.Y() - b.Y()) <= tol_v) {
            if (std::abs(a.Y() - t0) <= tol_v) {
                seen[2] = true;
            } else if (std::abs(a.Y() - t1) <= tol_v) {
                seen[3] = true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }
    return edges >= 4 && seen[0] && seen[1] && seen[2] && seen[3];
}

} // namespace

namespace cocct {

TopoDS_Face edit_copy::face() const {
    occt_shape holder{work};
    return face_at(&holder, face_index);
}

edit_copy make_edit_copy(const occt_shape *shape, int face_index) {
    edit_copy out;
    out.face_index = face_index;
    BRepBuilderAPI_Copy copier(shape->shape, Standard_True, Standard_False);
    TopoDS_Shape work = copier.Shape();
    occt_shape holder{work};
    out.original = face_at(&holder, face_index);
    converted_face converted = convert_face(&holder, face_index);
    if (converted.converted) {
        // The conversion of the whole copy, so the face stays in its shell; the same conversion the net read made.
        BRepBuilderAPI_NurbsConvert whole(work, Standard_True);
        if (!whole.IsDone() || whole.Shape().IsNull()) {
            throw user_error("This surface couldn't be converted to a B-spline.");
        }
        work = whole.Shape();
        holder.shape = work;
        converted = convert_face(&holder, face_index);
        converted.converted = true;
    }
    out.work = work;
    out.surface = converted.surface;
    out.converted = converted.converted;
    return out;
}

TopoDS_Face replace_face_surface(const TopoDS_Face &given, const Handle(Geom_Surface) &surface, const TopoDS_Face &original,
                                 bool rebuilding) {
    const TopoDS_Face face = TopoDS::Face(given.Oriented(TopAbs_FORWARD));
    BRep_Builder builder;
    const double tolerance = std::max(BRep_Tool::Tolerance(face), 1e-7);

    // Everything that reads the old surface comes first: each edge's pcurve(s) on it.
    struct edge_curves {
        TopoDS_Edge edge;
        Handle(Geom2d_Curve) first;
        Handle(Geom2d_Curve) second;
        double start = 0;
        double end = 0;
        bool rebuild = false; // the old 3D curve no longer lies on the new surface
        Handle(Geom_Curve) reinstated; // the original's curve, put back when it fits and the converted one doesn't
        double reinstated_first = 0;
        double reinstated_last = 0;
    };
    std::vector<edge_curves> edges;
    const Handle(Geom_Surface) old_surface = BRep_Tool::Surface(face);
    const TopTools_IndexedMapOfShape edge_map = map_of(face, TopAbs_EDGE);
    for (int k = 1; k <= edge_map.Extent(); ++k) {
        edge_curves entry;
        entry.edge = TopoDS::Edge(edge_map(k).Oriented(TopAbs_FORWARD));
        entry.first = BRep_Tool::CurveOnSurface(entry.edge, face, entry.start, entry.end);
        if (entry.first.IsNull()) {
            throw user_error("A face's edge has no curve on its surface.");
        }
        if (BRep_Tool::IsClosed(entry.edge, face)) {
            double s = 0;
            double e = 0;
            entry.second = BRep_Tool::CurveOnSurface(TopoDS::Edge(entry.edge.Oriented(TopAbs_REVERSED)), face, s, e);
        }
        edges.push_back(entry);
    }

    // An edge whose 3D curve still lies on the new surface (a straight edge of a plane the move left alone) is kept as it is, so
    // lines and circles stay lines and circles. The others are rebuilt from their pcurves.
    TopTools_IndexedMapOfShape original_edges;
    if (!original.IsNull()) {
        original_edges = map_of(original, TopAbs_EDGE);
        if (original_edges.Extent() != static_cast<int>(edges.size())) {
            original_edges.Clear();
        }
    }
    // An edge's own old 3D curve is kept when, at nine equal fractions of its parameter range, it passes through the pcurve's points
    // on the new surface.
    const auto lies_on = [&](const Handle(Geom_Curve) &curve, double first, double last, const edge_curves &entry) {
        if (curve.IsNull()) {
            return false;
        }
        for (int k = 0; k <= 8; ++k) {
            const double w = k / 8.0;
            const gp_Pnt2d uv = entry.first->Value(entry.start + (entry.end - entry.start) * w);
            if (curve->Value(first + (last - first) * w).Distance(surface->Value(uv.X(), uv.Y())) > 1e-7) {
                return false;
            }
        }
        return true;
    };
    // The original's line or circle, put back for a converted face: its parameter isn't the converted pcurve's (a rational pcurve is
    // not linear in a circle's angle), so nine points of the pcurve on the new surface must lie on the curve (the nearest point
    // within its range) and its ends must be the pcurve's ends.
    const auto lies_along = [&](const Handle(Geom_Curve) &curve, double first, double last, const edge_curves &entry) {
        if (curve.IsNull()) {
            return false;
        }
        const gp_Pnt2d start = entry.first->Value(entry.start);
        const gp_Pnt2d end = entry.first->Value(entry.end);
        if (curve->Value(first).Distance(surface->Value(start.X(), start.Y())) > 1e-7 ||
            curve->Value(last).Distance(surface->Value(end.X(), end.Y())) > 1e-7) {
            return false;
        }
        for (int k = 0; k <= 8; ++k) {
            const double w = k / 8.0;
            const gp_Pnt2d uv = entry.first->Value(entry.start + (entry.end - entry.start) * w);
            const gp_Pnt point = surface->Value(uv.X(), uv.Y());
            GeomAPI_ProjectPointOnCurve projection(point, curve, first, last);
            // The projection finds interior stationary points only, so the range's ends are tried too.
            double nearest = std::min(point.Distance(curve->Value(first)), point.Distance(curve->Value(last)));
            if (projection.NbPoints() >= 1) {
                nearest = std::min(nearest, projection.LowerDistance());
            }
            if (nearest > 1e-7) {
                return false;
            }
        }
        return true;
    };
    for (size_t k = 0; k < edges.size(); ++k) {
        edge_curves &entry = edges[k];
        if (BRep_Tool::Degenerated(entry.edge)) {
            continue;
        }
        // The original's curve first, since it is the exact line or circle the conversion made a B-spline of.
        if (original_edges.Extent() > 0) {
            const TopoDS_Edge source = TopoDS::Edge(original_edges(static_cast<int>(k) + 1));
            double source_first = 0;
            double source_last = 0;
            const Handle(Geom_Curve) source_curve = BRep_Tool::Curve(source, source_first, source_last);
            if (lies_along(source_curve, source_first, source_last, entry)) {
                entry.reinstated = source_curve;
                entry.reinstated_first = source_first;
                entry.reinstated_last = source_last;
                continue;
            }
        }
        double first = 0;
        double last = 0;
        const Handle(Geom_Curve) old_curve = BRep_Tool::Curve(entry.edge, first, last);
        if (lies_on(old_curve, first, last, entry)) {
            continue;
        }
        entry.rebuild = true;
    }

    // A degenerated edge (an apex) must still map to one point and a seam's two pcurves to one curve, whatever the poles did: the
    // topology says "closed" either way, and BRepCheck is lenient. 0 closed, 1 apex open, 2 seam open (at nine samples, 1e-6 mm).
    const auto opening = [&](const Handle(Geom_Surface) &on) {
        if (on.IsNull()) {
            return 0;
        }
        int found = 0;
        for (const edge_curves &entry : edges) {
            const bool degenerate = BRep_Tool::Degenerated(entry.edge);
            if (!degenerate && entry.second.IsNull()) {
                continue;
            }
            const gp_Pnt2d a0 = entry.first->Value(entry.start);
            const gp_Pnt anchor = on->Value(a0.X(), a0.Y());
            for (int k = 0; k <= 8; ++k) {
                const double t = entry.start + (entry.end - entry.start) * k / 8.0;
                const gp_Pnt2d uv = entry.first->Value(t);
                const gp_Pnt point = on->Value(uv.X(), uv.Y());
                if (degenerate) {
                    if (point.Distance(anchor) > 1e-6) {
                        found = std::max(found, 1);
                    }
                } else {
                    const gp_Pnt2d other = entry.second->Value(t);
                    if (point.Distance(on->Value(other.X(), other.Y())) > 1e-6) {
                        found = std::max(found, 2);
                    }
                }
            }
        }
        return found;
    };
    const int was_open = opening(old_surface);
    const int now_open = opening(surface);
    if (now_open != 0 && was_open == 0) {
        const std::string what = now_open == 1 ? "at its apex" : "along its seam";
        throw user_error(rebuilding ? "Rebuilding opens the surface " + what + "."
                                    : "Moving these control points opens the surface " + what +
                                          "; move the matching points together.");
    }

    builder.UpdateFace(face, surface, TopLoc_Location(), tolerance);
    for (const edge_curves &entry : edges) {
        if (entry.second.IsNull()) {
            builder.UpdateEdge(entry.edge, entry.first, face, tolerance);
        } else {
            builder.UpdateEdge(entry.edge, entry.first, entry.second, face, tolerance);
        }
        builder.Range(entry.edge, face, entry.start, entry.end);
    }
    BRepTools::RemoveUnusedPCurves(face);

    // Every vertex goes where its edge's pcurve now lands on the new surface.
    for (const edge_curves &entry : edges) {
        const TopoDS_Vertex first = TopExp::FirstVertex(entry.edge, Standard_True);
        const TopoDS_Vertex last = TopExp::LastVertex(entry.edge, Standard_True);
        const gp_Pnt2d a = entry.first->Value(entry.start);
        const gp_Pnt2d b = entry.first->Value(entry.end);
        if (!first.IsNull()) {
            builder.UpdateVertex(first, surface->Value(a.X(), a.Y()), 1e-7);
        }
        if (!last.IsNull()) {
            builder.UpdateVertex(last, surface->Value(b.X(), b.Y()), 1e-7);
        }
    }
    for (const edge_curves &entry : edges) {
        if (!entry.reinstated.IsNull()) {
            builder.UpdateEdge(entry.edge, entry.reinstated, TopLoc_Location(), 1e-7);
            // Only the 3D range: the pcurve's own range stays.
            builder.Range(entry.edge, entry.reinstated_first, entry.reinstated_last, Standard_True);
            BRepLib::SameParameter(entry.edge, 1e-6, Standard_True);
            continue;
        }
        if (!entry.rebuild) {
            continue;
        }
        builder.UpdateEdge(entry.edge, Handle(Geom_Curve)(), 0.0);
        if (!BRepLib::BuildCurve3d(entry.edge, 1e-6, GeomAbs_C0, 14, 60)) {
            throw user_error("The edges couldn't be rebuilt on the new surface.");
        }
        BRepLib::SameParameter(entry.edge, 1e-6, Standard_True);
    }
    BRepLib::UpdateTolerances(face);
    return TopoDS::Face(face.Oriented(given.Orientation()));
}

} // namespace cocct

extern "C" {

int occt_control_net_of_face(const occt_shape *shape, int face_index, int max_poles, occt_surface_net *out,
                             occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        *out = occt_surface_net{};
        const converted_face converted = convert_face(shape, face_index);
        const Handle(Geom_BSplineSurface) &surface = converted.surface;
        out->converted_from = converted.converted ? converted.original : -1;
        const int degree = std::max(surface->UDegree(), surface->VDegree());
        if (degree > kMaxDegree) {
            throw user_error("Edit Surface works on degree 1 to " + number(kMaxDegree) + "; this surface is degree " +
                             number(degree) + ". Rebuild it first.");
        }
        const double count = static_cast<double>(surface->NbUPoles()) * surface->NbVPoles();
        if (max_poles > 0 && count > max_poles) {
            throw user_error("This surface has " + number(count) + " control points; Edit Surface works on at most " +
                             number(max_poles) + ".");
        }
        out->kind = converted.original;
        fill_net(surface, true, converted.face.Orientation() == TopAbs_REVERSED, *out);
        return 1;
    });
}

occt_shape *occt_move_face_poles(const occt_shape *shape, int face_index, const int *indices, const double *offsets, int count,
                                 occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!shape || shape->shape.IsNull() || !indices || !offsets || count < 0) {
            throw user_error("That surface no longer exists.");
        }
        face_at(shape, face_index);
        const bool input_valid = BRepCheck_Analyzer(shape->shape).IsValid();
        // Geometry is copied, so no surface another solid shares is changed.
        edit_copy edit = make_edit_copy(shape, face_index);
        const Handle(Geom_BSplineSurface) moved = Handle(Geom_BSplineSurface)::DownCast(edit.surface->Copy());
        const int nu = moved->NbUPoles();
        const int nv = moved->NbVPoles();
        for (int k = 0; k < count; ++k) {
            if (!std::isfinite(offsets[3 * k]) || !std::isfinite(offsets[3 * k + 1]) || !std::isfinite(offsets[3 * k + 2])) {
                throw user_error("Moving these control points makes an invalid surface.");
            }
            const int i = indices[2 * k];
            const int j = indices[2 * k + 1];
            if (i < 0 || i >= nu || j < 0 || j >= nv) {
                throw user_error("That control point no longer exists.");
            }
            const gp_Pnt pole = moved->Pole(i + 1, j + 1);
            const gp_Pnt target(pole.X() + offsets[3 * k], pole.Y() + offsets[3 * k + 1], pole.Z() + offsets[3 * k + 2]);
            if (!std::isfinite(target.X()) || !std::isfinite(target.Y()) || !std::isfinite(target.Z())) {
                throw user_error("Moving these control points makes an invalid surface.");
            }
            moved->SetPole(i + 1, j + 1, target);
        }
        replace_face_surface(edit.face(), moved, edit.converted ? edit.original : TopoDS_Face());
        if (input_valid && !BRepCheck_Analyzer(edit.work).IsValid()) {
            throw user_error("Moving these control points makes an invalid surface.");
        }
        return new occt_shape{edit.work};
    });
}

int occt_same_structure(const occt_shape *a, const occt_shape *b, occt_status *status) {
    return guarded(status, [&]() -> int {
        if (!a || !b) {
            return 0;
        }
        const TopTools_IndexedMapOfShape faces_a = map_of(a->shape, TopAbs_FACE);
        const TopTools_IndexedMapOfShape faces_b = map_of(b->shape, TopAbs_FACE);
        const TopTools_IndexedMapOfShape edges_a = map_of(a->shape, TopAbs_EDGE);
        const TopTools_IndexedMapOfShape edges_b = map_of(b->shape, TopAbs_EDGE);
        const TopTools_IndexedMapOfShape vertices_a = map_of(a->shape, TopAbs_VERTEX);
        const TopTools_IndexedMapOfShape vertices_b = map_of(b->shape, TopAbs_VERTEX);
        if (faces_a.Extent() != faces_b.Extent() || edges_a.Extent() != edges_b.Extent() ||
            vertices_a.Extent() != vertices_b.Extent()) {
            return 0;
        }
        for (int k = 1; k <= edges_a.Extent(); ++k) {
            const TopoDS_Edge ea = TopoDS::Edge(edges_a(k));
            const TopoDS_Edge eb = TopoDS::Edge(edges_b(k));
            const int a0 = vertices_a.FindIndex(TopExp::FirstVertex(ea, Standard_True));
            const int a1 = vertices_a.FindIndex(TopExp::LastVertex(ea, Standard_True));
            const int b0 = vertices_b.FindIndex(TopExp::FirstVertex(eb, Standard_True));
            const int b1 = vertices_b.FindIndex(TopExp::LastVertex(eb, Standard_True));
            if (a0 != b0 || a1 != b1 || BRep_Tool::Degenerated(ea) != BRep_Tool::Degenerated(eb)) {
                return 0;
            }
        }
        for (int f = 1; f <= faces_a.Extent(); ++f) {
            std::vector<int> list_a;
            std::vector<int> list_b;
            for (TopExp_Explorer it(faces_a(f), TopAbs_EDGE); it.More(); it.Next()) {
                list_a.push_back(edges_a.FindIndex(it.Current()));
            }
            for (TopExp_Explorer it(faces_b(f), TopAbs_EDGE); it.More(); it.Next()) {
                list_b.push_back(edges_b.FindIndex(it.Current()));
            }
            if (list_a != list_b) {
                return 0;
            }
        }
        return 1;
    });
}

int occt_surface_folds(const occt_shape *shape, int face_index, int *folds, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        const TopoDS_Face face = face_at(shape, face_index);
        const Handle(Geom_Surface) surface = BRep_Tool::Surface(face);
        if (surface.IsNull()) {
            throw user_error("That face has no surface.");
        }
        double u0, u1, v0, v1;
        BRepTools::UVBounds(face, u0, u1, v0, v1);
        Bnd_Box box;
        BRepBndLib::Add(face, box);
        double x0, y0, z0, x1, y1, z1;
        box.Get(x0, y0, z0, x1, y1, z1);
        const double size = std::max({x1 - x0, y1 - y0, z1 - z0, 1e-9});
        const double tiny = 1e-12 * size * size;
        std::vector<gp_Pnt> degenerate_points;
        for (TopExp_Explorer it(face, TopAbs_EDGE); it.More(); it.Next()) {
            const TopoDS_Edge edge = TopoDS::Edge(it.Current());
            if (BRep_Tool::Degenerated(edge)) {
                degenerate_points.push_back(BRep_Tool::Pnt(TopExp::FirstVertex(edge)));
            }
        }
        // Samples sit inside each knot span (cell centred), and only neighbours of one span are compared: across an interior knot a
        // surface may have a sharp crease that is not a fold; inside a span it is smooth, so opposite normals there are a fold.
        struct line_sample {
            double parameter;
            int span;
        };
        const Handle(Geom_BSplineSurface) spline = Handle(Geom_BSplineSurface)::DownCast(unwrapped(surface));
        auto spans_of = [](const Handle(Geom_BSplineSurface) &s, bool is_u, double lo, double hi) {
            std::vector<double> cuts{lo};
            if (!s.IsNull()) {
                const int count = is_u ? s->NbUKnots() : s->NbVKnots();
                for (int k = 1; k <= count; ++k) {
                    const double knot = is_u ? s->UKnot(k) : s->VKnot(k);
                    if (knot > lo + 1e-12 * (hi - lo) && knot < hi - 1e-12 * (hi - lo)) {
                        cuts.push_back(knot);
                    }
                }
            }
            cuts.push_back(hi);
            return cuts;
        };
        const std::vector<double> cuts_u = spans_of(spline, true, u0, u1);
        const std::vector<double> cuts_v = spans_of(spline, false, v0, v1);
        const double span_count = double(cuts_u.size() - 1) * double(cuts_v.size() - 1);
        int per_span = 8;
        while (per_span > 1 && span_count * per_span * per_span > 1.0e6) {
            --per_span;
        }
        auto lines_of = [per_span](const std::vector<double> &cuts) {
            std::vector<line_sample> lines;
            for (size_t k = 0; k + 1 < cuts.size(); ++k) {
                for (int i = 0; i < per_span; ++i) {
                    lines.push_back({cuts[k] + (cuts[k + 1] - cuts[k]) * (i + 0.5) / per_span, int(k)});
                }
            }
            return lines;
        };
        const std::vector<line_sample> lines_u = lines_of(cuts_u);
        const std::vector<line_sample> lines_v = lines_of(cuts_v);
        const int count_u = int(lines_u.size());
        const int count_v = int(lines_v.size());
        BRepClass_FaceClassifier classifier;
        // An untrimmed face holds every point of its parameter box, so nothing is classified (the box's sides are the face's).
        const bool untrimmed = is_untrimmed(face, surface);
        struct sample {
            bool inside = false;
            bool ignored = false;
            bool degenerate = false;
            gp_Vec normal;
        };
        std::vector<sample> grid(size_t(count_u) * size_t(count_v));
        for (int a = 0; a < count_u; ++a) {
            for (int b = 0; b < count_v; ++b) {
                sample &out = grid[size_t(a) * count_v + b];
                const double u = lines_u[a].parameter;
                const double v = lines_v[b].parameter;
                if (untrimmed) {
                    out.inside = true;
                } else {
                    classifier.Perform(face, gp_Pnt2d(u, v), 1e-7);
                    out.inside = classifier.State() == TopAbs_IN || classifier.State() == TopAbs_ON;
                }
                if (!out.inside) {
                    continue;
                }
                gp_Pnt point;
                gp_Vec du, dv;
                surface->D1(u, v, point, du, dv);
                for (const gp_Pnt &pole : degenerate_points) {
                    out.ignored = out.ignored || point.Distance(pole) <= 1e-6 * size;
                }
                const gp_Vec n = du.Crossed(dv);
                out.degenerate = n.Magnitude() < tiny;
                out.normal = out.degenerate ? gp_Vec() : n.Normalized();
            }
        }
        *folds = 0;
        for (int a = 0; a < count_u && !*folds; ++a) {
            for (int b = 0; b < count_v && !*folds; ++b) {
                const sample &here = grid[size_t(a) * count_v + b];
                if (!here.inside || here.ignored) {
                    continue;
                }
                for (int direction = 0; direction < 2; ++direction) {
                    const int na = a + (direction == 0 ? 1 : 0);
                    const int nb = b + (direction == 1 ? 1 : 0);
                    if (na >= count_u || nb >= count_v) {
                        continue;
                    }
                    if (lines_u[na].span != lines_u[a].span || lines_v[nb].span != lines_v[b].span) {
                        continue;
                    }
                    const sample &next = grid[size_t(na) * count_v + nb];
                    if (!next.inside || next.ignored) {
                        continue;
                    }
                    if (here.degenerate != next.degenerate) {
                        *folds = 1;
                    } else if (!here.degenerate && here.normal.Dot(next.normal) < 0) {
                        *folds = 1;
                    }
                }
            }
        }
        return 1;
    });
}

int occt_surface_info(const occt_shape *shape, int face_index, occt_surface_net *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        *out = occt_surface_net{};
        const TopoDS_Face face = face_at(shape, face_index);
        const BRepAdaptor_Surface adaptor(face, Standard_True);
        out->kind = code_of(adaptor.GetType());
        out->converted_from = -1;
        const Handle(Geom_Surface) surface = unwrapped(BRep_Tool::Surface(face));
        if (out->kind == kBSpline) {
            Handle(Geom_BSplineSurface) spline = Handle(Geom_BSplineSurface)::DownCast(surface);
            if (!spline.IsNull()) {
                fill_net(spline, false, false, *out);
            }
        } else if (out->kind == kBezier) {
            Handle(Geom_BezierSurface) bezier = Handle(Geom_BezierSurface)::DownCast(surface);
            if (!bezier.IsNull()) {
                fill_net(GeomConvert::SurfaceToBSplineSurface(bezier), false, false, *out);
            }
        }
        return 1;
    });
}

void occt_surface_net_free(occt_surface_net *net) {
    if (net) {
        std::free(net->poles);
        std::free(net->weights);
        std::free(net->knots_u);
        std::free(net->knots_v);
        std::free(net->normals);
        std::free(net->mult_u);
        std::free(net->mult_v);
        *net = occt_surface_net{};
    }
}

int occt_control_net_of_curve(const occt_shape *wire, occt_curve_net *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        *out = occt_curve_net{};
        if (!wire || wire->shape.IsNull() || wire->shape.ShapeType() != TopAbs_WIRE) {
            throw user_error("This isn't a curve.");
        }
        TopoDS_Edge edge;
        int pieces = 0;
        for (TopExp_Explorer explorer(wire->shape, TopAbs_EDGE); explorer.More(); explorer.Next()) {
            if (pieces == 0) {
                edge = TopoDS::Edge(explorer.Current());
            }
            ++pieces;
        }
        if (pieces != 1) {
            throw user_error("A curve of one piece is needed.");
        }
        double first = 0;
        double last = 0;
        Handle(Geom_Curve) base = BRep_Tool::Curve(edge, first, last);
        if (base.IsNull()) {
            throw user_error("This curve has no geometry.");
        }
        Handle(Geom_Curve) basis = base;
        while (true) {
            Handle(Geom_TrimmedCurve) trimmed = Handle(Geom_TrimmedCurve)::DownCast(basis);
            if (trimmed.IsNull()) {
                break;
            }
            basis = trimmed->BasisCurve();
        }
        out->converted_from = -1;
        Handle(Geom_BSplineCurve) spline = Handle(Geom_BSplineCurve)::DownCast(basis);
        if (!spline.IsNull()) {
            spline = Handle(Geom_BSplineCurve)::DownCast(spline->Copy());
            const double slack = 1e-9 * (1.0 + std::abs(spline->LastParameter() - spline->FirstParameter()));
            const bool whole = std::abs(first - spline->FirstParameter()) <= slack &&
                               std::abs(last - spline->LastParameter()) <= slack;
            if (!whole) {
                if (spline->IsPeriodic()) {
                    spline->SetNotPeriodic();
                }
                spline->Segment(first, last);
            }
        } else {
            out->converted_from = !Handle(Geom_Line)::DownCast(basis).IsNull()     ? 0
                                  : !Handle(Geom_Circle)::DownCast(basis).IsNull() ? 1
                                                                                   : 2;
            const Handle(Geom_TrimmedCurve) trimmed = new Geom_TrimmedCurve(basis, first, last);
            spline = GeomConvert::CurveToBSplineCurve(trimmed);
        }
        if (spline.IsNull()) {
            throw user_error("This curve couldn't be converted to a B-spline.");
        }
        out->periodic = spline->IsPeriodic() ? 1 : 0;
        if (edge.Orientation() == TopAbs_REVERSED) {
            spline->Reverse();
        }
        if (spline->Degree() > kMaxDegree) {
            throw user_error("Edit Curve works on degree 1 to " + number(kMaxDegree) + "; this curve is degree " +
                             number(spline->Degree()) + ". Rebuild it first.");
        }
        const int n = spline->NbPoles();
        out->degree = spline->Degree();
        out->pole_count = n;
        out->poles = zeroed<double>(static_cast<size_t>(n) * 3);
        out->rational = spline->IsRational() ? 1 : 0;
        if (out->rational) {
            out->weights = zeroed<double>(n);
        }
        for (int i = 0; i < n; ++i) {
            const gp_Pnt p = spline->Pole(i + 1);
            out->poles[3 * i] = p.X();
            out->poles[3 * i + 1] = p.Y();
            out->poles[3 * i + 2] = p.Z();
            if (out->weights) {
                out->weights[i] = spline->Weight(i + 1);
            }
        }
        out->knot_count = spline->NbKnots();
        out->knots = zeroed<double>(out->knot_count);
        out->multiplicities = zeroed<int>(out->knot_count);
        for (int k = 0; k < out->knot_count; ++k) {
            out->knots[k] = spline->Knot(k + 1);
            out->multiplicities[k] = spline->Multiplicity(k + 1);
        }
        return 1;
    });
}

void occt_curve_net_free(occt_curve_net *net) {
    if (net) {
        std::free(net->poles);
        std::free(net->weights);
        std::free(net->knots);
        std::free(net->multiplicities);
        *net = occt_curve_net{};
    }
}

int occt_test_net_gaps(const occt_shape *shape, int face_index, double *normal_error, double *pole_gap, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        const converted_face converted = convert_face(shape, face_index);
        const Handle(Geom_BSplineSurface) &surface = converted.surface;
        const bool flip = converted.face.Orientation() == TopAbs_REVERSED;
        double u0, u1, v0, v1;
        surface->Bounds(u0, u1, v0, v1);
        const std::vector<double> us = greville_all(surface, true, u0, u1);
        const std::vector<double> vs = greville_all(surface, false, v0, v1);
        *normal_error = 0;
        *pole_gap = 0;
        for (int i = 0; i < surface->NbUPoles(); ++i) {
            for (int j = 0; j < surface->NbVPoles(); ++j) {
                gp_Pnt point;
                gp_Vec du, dv;
                surface->D1(us[i], vs[j], point, du, dv);
                double n[3];
                unit_normal(surface, us[i], vs[j], flip, n);
                const gp_Vec normal(n[0], n[1], n[2]);
                if (du.Magnitude() > 1e-9) {
                    *normal_error = std::max(*normal_error, std::abs(normal.Dot(du)) / du.Magnitude());
                }
                if (dv.Magnitude() > 1e-9) {
                    *normal_error = std::max(*normal_error, std::abs(normal.Dot(dv)) / dv.Magnitude());
                }
                *pole_gap = std::max(*pole_gap, point.Distance(surface->Pole(i + 1, j + 1)));
            }
        }
        return 1;
    });
}

occt_shape *occt_test_reversed_copy(const occt_shape *shape, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * { return new occt_shape{shape->shape.Reversed()}; });
}

occt_shape *occt_test_bspline_sheet(int u_count, int v_count, int degree, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (degree < 1 || u_count < degree + 1 || v_count < degree + 1) {
            throw user_error("A sheet needs more poles than its degree each way.");
        }
        TColgp_Array2OfPnt poles(1, u_count, 1, v_count);
        for (int i = 1; i <= u_count; ++i) {
            for (int j = 1; j <= v_count; ++j) {
                poles(i, j) = gp_Pnt(i - 1, j - 1, 0);
            }
        }
        const int knot_u = u_count - degree + 1;
        const int knot_v = v_count - degree + 1;
        TColStd_Array1OfReal knots_u(1, knot_u);
        TColStd_Array1OfReal knots_v(1, knot_v);
        TColStd_Array1OfInteger mult_u(1, knot_u);
        TColStd_Array1OfInteger mult_v(1, knot_v);
        for (int i = 1; i <= knot_u; ++i) {
            knots_u(i) = i - 1;
            mult_u(i) = (i == 1 || i == knot_u) ? degree + 1 : 1;
        }
        for (int j = 1; j <= knot_v; ++j) {
            knots_v(j) = j - 1;
            mult_v(j) = (j == 1 || j == knot_v) ? degree + 1 : 1;
        }
        Handle(Geom_BSplineSurface) surface =
            new Geom_BSplineSurface(poles, knots_u, knots_v, mult_u, mult_v, degree, degree);
        BRepBuilderAPI_MakeFace face(surface, 1e-7);
        if (!face.IsDone()) {
            throw user_error("The sheet couldn't be made.");
        }
        return new occt_shape{face.Face()};
    });
}

} // extern "C"
