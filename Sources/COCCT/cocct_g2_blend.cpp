// SPIKE (G-b): curvature-continuous fillet strips. OpenCascade makes the circular fillet; each strip face is then
// replaced by a B-spline surface skinned from quintic G2 Hermite sections between its two spring edges.
#include "cocct_g2_section.hpp"
#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepFill_Filling.hxx>
#include <GeomAbs_Shape.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepLib.hxx>
#include <BRepTools_ReShape.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <GCPnts_AbscissaPoint.hxx>
#include <Geom2d_BSplineCurve.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Geom_BezierCurve.hxx>
#include <GeomAPI_Interpolate.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <TColGeom2d_Array1OfBSplineCurve.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColStd_HArray1OfReal.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array1OfPnt2d.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <TopoDS_Wire.hxx>
#include <TopoDS_Iterator.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pln.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <memory>

using namespace cocct;

namespace {

constexpr int kFirstSections = 9;   // cross-sections per strip to start with
constexpr int kMaxSections = 129;   // the cap: 9, 17, 33, 65, 129
constexpr int kCheckSamples = 128;  // samples per spring edge when a candidate strip is judged
constexpr int kMeasureSamples = 64;
constexpr double kEdgeTolerance = 1e-6;

gp_Vec to_vec(const g2::Vec &v) { return gp_Vec(v[0], v[1], v[2]); }
g2::Vec from_vec(const gp_Vec &v) { return {v.X(), v.Y(), v.Z()}; }
g2::Vec from_pnt(const gp_Pnt &p) { return {p.X(), p.Y(), p.Z()}; }

/// A face's geometry at the point where `edge`'s parameter is `t`, normal pointing out of the solid.
struct SurfacePoint {
    gp_Pnt p;
    gp_Vec su, sv, suu, suv, svv, n;

    /// The second derivative of a curve in the surface leaving along the unit tangent-plane vector `t`, and the
    /// normal curvature along it (signed against the outward normal).
    double normal_curvature(const gp_Vec &t) const {
        const double g11 = su.Dot(su), g12 = su.Dot(sv), g22 = sv.Dot(sv);
        const double det = g11 * g22 - g12 * g12;
        const double r1 = t.Dot(su), r2 = t.Dot(sv);
        const double a = (r1 * g22 - r2 * g12) / det;
        const double b = (r2 * g11 - r1 * g12) / det;
        const gp_Vec second = suu * (a * a) + suv * (2 * a * b) + svv * (b * b);
        return second.Dot(n) / t.SquareMagnitude();
    }
};

SurfacePoint surface_point(const TopoDS_Face &face, const TopoDS_Edge &edge, double t) {
    double first = 0, last = 0;
    const Handle(Geom2d_Curve) pc = BRep_Tool::CurveOnSurface(edge, face, first, last);
    if (pc.IsNull()) {
        throw user_error("a fillet strip's edge has no curve on its face");
    }
    const gp_Pnt2d uv = pc->Value(t);
    BRepAdaptor_Surface surface(face, Standard_False);
    SurfacePoint s;
    surface.D2(uv.X(), uv.Y(), s.p, s.su, s.sv, s.suu, s.svv, s.suv);
    s.n = s.su.Crossed(s.sv);
    if (s.n.Magnitude() < 1e-12) {
        throw user_error("a fillet strip's neighbour has no normal at its edge");
    }
    s.n.Normalize();
    if (face.Orientation() == TopAbs_REVERSED) {
        s.n.Reverse();
    }
    return s;
}

struct Spring {
    TopoDS_Edge edge;
    TopoDS_Face neighbour;
    bool flipped = false; // sampled from its last parameter to its first
};

/// The edge parameter of fraction `fraction` of the way along the spring, in the sampling direction. Sections and the
/// spring's pcurve share this one parametrization (linear in the edge parameter), so any curve works, not only the
/// lines and circles whose parameter runs with arc length.
double sample_parameter(const Spring &spring, double fraction) {
    BRepAdaptor_Curve curve(spring.edge);
    const double f = spring.flipped ? 1 - fraction : fraction;
    return curve.FirstParameter() + f * (curve.LastParameter() - curve.FirstParameter());
}

/// The neighbour's end condition across `spring`'s edge at fraction `f`: position, the unit direction of travel (into
/// the blend when `entering`, else out of it) and the acceleration, the normal curvature times the normal.
g2::EndCondition end_condition(const Spring &spring, double f, const gp_Pnt &other, bool entering) {
    const double t = sample_parameter(spring, f);
    const SurfacePoint s = surface_point(spring.neighbour, spring.edge, t);
    BRepAdaptor_Curve curve(spring.edge);
    gp_Pnt p;
    gp_Vec tangent;
    curve.D1(t, p, tangent);
    gp_Vec across = s.n.Crossed(tangent);
    if (across.Magnitude() < 1e-12) {
        throw user_error("a fillet strip's spring edge is degenerate");
    }
    across.Normalize();
    if (across.Dot(gp_Vec(s.p, other)) < 0) {
        across.Reverse();
    }
    const double kappa = s.normal_curvature(across);
    g2::EndCondition e;
    e.position = from_pnt(s.p);
    e.direction = from_vec(entering ? across : across.Reversed());
    e.acceleration = from_vec(s.n * kappa);
    return e;
}

struct BuiltStrip {
    Handle(Geom_BSplineSurface) surface;
    std::array<g2::Vec, 6> first_section{}, last_section{};
    std::vector<std::array<g2::Vec, 6>> sections;
};

BuiltStrip build_strip(const Spring &a, const Spring &b, double weight, int sections) {
    BuiltStrip built;
    built.sections.resize(sections);
    for (int j = 0; j < sections; ++j) {
        const double f = static_cast<double>(j) / (sections - 1);
        BRepAdaptor_Curve ca(a.edge), cb(b.edge);
        const gp_Pnt pa = ca.Value(sample_parameter(a, f));
        const gp_Pnt pb = cb.Value(sample_parameter(b, f));
        const g2::EndCondition e0 = end_condition(a, f, pb, true);
        const g2::EndCondition e1 = end_condition(b, f, pa, false);
        const double chord = pa.Distance(pb);
        const double theta = g2::turning_angle(e0.direction, e1.direction);
        const double d = weight * g2::circular_tangent_length(chord, theta);
        built.sections[j] = g2::quintic_poles(e0, d, e1, d);
    }
    // Skin: one cubic interpolation along the strip per pole row, all through the same parameters.
    Handle(TColStd_HArray1OfReal) params = new TColStd_HArray1OfReal(1, sections);
    for (int j = 0; j < sections; ++j) {
        params->SetValue(j + 1, static_cast<double>(j) / (sections - 1));
    }
    std::vector<Handle(Geom_BSplineCurve)> rows;
    for (int i = 0; i < 6; ++i) {
        Handle(TColgp_HArray1OfPnt) points = new TColgp_HArray1OfPnt(1, sections);
        for (int j = 0; j < sections; ++j) {
            const g2::Vec &q = built.sections[j][i];
            points->SetValue(j + 1, gp_Pnt(q[0], q[1], q[2]));
        }
        GeomAPI_Interpolate interpolate(points, params, Standard_False, 1e-9);
        interpolate.Perform();
        if (!interpolate.IsDone()) {
            throw user_error("the strip's sections could not be interpolated");
        }
        rows.push_back(interpolate.Curve());
    }
    const int count = rows[0]->NbPoles();
    TColgp_Array2OfPnt poles(1, count, 1, 6);
    for (int i = 0; i < 6; ++i) {
        if (rows[i]->NbPoles() != count) {
            throw user_error("the strip's rows disagree");
        }
        for (int k = 1; k <= count; ++k) {
            poles.SetValue(k, i + 1, rows[i]->Pole(k));
        }
    }
    TColStd_Array1OfReal uknots(1, rows[0]->NbKnots());
    TColStd_Array1OfInteger umults(1, rows[0]->NbKnots());
    rows[0]->Knots(uknots);
    rows[0]->Multiplicities(umults);
    TColStd_Array1OfReal vknots(1, 2);
    vknots.SetValue(1, 0);
    vknots.SetValue(2, 1);
    TColStd_Array1OfInteger vmults(1, 2);
    vmults.SetValue(1, 6);
    vmults.SetValue(2, 6);
    built.surface = new Geom_BSplineSurface(poles, uknots, vknots, umults, vmults, rows[0]->Degree(), 5);
    return built;
}

Handle(Geom2d_BSplineCurve) line2d(const gp_Pnt2d &from, const gp_Pnt2d &to, double first, double last) {
    TColgp_Array1OfPnt2d poles(1, 2);
    poles.SetValue(1, from);
    poles.SetValue(2, to);
    TColStd_Array1OfReal knots(1, 2);
    knots.SetValue(1, first);
    knots.SetValue(2, last);
    TColStd_Array1OfInteger mults(1, 2);
    mults.SetValue(1, 2);
    mults.SetValue(2, 2);
    return new Geom2d_BSplineCurve(poles, knots, mults, 1);
}

bool is_blend(const TopoDS_Shape &face, const std::vector<TopoDS_Face> &blend) {
    for (const TopoDS_Face &b : blend) {
        if (b.IsSame(face)) {
            return true;
        }
    }
    return false;
}

struct StripEdges {
    Spring spring[2];
    TopoDS_Edge ends[2];
    TopoDS_Face end_face[2]; // null where the end borders a blend face
};

StripEdges classify(const TopoDS_Face &strip, const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces,
                    const std::vector<TopoDS_Face> &blend) {
    StripEdges out;
    int springs = 0, ends = 0;
    for (TopExp_Explorer it(strip, TopAbs_EDGE); it.More(); it.Next()) {
        const TopoDS_Edge edge = TopoDS::Edge(it.Current());
        bool duplicate = false;
        for (int i = 0; i < springs; ++i) {
            duplicate = duplicate || out.spring[i].edge.IsSame(edge);
        }
        for (int i = 0; i < ends; ++i) {
            duplicate = duplicate || out.ends[i].IsSame(edge);
        }
        if (duplicate) {
            continue;
        }
        if (BRep_Tool::Degenerated(edge)) {
            throw user_error("a fillet strip with a degenerate edge isn't supported yet");
        }
        TopoDS_Face other;
        for (const TopoDS_Face &face : distinct_faces(edge, edge_faces)) {
            if (!face.IsSame(strip)) {
                other = face;
            }
        }
        bool spring = false;
        if (!other.IsNull() && !is_blend(other, blend)) {
            double first = 0, last = 0;
            BRep_Tool::Range(edge, first, last);
            const double mid = 0.5 * (first + last);
            const SurfacePoint a = surface_point(strip, edge, mid);
            const SurfacePoint b = surface_point(other, edge, mid);
            spring = std::abs(a.n.Dot(b.n)) > 0.99;
        }
        if (spring && springs < 2) {
            out.spring[springs].edge = edge;
            out.spring[springs].neighbour = other;
            ++springs;
        } else if (!spring && ends < 2) {
            out.ends[ends] = edge;
            if (!other.IsNull() && !is_blend(other, blend)) {
                out.end_face[ends] = other;
            }
            ++ends;
        } else {
            throw user_error("this fillet strip's edges aren't two springs and two ends");
        }
    }
    if (springs != 2 || ends != 2) {
        throw user_error("this fillet strip's edges aren't two springs and two ends");
    }
    // Sample both springs from the same end.
    BRepAdaptor_Curve ca(out.spring[0].edge), cb(out.spring[1].edge);
    const gp_Pnt a0 = ca.Value(ca.FirstParameter()), a1 = ca.Value(ca.LastParameter());
    const gp_Pnt b0 = cb.Value(cb.FirstParameter()), b1 = cb.Value(cb.LastParameter());
    out.spring[1].flipped = a0.Distance(b0) + a1.Distance(b1) > a0.Distance(b1) + a1.Distance(b0);
    return out;
}

/// Folds the gaps at one sample of a seam into `seam`; `a` and `b` are the two faces there, `tangent` the edge's.
void accumulate(occt_g2_seam &seam, const SurfacePoint &a, const SurfacePoint &b, const gp_Vec &tangent) {
    gp_Vec across = a.n.Crossed(tangent);
    across.Normalize();
    gp_Vec across_b = across - b.n * across.Dot(b.n);
    across_b.Normalize();
    const double ka = a.normal_curvature(across), kb = b.normal_curvature(across_b);
    const double gap = std::abs(ka - kb);
    const double allowed = std::max(0.01 * std::max(std::abs(ka), std::abs(kb)), 1e-4);
    seam.position = std::max(seam.position, a.p.Distance(b.p));
    const double cosine = std::clamp(a.n.Dot(b.n), -1.0, 1.0);
    seam.angle_degrees = std::max(seam.angle_degrees, std::acos(cosine) * 180 / kPi);
    seam.curvature = std::max(seam.curvature, gap);
    if (gap / allowed >= seam.curvature_ratio) {
        seam.curvature_ratio = gap / allowed;
        seam.curvature_allowed = allowed;
    }
}

/// The worst position, angle and curvature gaps along `edge` between the two faces that share it.
occt_g2_seam measure_seam(const TopoDS_Edge &edge, const TopoDS_Face &f1, const TopoDS_Face &f2) {
    occt_g2_seam seam{};
    BRepAdaptor_Curve curve(edge);
    for (int k = 0; k <= kMeasureSamples; ++k) {
        const double t = curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * k / kMeasureSamples;
        gp_Pnt p;
        gp_Vec tangent;
        curve.D1(t, p, tangent);
        accumulate(seam, surface_point(f1, edge, t), surface_point(f2, edge, t), tangent);
    }
    return seam;
}

/// The strip's gaps against one spring's neighbour, read off the candidate surface (v = 0 for the first spring, 1 for
/// the second) before any topology is built. `reversed`: the face is REVERSED, so its outward normal is the raw one's
/// opposite.
occt_g2_seam candidate_seam(const Handle(Geom_BSplineSurface) &surface, bool reversed, const Spring &spring, double v) {
    occt_g2_seam seam{};
    BRepAdaptor_Curve curve(spring.edge);
    for (int k = 0; k <= kCheckSamples; ++k) {
        const double f = static_cast<double>(k) / kCheckSamples;
        const double t = sample_parameter(spring, f);
        SurfacePoint strip;
        surface->D2(f, v, strip.p, strip.su, strip.sv, strip.suu, strip.svv, strip.suv);
        strip.n = strip.su.Crossed(strip.sv);
        strip.n.Normalize();
        if (reversed) {
            strip.n.Reverse();
        }
        gp_Pnt p;
        gp_Vec tangent;
        curve.D1(t, p, tangent);
        accumulate(seam, strip, surface_point(spring.neighbour, spring.edge, t), tangent);
    }
    return seam;
}

bool within_tolerance(const occt_g2_seam &seam) {
    // Half the promised tolerances, so the final measurement at other samples still has room.
    return seam.position <= 0.5e-4 && seam.angle_degrees <= 0.005 && seam.curvature_ratio <= 0.5;
}

} // namespace

extern "C" {

double occt_g2_tangent_length(double chord, double turning_angle) {
    return g2::circular_tangent_length(chord, turning_angle);
}

int occt_g2_section_test(const double end0[9], double len0, const double end1[9], double len1, double t, double out[9]) {
    auto read = [](const double *e) {
        g2::EndCondition c;
        c.position = {e[0], e[1], e[2]};
        c.direction = {e[3], e[4], e[5]};
        c.acceleration = {e[6], e[7], e[8]};
        return c;
    };
    const auto poles = g2::quintic_poles(read(end0), len0, read(end1), len1);
    g2::Vec p, d1, d2;
    g2::evaluate(poles, t, p, d1, d2);
    for (int i = 0; i < 3; ++i) {
        out[i] = p[i];
        out[3 + i] = d1[i];
        out[6 + i] = d2[i];
    }
    return 1;
}

occt_shape *occt_fillet_g2(const occt_shape *shape, const int *edge_indices, int count, double radius, double weight,
                           occt_history *history, occt_g2_report *report, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        *report = occt_g2_report{};
        if (!shape || !edge_indices || count <= 0 || !std::isfinite(radius) || radius <= 0) {
            set_error(status, "a blend needs edges and a size greater than 0");
            return nullptr;
        }
        const TopTools_IndexedMapOfShape input_edges = map_of(shape->shape, TopAbs_EDGE);
        BRepFilletAPI_MakeFillet algo(shape->shape);
        for (int i = 0; i < count; ++i) {
            if (edge_indices[i] < 1 || edge_indices[i] > input_edges.Extent()) {
                set_error(status, "edge index out of range");
                return nullptr;
            }
            algo.Add(radius, TopoDS::Edge(input_edges(edge_indices[i])));
        }
        algo.Build();
        if (!algo.IsDone()) {
            set_error(status, "the fillet could not be built for this radius");
            return nullptr;
        }
        const TopoDS_Shape g1 = algo.Shape();

        // History against the circular result; a face keeps its index through the copy and the replacements.
        history_builder records(g1);
        {
            const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
            for (int j = 1; j <= faces.Extent(); ++j) {
                const TopoDS_Shape &face = faces(j);
                if (algo.IsDeleted(face)) {
                    continue;
                }
                const TopTools_ListOfShape &modified = algo.Modified(face);
                if (modified.IsEmpty()) {
                    records.add(face, OCCT_FROM_FACE, 0, j);
                } else {
                    records.add_all(modified, OCCT_FROM_FACE, 0, j);
                }
            }
        }
        std::vector<int> strip_indices, corner_indices;
        const TopTools_IndexedMapOfShape g1_faces = map_of(g1, TopAbs_FACE);
        for (int i = 0; i < count; ++i) {
            const TopoDS_Edge edge = TopoDS::Edge(input_edges(edge_indices[i]));
            records.add_all(algo.Generated(edge), OCCT_FROM_EDGE, 0, edge_indices[i]);
            for (TopTools_ListOfShape::Iterator it(algo.Generated(edge)); it.More(); it.Next()) {
                strip_indices.push_back(g1_faces.FindIndex(it.Value()));
            }
            TopoDS_Vertex first, last;
            TopExp::Vertices(edge, first, last);
            for (const TopoDS_Vertex &vertex : {first, last}) {
                if (!vertex.IsNull()) {
                    records.add_all(algo.Generated(vertex), OCCT_FROM_EDGE, 0, edge_indices[i]);
                    for (TopTools_ListOfShape::Iterator it(algo.Generated(vertex)); it.More(); it.Next()) {
                        corner_indices.push_back(g1_faces.FindIndex(it.Value()));
                    }
                }
            }
        }
        records.move_into(history);

        BRepBuilderAPI_Copy copy(g1, Standard_True, Standard_False);
        const TopoDS_Shape work = copy.Shape();
        const TopTools_IndexedMapOfShape faces = map_of(work, TopAbs_FACE);
        if (faces.Extent() != g1_faces.Extent()) {
            throw user_error("the copy of the fillet has a different face count");
        }
        std::sort(strip_indices.begin(), strip_indices.end());
        strip_indices.erase(std::unique(strip_indices.begin(), strip_indices.end()), strip_indices.end());
        std::sort(corner_indices.begin(), corner_indices.end());
        corner_indices.erase(std::unique(corner_indices.begin(), corner_indices.end()), corner_indices.end());
        std::vector<TopoDS_Face> blend_faces;
        for (int index : strip_indices) {
            blend_faces.push_back(TopoDS::Face(faces(index)));
        }
        for (int index : corner_indices) {
            blend_faces.push_back(TopoDS::Face(faces(index)));
        }
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(work, TopAbs_EDGE, TopAbs_FACE, edge_faces);

        TopoDS_Shape result = work;
        BRep_Builder builder;
        BRepTools_ReShape reshape;
        std::vector<StripEdges> strips;
        for (int index : strip_indices) {
            strips.push_back(classify(TopoDS::Face(faces(index)), edge_faces, blend_faces));
        }
        std::vector<std::pair<TopoDS_Edge, TopoDS_Edge>> replaced_edges;
        // SPIKE ONLY: a weight <= 0 keeps the circular strips and just measures them (the baseline). Task 3 removes it.
        if (weight > 0) {
            for (std::size_t s = 0; s < strips.size(); ++s) {
                const TopoDS_Face old_face = TopoDS::Face(faces(strip_indices[s]));
                StripEdges &edges = strips[s];
                BuiltStrip built;
                bool swapped = false;
                // Sections are doubled (9, 17, 33, ...) until the candidate's seams pass; the cap fails the blend.
                int sections = kFirstSections;
                for (;; sections = 2 * sections - 1) {
                    swapped = false;
                    for (int attempt = 0; attempt < 2; ++attempt) {
                        built = build_strip(edges.spring[swapped ? 1 : 0], edges.spring[swapped ? 0 : 1], weight, sections);
                        // The raw normal must agree with the old surface's so the face keeps its orientation.
                        gp_Pnt mid;
                        gp_Vec du, dv;
                        built.surface->D1(0.5, 0.5, mid, du, dv);
                        GeomAPI_ProjectPointOnSurf project(mid, BRep_Tool::Surface(old_face));
                        double u = 0, v = 0;
                        project.LowerDistanceParameters(u, v);
                        gp_Pnt q;
                        gp_Vec ou, ov;
                        BRep_Tool::Surface(old_face)->D1(u, v, q, ou, ov);
                        if (du.Crossed(dv).Dot(ou.Crossed(ov)) > 0) {
                            break;
                        }
                        swapped = !swapped;
                    }
                    const bool reversed = old_face.Orientation() == TopAbs_REVERSED;
                    if (within_tolerance(candidate_seam(built.surface, reversed, edges.spring[swapped ? 1 : 0], 0)) &&
                        within_tolerance(candidate_seam(built.surface, reversed, edges.spring[swapped ? 0 : 1], 1))) {
                        break;
                    }
                    if (sections >= kMaxSections) {
                        throw user_error("The fillet can't be made curvature continuous at this radius.");
                    }
                }
                report->sections = std::max(report->sections, sections);
                if (s < 32) {
                    report->strip_sections[s] = sections;
                }
                // Spring edges: a pcurve on the new surface, linear in the edge parameter.
                const Handle(Geom_Surface) surface = built.surface;
                for (int side = 0; side < 2; ++side) {
                    const Spring &spring = edges.spring[(side == 0) != swapped ? 0 : 1];
                    double f = 0, l = 0;
                    BRep_Tool::Range(spring.edge, f, l);
                    const double v = side;
                    const Handle(Geom2d_BSplineCurve) line = spring.flipped ? line2d(gp_Pnt2d(1, v), gp_Pnt2d(0, v), f, l)
                                                                            : line2d(gp_Pnt2d(0, v), gp_Pnt2d(1, v), f, l);
                    builder.UpdateEdge(spring.edge, line, surface, TopLoc_Location(), kEdgeTolerance);
                }

                // End edges become the first and last sections.
                const int count_u = built.surface->NbUPoles();
                TopoDS_Edge new_ends[2];
                for (int end = 0; end < 2; ++end) {
                    TColgp_Array1OfPnt poles(1, 6);
                    for (int i = 0; i < 6; ++i) {
                        poles.SetValue(i + 1, built.surface->Pole(end == 0 ? 1 : count_u, i + 1));
                    }
                    // Match the end edges to the section ends by position.
                    Handle(Geom_BezierCurve) bezier = new Geom_BezierCurve(poles);
                    // Which old end edge is at this section: the one whose midpoint is nearer.
                    int chosen = 0;
                    {
                        const gp_Pnt target = bezier->Value(0.5);
                        double best = 1e300;
                        for (int c = 0; c < 2; ++c) {
                            BRepAdaptor_Curve oc(edges.ends[c]);
                            const double d = oc.Value(0.5 * (oc.FirstParameter() + oc.LastParameter())).Distance(target);
                            if (d < best) {
                                best = d;
                                chosen = c;
                            }
                        }
                    }
                    const TopoDS_Edge old_edge = edges.ends[chosen];
                    TopoDS_Vertex v1, v2;
                    TopExp::Vertices(old_edge, v1, v2, Standard_False);
                    const gp_Pnt p_first = BRep_Tool::Pnt(v1);
                    const bool reversed = bezier->Value(0).Distance(p_first) > bezier->Value(1).Distance(p_first);
                    Handle(Geom_BezierCurve) curve = bezier;
                    if (reversed) {
                        curve = Handle(Geom_BezierCurve)::DownCast(bezier->Reversed());
                    }
                    TopoDS_Edge ne;
                    builder.MakeEdge(ne, curve, kEdgeTolerance);
                    builder.Add(ne, v1.Oriented(TopAbs_FORWARD));
                    builder.Add(ne, v2.Oriented(TopAbs_REVERSED));
                    builder.Range(ne, 0, 1);
                    const double u_iso = end;
                    // Section poles run from the first spring (v = 0) to the second (v = 1).
                    const Handle(Geom2d_BSplineCurve) pcs = reversed ? line2d(gp_Pnt2d(u_iso, 1), gp_Pnt2d(u_iso, 0), 0, 1)
                                                                       : line2d(gp_Pnt2d(u_iso, 0), gp_Pnt2d(u_iso, 1), 0, 1);
                    builder.UpdateEdge(ne, pcs, surface, TopLoc_Location(), kEdgeTolerance);
                    if (!edges.end_face[chosen].IsNull()) {
                        if (BRepAdaptor_Surface(edges.end_face[chosen], Standard_False).GetType() != GeomAbs_Plane) {
                            throw user_error("a curvature-continuous fillet can't end on a curved face yet");
                        }
                        BRepLib::BuildPCurveForEdgeOnPlane(ne, edges.end_face[chosen]);
                    }
                    new_ends[chosen] = ne;
                    // The replacement carries the old occurrence's orientation: Replace composes the two.
                    reshape.Replace(old_edge, ne.Oriented(old_edge.Orientation()));
                    replaced_edges.emplace_back(old_edge, ne);
                }

                // The new face: the old wire rebuilt with the new end edges.
                TopoDS_Face new_face;
                builder.MakeFace(new_face, surface, kEdgeTolerance);
                // TopoDS_Builder::Add compensates for the container's orientation, so the containers stay
                // FORWARD while they are filled and take the old orientations afterwards.
                for (TopoDS_Iterator wires(old_face, Standard_False); wires.More(); wires.Next()) {
                    TopoDS_Wire new_wire;
                    builder.MakeWire(new_wire);
                    for (TopoDS_Iterator it(wires.Value(), Standard_False); it.More(); it.Next()) {
                        TopoDS_Shape e = it.Value();
                        for (int c = 0; c < 2; ++c) {
                            if (e.IsSame(edges.ends[c])) {
                                e = new_ends[c].Oriented(it.Value().Orientation());
                            }
                        }
                        builder.Add(new_wire, e);
                    }
                    new_wire.Orientation(wires.Value().Orientation());
                    builder.Add(new_face, new_wire);
                }
                new_face.Orientation(old_face.Orientation());
                reshape.Replace(old_face, new_face);
                ++report->strips;
            }
            // Corner patches: a G0 refill between the new end curves, tangent to nothing. Task 2 replaces it with a
            // G2 refill, else a G1 one with a warning, else a failure; never a crease.
            for (int index : corner_indices) {
                const TopoDS_Face old_corner = TopoDS::Face(faces(index));
                BRepFill_Filling fill(5, 30, 5, Standard_False, 1e-6, 1e-6, 0.01, 0.1, 12, 20);
                for (TopExp_Explorer it(old_corner, TopAbs_EDGE); it.More(); it.Next()) {
                    TopoDS_Edge e = TopoDS::Edge(it.Current());
                    if (BRep_Tool::Degenerated(e)) {
                        continue; // the sphere's pole
                    }
                    for (const auto &pair : replaced_edges) {
                        if (pair.first.IsSame(e)) {
                            e = pair.second;
                        }
                    }
                    fill.Add(TopoDS::Edge(e.Oriented(TopAbs_FORWARD)), GeomAbs_C0);
                }
                fill.Build();
                if (!fill.IsDone()) {
                    throw user_error("a corner patch could not be filled");
                }
                TopoDS_Face filled = fill.Face();
                BRepAdaptor_Surface os(old_corner, Standard_False), ns(filled, Standard_False);
                gp_Pnt q;
                gp_Vec a, b;
                const double um = 0.5 * (ns.FirstUParameter() + ns.LastUParameter());
                const double vm = 0.5 * (ns.FirstVParameter() + ns.LastVParameter());
                ns.D1(um, vm, q, a, b);
                gp_Vec n_new = a.Crossed(b);
                if (filled.Orientation() == TopAbs_REVERSED) n_new.Reverse();
                GeomAPI_ProjectPointOnSurf project(q, BRep_Tool::Surface(old_corner));
                double u = 0, v = 0;
                project.LowerDistanceParameters(u, v);
                gp_Pnt c2;
                gp_Vec oa, ob;
                os.D1(u, v, c2, oa, ob);
                gp_Vec n_old = oa.Crossed(ob);
                if (old_corner.Orientation() == TopAbs_REVERSED) n_old.Reverse();
                if (n_new.Dot(n_old) < 0) {
                    filled.Reverse();
                }
                // BRepFill_Filling makes copies of its boundary edges; rebuild the face on the shared new edges.
                {
                    const Handle(Geom_Surface) fill_surface = BRep_Tool::Surface(filled);
                    TopoDS_Face rebuilt;
                    builder.MakeFace(rebuilt, fill_surface, kEdgeTolerance);
                    for (TopoDS_Iterator wires(filled, Standard_False); wires.More(); wires.Next()) {
                        TopoDS_Wire wire;
                        builder.MakeWire(wire);
                        for (TopoDS_Iterator it(wires.Value(), Standard_False); it.More(); it.Next()) {
                            const TopoDS_Edge fe = TopoDS::Edge(it.Value());
                            double f2 = 0, l2 = 0;
                            const Handle(Geom2d_Curve) pc = BRep_Tool::CurveOnSurface(fe, filled, f2, l2);
                            BRepAdaptor_Curve fc(fe);
                            const gp_Pnt fm = fc.Value(0.5 * (fc.FirstParameter() + fc.LastParameter()));
                            TopoDS_Edge shared;
                            for (const auto &pair : replaced_edges) {
                                BRepAdaptor_Curve nc(pair.second);
                                if (nc.Value(0.5 * (nc.FirstParameter() + nc.LastParameter())).Distance(fm) < 1e-7) {
                                    shared = pair.second;
                                }
                            }
                            if (shared.IsNull() || pc.IsNull()) {
                                throw user_error("a corner patch's edge is not one of the strips' ends");
                            }
                            BRepAdaptor_Curve nc(shared);
                            if (nc.Value(nc.FirstParameter()).Distance(fc.Value(fc.FirstParameter())) > 1e-7 ||
                                std::abs(nc.FirstParameter() - fc.FirstParameter()) > 1e-12 ||
                                std::abs(nc.LastParameter() - fc.LastParameter()) > 1e-12) {
                                throw user_error("a corner patch's edge runs the other way from the strip's");
                            }
                            builder.UpdateEdge(shared, pc, fill_surface, TopLoc_Location(), std::max(kEdgeTolerance, 2 * fill.G0Error()));
                            builder.Add(wire, shared.Oriented(it.Value().Orientation()));
                        }
                        wire.Orientation(wires.Value().Orientation());
                        builder.Add(rebuilt, wire);
                    }
                    rebuilt.Orientation(filled.Orientation());
                    filled = rebuilt;
                }
                reshape.Replace(old_corner, filled);
                ++report->corners;
            }
            result = reshape.Apply(work);
            BRepLib::SameParameter(result, 1e-5);
            BRepLib::UpdateTolerances(result);
        }

        // Measure the spring seams in the result.
        const TopTools_IndexedMapOfShape result_faces = map_of(result, TopAbs_FACE);
        TopTools_IndexedDataMapOfShapeListOfShape result_edge_faces;
        TopExp::MapShapesAndAncestors(result, TopAbs_EDGE, TopAbs_FACE, result_edge_faces);
        std::vector<TopoDS_Face> result_blend;
        for (int index : strip_indices) {
            result_blend.push_back(TopoDS::Face(result_faces(index)));
        }
        for (int index : corner_indices) {
            result_blend.push_back(TopoDS::Face(result_faces(index)));
        }
        for (int index : strip_indices) {
            const TopoDS_Face strip = TopoDS::Face(result_faces(index));
            const StripEdges edges = classify(strip, result_edge_faces, result_blend);
            for (const Spring &spring : edges.spring) {
                if (report->seam_count < OCCT_G2_MAX_SEAMS) {
                    report->seams[report->seam_count++] = measure_seam(spring.edge, strip, spring.neighbour);
                }
            }
        }
        return new occt_shape{result};
    });
}

} // extern "C"
