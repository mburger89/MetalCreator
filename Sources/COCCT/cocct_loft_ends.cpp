// The end-constrained loft (G-d): a loft that starts or ends on a face of the part and leaves that face's edges along
// the part's adjacent faces, tangent (G1) or with matching curvature (G2). With every end Free it is OCCT's
// ThruSections, as occt_loft; otherwise it is skinned here: per segment of the sections, columns across the sections as
// quintic B-splines with the face end's derivatives taken from the part, skinned along the segment into one B-spline
// patch, the columns doubled until the face-end seams and the sections fit, the patches and caps sewn and checked.
// The fillet's surface sampling, seam accumulation and tolerances are shared (cocct_g2_blend_internal.hpp).

#include "cocct_g2_blend_internal.hpp"
#include "cocct_profile.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepOffsetAPI_ThruSections.hxx>
#include <BRepTools.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <BSplCLib.hxx>
#include <GeomAPI_Interpolate.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Precision.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColStd_HArray1OfReal.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
#include <TopoDS_Wire.hxx>
#include <math_Gauss.hxx>
#include <math_Matrix.hxx>
#include <math_Vector.hxx>

#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>

using namespace cocct;
using cocct::g2_blend::SurfacePoint;

namespace {

constexpr const char *kTangentMessage = "The loft can't meet the part tangent (G1) here.";
constexpr const char *kCurvatureMessage = "The loft can't meet the part with matching curvature (G2) here.";
constexpr const char *kSegmentsMessage = "Every loft section needs the same number of segments.";
constexpr const char *kHolesMessage = "a loft can't use a profile with holes";
constexpr int kFirstColumns = 9;   // columns per segment to start with
constexpr int kMaxColumns = 129;   // the cap: 9, 17, 33, 65, 129
constexpr int kCheckSamples = 127; // prime, so the samples never fall on the columns (at multiples of 1/2^k)
constexpr int kOrder = 6;          // the columns are quintic
constexpr double kSewingTolerance = 1e-4; // the promised position tolerance; the candidates fit within a fifth of it

enum Continuity { kFree = 0, kTangent = 1, kCurvature = 2 };

/// One segment of one section, sampled from the loop's point at fraction 0 to fraction 1 along the loop.
struct Piece {
    bool on_part = false;
    // A profile segment, in its plane's frame.
    occt_segment segment{};
    gp_Ax2 frame;
    // An edge of the part, sampled from t0 to t1 (decreasing where the loop runs against the edge), and the part's face
    // on the far side of it from the picked face.
    TopoDS_Edge edge;
    TopoDS_Face wall;
    std::shared_ptr<BRepAdaptor_Curve> curve;
    int edge_index = 0;
    double t0 = 0, t1 = 0;
    bool reversed_in_wall = false; // the edge's orientation within the wall (as explored from the part)
    double phi0 = kPi / 2, phi1 = kPi / 2; // the across direction's angle from the loop's tangent at the two ends

    double parameter(double s) const { return t0 + s * (t1 - t0); }

    gp_Pnt value(double s) const {
        if (on_part) {
            return curve->Value(parameter(s));
        }
        if (segment.kind == 0) {
            return point_on(frame, segment.x0 + s * (segment.x1 - segment.x0), segment.y0 + s * (segment.y1 - segment.y0));
        }
        const double a = segment.start + s * (segment.end - segment.start);
        return point_on(frame, segment.cx + segment.radius * std::cos(a), segment.cy + segment.radius * std::sin(a));
    }

    /// The loop's unit tangent at s (the part's edges only).
    gp_Vec tangent(double s) const {
        gp_Pnt p;
        gp_Vec d;
        curve->D1(parameter(s), p, d);
        if (t1 < t0) {
            d.Reverse();
        }
        return d.Normalized();
    }
};

struct Section {
    std::vector<Piece> pieces;
    bool is_face = false;
    TopoDS_Face face;
    int continuity = kFree;
    double weight = 1;
    built_profile profile;
};

/// The wall's frame at fraction s of a face piece: the point, the outward normal and curvatures, the loop's tangent and
/// the unit direction across the edge in the wall's tangent plane that leaves the part (the wall continued past the edge).
struct WallFrame {
    SurfacePoint w;
    gp_Vec tangent;
    gp_Vec away;
};

WallFrame wall_frame(const Piece &piece, double s) {
    const double t = piece.parameter(s);
    WallFrame f;
    f.w = g2_blend::surface_point(piece.wall, piece.edge, t);
    gp_Pnt p;
    gp_Vec raw;
    piece.curve->D1(t, p, raw);
    f.tangent = (piece.t1 < piece.t0 ? raw.Reversed() : raw).Normalized();
    // The wall's material lies to the left of its edge as oriented in it, seen from outside: outward normal x tangent.
    const gp_Vec in_wall = piece.reversed_in_wall ? raw.Reversed() : raw;
    gp_Vec inward = f.w.n.Crossed(in_wall);
    if (inward.Magnitude() < 1e-12) {
        throw user_error(kTangentMessage);
    }
    f.away = inward.Normalized().Reversed();
    return f;
}

/// The direction a column leaves (or reaches) the face loop in, at fraction s of a face piece: in the wall's tangent
/// plane, turned from the perpendicular `away` by the angle blended between the piece's two vertices (where two walls
/// meet at an angle, the shared column runs along their tangent planes' intersection, which lies in both).
gp_Vec column_direction(const Piece &piece, const WallFrame &f, double s) {
    const double phi = kPi / 2 + (1 - s) * (piece.phi0 - kPi / 2) + s * (piece.phi1 - kPi / 2);
    gp_Vec d = f.tangent * std::cos(phi) + f.away * std::sin(phi);
    d -= f.w.n * d.Dot(f.w.n);
    return d.Normalized();
}

/// The direction shared by two face pieces' column at the vertex between them: their `away` directions where the walls
/// agree, else the line where the walls' tangent planes meet, leaving the part.
gp_Vec vertex_direction(const WallFrame &before, const WallFrame &after) {
    if (before.away.Angle(after.away) < 1e-9) {
        return after.away;
    }
    gp_Vec line = before.w.n.Crossed(after.w.n);
    const gp_Vec mean = before.away + after.away;
    if (line.Magnitude() < 1e-9) {
        return mean.Normalized();
    }
    line.Normalize();
    return line.Dot(mean) < 0 ? line.Reversed() : line;
}

/// A face of the part as a section: its outer wire's edges in the wire's order from the edge with the lowest index in the
/// part's edge map, each with the part's face across it.
Section face_section(const TopoDS_Shape &part, const occt_loft_end &end, const TopTools_IndexedMapOfShape &faces,
                     const TopTools_IndexedMapOfShape &edges, const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces) {
    if (end.face_index > faces.Extent()) {
        throw user_error("That face no longer exists.");
    }
    if (end.continuity < kFree || end.continuity > kCurvature) {
        throw user_error("unknown loft end continuity");
    }
    if (end.continuity != kFree && !(end.weight > 0 && std::isfinite(end.weight))) {
        throw user_error("The tangency weight must be greater than 0.");
    }
    Section section;
    section.is_face = true;
    section.continuity = end.continuity;
    section.weight = end.weight;
    // The face as it sits in the part, with its orientation.
    for (TopExp_Explorer it(part, TopAbs_FACE); it.More(); it.Next()) {
        if (it.Current().IsSame(faces(end.face_index))) {
            section.face = TopoDS::Face(it.Current());
            break;
        }
    }
    int wires = 0;
    for (TopExp_Explorer it(section.face, TopAbs_WIRE); it.More(); it.Next()) {
        ++wires;
    }
    if (wires != 1) {
        throw user_error(kHolesMessage);
    }
    const TopoDS_Wire wire = BRepTools::OuterWire(section.face);
    for (BRepTools_WireExplorer it(wire, section.face); it.More(); it.Next()) {
        const TopoDS_Edge edge = it.Current();
        if (BRep_Tool::Degenerated(edge)) {
            continue;
        }
        Piece piece;
        piece.on_part = true;
        piece.edge = edge;
        piece.edge_index = edges.FindIndex(edge);
        piece.curve = std::make_shared<BRepAdaptor_Curve>(edge);
        double first = 0, last = 0;
        BRep_Tool::Range(edge, first, last);
        const bool forward = edge.Orientation() != TopAbs_REVERSED;
        piece.t0 = forward ? first : last;
        piece.t1 = forward ? last : first;
        for (const TopoDS_Face &face : distinct_faces(edge, edge_faces)) {
            if (!face.IsSame(section.face)) {
                piece.wall = face;
            }
        }
        if (piece.wall.IsNull() && end.continuity != kFree) {
            throw user_error(end.continuity == kCurvature ? kCurvatureMessage : kTangentMessage);
        }
        if (!piece.wall.IsNull()) {
            // `wall` came from the edge-to-faces map, which explores the part: its orientation is the part's.
            for (TopExp_Explorer e(piece.wall, TopAbs_EDGE); e.More(); e.Next()) {
                if (e.Current().IsSame(edge)) {
                    piece.reversed_in_wall = e.Current().Orientation() == TopAbs_REVERSED;
                    break;
                }
            }
        }
        section.pieces.push_back(piece);
    }
    if (section.pieces.empty()) {
        throw user_error("the profile has no segments");
    }
    const auto lowest = std::min_element(section.pieces.begin(), section.pieces.end(),
                                         [](const Piece &a, const Piece &b) { return a.edge_index < b.edge_index; });
    std::rotate(section.pieces.begin(), lowest, section.pieces.end());
    return section;
}

Section profile_section(const occt_profile &profile) {
    if (profile.loop_count != 1) {
        throw user_error(kHolesMessage);
    }
    Section section;
    section.profile = build_profile(profile);
    const gp_Ax2 frame = frame_of(profile.plane);
    for (int k = 0; k < profile.loops[0].segment_count; ++k) {
        Piece piece;
        piece.segment = profile.loops[0].segments[k];
        piece.frame = frame;
        section.pieces.push_back(piece);
    }
    return section;
}

/// Twice the loop's vector area, from samples along its pieces: its direction says which way the loop winds.
gp_XYZ vector_area(const Section &section) {
    std::vector<gp_XYZ> points;
    for (const Piece &piece : section.pieces) {
        for (int i = 0; i < 16; ++i) {
            points.push_back(piece.value(i / 16.0).XYZ());
        }
    }
    gp_XYZ area(0, 0, 0);
    for (std::size_t i = 0; i < points.size(); ++i) {
        area += points[i].Crossed(points[(i + 1) % points.size()]);
    }
    return area;
}

/// Turns a face section to wind like `reference` and starts it at the rotation whose vertices best match the
/// reference's, about each loop's centre (the first such rotation on a tie).
void align(Section &face, const Section &reference) {
    if (vector_area(face).Dot(vector_area(reference)) < 0) {
        std::reverse(face.pieces.begin(), face.pieces.end());
        for (Piece &piece : face.pieces) {
            std::swap(piece.t0, piece.t1);
        }
    }
    const int count = static_cast<int>(face.pieces.size());
    auto centre = [&](const Section &s) {
        gp_XYZ c(0, 0, 0);
        for (const Piece &piece : s.pieces) {
            c += piece.value(0).XYZ();
        }
        return c / count;
    };
    const gp_XYZ cf = centre(face), cr = centre(reference);
    int best = 0;
    double best_cost = 0;
    for (int r = 0; r < count; ++r) {
        double cost = 0;
        for (int k = 0; k < count; ++k) {
            cost += ((face.pieces[(k + r) % count].value(0).XYZ() - cf) - (reference.pieces[k].value(0).XYZ() - cr)).SquareModulus();
        }
        if (r == 0 || cost < best_cost * (1 - 1e-12)) {
            best = r;
            best_cost = cost;
        }
    }
    std::rotate(face.pieces.begin(), face.pieces.begin() + best, face.pieces.end());
}

/// Each face piece's column angles at its two vertices.
void plan_vertex_directions(Section &face) {
    if (face.continuity == kFree) {
        return;
    }
    const int count = static_cast<int>(face.pieces.size());
    for (int k = 0; k < count; ++k) {
        Piece &piece = face.pieces[k];
        const Piece &before = face.pieces[(k + count - 1) % count];
        const Piece &after = face.pieces[(k + 1) % count];
        const WallFrame start = wall_frame(piece, 0), finish = wall_frame(piece, 1);
        const gp_Vec d0 = vertex_direction(wall_frame(before, 1), start);
        const gp_Vec d1 = vertex_direction(finish, wall_frame(after, 0));
        piece.phi0 = std::atan2(d0.Dot(start.away), d0.Dot(start.tangent));
        piece.phi1 = std::atan2(d1.Dot(finish.away), d1.Dot(finish.tangent));
    }
}

/// The columns' shared quintic B-spline basis across the sections: knots at the sections' chord-length places, and the
/// factored system that gives a column's poles from its section points and its two ends' conditions.
struct ColumnBasis {
    int sections = 0;
    std::vector<double> v;           // the sections' places, 0 to 1
    TColStd_Array1OfReal knots;      // distinct
    TColStd_Array1OfInteger mults;
    std::unique_ptr<math_Gauss> solver;
    int start = kFree, finish = kFree;

    int poles() const { return sections + 4; }
};

/// The rows of a B-spline's values or derivatives at `v` (`order` 0 to 4): A(row, j) = N_j^(order)(v).
void basis_row(math_Matrix &a, int row, const TColStd_Array1OfReal &flat, double v, int order) {
    math_Matrix values(1, 5, 1, kOrder, 0.0);
    int first = 0;
    if (BSplCLib::EvalBsplineBasis(4, kOrder, flat, v, first, values) != 0) {
        throw std::runtime_error("the loft's column basis could not be evaluated");
    }
    for (int j = 1; j <= kOrder; ++j) {
        a(row, first + j - 1) = values(order + 1, j);
    }
}

std::unique_ptr<ColumnBasis> make_basis(const std::vector<Section> &sections) {
    auto basis = std::make_unique<ColumnBasis>();
    const int n = static_cast<int>(sections.size());
    basis->sections = n;
    basis->start = sections.front().is_face ? sections.front().continuity : kFree;
    basis->finish = sections.back().is_face ? sections.back().continuity : kFree;
    // Chord-length places, normalized per sample column and averaged over four columns per segment (fixed, so the
    // knots never depend on how many columns a patch needs).
    basis->v.assign(n, 0.0);
    int samples = 0;
    const int segments = static_cast<int>(sections.front().pieces.size());
    for (int k = 0; k < segments; ++k) {
        for (const double s : {0.0, 0.25, 0.5, 0.75}) {
            std::vector<double> cumulative{0.0};
            for (int i = 1; i < n; ++i) {
                cumulative.push_back(cumulative.back()
                                     + sections[i].pieces[k].value(s).Distance(sections[i - 1].pieces[k].value(s)));
            }
            if (cumulative.back() < 1e-9) {
                continue;
            }
            for (int i = 0; i < n; ++i) {
                basis->v[i] += cumulative[i] / cumulative.back();
            }
            ++samples;
        }
    }
    if (samples == 0) {
        throw user_error("the loft's sections lie on top of each other");
    }
    for (double &value : basis->v) {
        value /= samples;
    }
    basis->v.front() = 0;
    basis->v.back() = 1;
    for (int i = 1; i < n; ++i) {
        if (basis->v[i] - basis->v[i - 1] < 1e-6) {
            throw user_error("the loft's sections lie on top of each other");
        }
    }
    basis->knots = TColStd_Array1OfReal(1, n);
    basis->mults = TColStd_Array1OfInteger(1, n);
    for (int i = 0; i < n; ++i) {
        basis->knots.SetValue(i + 1, basis->v[i]);
        basis->mults.SetValue(i + 1, (i == 0 || i == n - 1) ? kOrder : 1);
    }
    TColStd_Array1OfReal flat(1, basis->poles() + kOrder);
    BSplCLib::KnotSequence(basis->knots, basis->mults, flat);
    const int size = basis->poles();
    math_Matrix a(1, size, 1, size, 0.0);
    for (int i = 0; i < n; ++i) {
        basis_row(a, i + 1, flat, basis->v[i], 0);
    }
    // Two rows per end: Free, the natural conditions (third and fourth derivatives zero); Tangent, the first derivative
    // given and the third zero; Curvature, the first and second derivatives given.
    auto end_rows = [&](int row, double v, int kind) {
        const int orders[3][2] = {{3, 4}, {1, 3}, {1, 2}};
        basis_row(a, row, flat, v, orders[kind][0]);
        basis_row(a, row + 1, flat, v, orders[kind][1]);
    };
    end_rows(n + 1, 0, basis->start);
    end_rows(n + 3, 1, basis->finish);
    basis->solver = std::make_unique<math_Gauss>(a, 1e-14);
    if (!basis->solver->IsDone()) {
        throw user_error(basis->start == kCurvature || basis->finish == kCurvature ? kCurvatureMessage : kTangentMessage);
    }
    return basis;
}

/// A face end's two column conditions at fraction s of segment k: the first derivative (with respect to the columns'
/// parameter) and the second (Curvature) or zero (the third derivative's row, Tangent).
void face_end_rows(const Section &face, int k, double s, const gp_Pnt &neighbour, double span, bool at_start,
                   gp_Vec &first, gp_Vec &second) {
    const Piece &piece = face.pieces[k];
    const WallFrame f = wall_frame(piece, s);
    const gp_Vec d = column_direction(piece, f, s);
    const gp_Pnt p = piece.value(s);
    const gp_Vec chord(p, neighbour);
    const double c = chord.Magnitude();
    // The direction of travel along the column at this end: away from the part at the start, towards it at the end.
    const gp_Vec travel = at_start ? d : d.Reversed();
    const gp_Vec towards = at_start ? chord : chord.Reversed();
    const double angle = c > 1e-12 ? std::min(travel.Angle(towards), kPi / 2) : 0.0;
    const double length = face.weight * g2::circular_tangent_length(c, 2 * angle) / span;
    first = travel * length;
    if (face.continuity == kCurvature) {
        second = f.w.n * (f.w.normal_curvature(d) * length * length);
    } else {
        second = gp_Vec(0, 0, 0);
    }
}

/// The poles of segment k's column at fraction s.
std::vector<gp_Pnt> column(const std::vector<Section> &sections, const ColumnBasis &basis, int k, double s) {
    const int n = basis.sections;
    const int size = basis.poles();
    std::vector<gp_Pnt> points;
    for (const Section &section : sections) {
        points.push_back(section.pieces[k].value(s));
    }
    std::vector<gp_Vec> ends(4, gp_Vec(0, 0, 0));
    if (basis.start != kFree) {
        face_end_rows(sections.front(), k, s, points[1], basis.v[1] - basis.v[0], true, ends[0], ends[1]);
    }
    if (basis.finish != kFree) {
        face_end_rows(sections.back(), k, s, points[n - 2], basis.v[n - 1] - basis.v[n - 2], false, ends[2], ends[3]);
    }
    std::vector<gp_Pnt> poles(size);
    for (int axis = 1; axis <= 3; ++axis) {
        math_Vector b(1, size, 0.0), x(1, size, 0.0);
        for (int i = 0; i < n; ++i) {
            b(i + 1) = points[i].Coord(axis);
        }
        for (int e = 0; e < 4; ++e) {
            b(n + 1 + e) = ends[e].Coord(axis);
        }
        basis.solver->Solve(b, x);
        for (int j = 0; j < size; ++j) {
            poles[j].SetCoord(axis, x(j + 1));
        }
    }
    return poles;
}

/// The patch of segment k through `count` columns at even fractions: each row of column poles interpolated by a cubic
/// along the segment (periodically for a closed loop of one segment, whose last column is its first).
Handle(Geom_BSplineSurface) skin(const std::vector<std::vector<gp_Pnt>> &columns, const ColumnBasis &basis, bool closed) {
    const int count = static_cast<int>(columns.size());
    const int size = basis.poles();
    const int points_count = closed ? count - 1 : count;
    Handle(TColStd_HArray1OfReal) params = new TColStd_HArray1OfReal(1, count);
    for (int j = 0; j < count; ++j) {
        params->SetValue(j + 1, static_cast<double>(j) / (count - 1));
    }
    std::vector<Handle(Geom_BSplineCurve)> rows;
    for (int r = 0; r < size; ++r) {
        Handle(TColgp_HArray1OfPnt) points = new TColgp_HArray1OfPnt(1, points_count);
        for (int j = 0; j < points_count; ++j) {
            points->SetValue(j + 1, columns[j][r]);
        }
        GeomAPI_Interpolate interpolate(points, params, closed ? Standard_True : Standard_False, 1e-9);
        interpolate.Perform();
        if (!interpolate.IsDone()) {
            throw std::runtime_error("the loft's columns could not be skinned");
        }
        rows.push_back(interpolate.Curve());
    }
    const int u_poles = rows[0]->NbPoles();
    TColgp_Array2OfPnt poles(1, u_poles, 1, size);
    for (int r = 0; r < size; ++r) {
        if (rows[r]->NbPoles() != u_poles) {
            throw std::runtime_error("the loft's columns could not be skinned");
        }
        for (int j = 1; j <= u_poles; ++j) {
            poles.SetValue(j, r + 1, rows[r]->Pole(j));
        }
    }
    TColStd_Array1OfReal uknots(1, rows[0]->NbKnots());
    TColStd_Array1OfInteger umults(1, rows[0]->NbKnots());
    rows[0]->Knots(uknots);
    rows[0]->Multiplicities(umults);
    return new Geom_BSplineSurface(poles, uknots, basis.knots, umults, basis.mults, rows[0]->Degree(), kOrder - 1,
                                   closed ? Standard_True : Standard_False, Standard_False);
}

/// The patch's point and normal at (u, v), the normal turned outward when `outward` is +1 or -1, or to agree with
/// `like` when 0.
SurfacePoint patch_point(const Handle(Geom_Surface) &surface, double u, double v, int outward, const gp_Vec &like) {
    SurfacePoint s;
    surface->D2(u, v, s.p, s.su, s.sv, s.suu, s.svv, s.suv);
    s.n = s.su.Crossed(s.sv);
    if (s.n.Magnitude() < 1e-12) {
        throw std::runtime_error("the loft's patch is degenerate");
    }
    s.n.Normalize();
    if (outward < 0 || (outward == 0 && s.n.Dot(like) < 0)) {
        s.n.Reverse();
    }
    return s;
}

/// The face end's seam on the patch of segment k, against the part's wall, sampled `samples` + 1 times.
occt_g2_seam face_seam(const Handle(Geom_Surface) &surface, const Section &face, int k, double v, int outward, int samples) {
    occt_g2_seam seam{};
    const Piece &piece = face.pieces[k];
    for (int i = 0; i <= samples; ++i) {
        const double s = static_cast<double>(i) / samples;
        const double t = piece.parameter(s);
        const SurfacePoint wall = g2_blend::surface_point(piece.wall, piece.edge, t);
        const SurfacePoint patch = patch_point(surface, s, v, outward, wall.n);
        gp_Pnt p;
        gp_Vec tangent;
        piece.curve->D1(t, p, tangent);
        g2_blend::accumulate(seam, patch, wall, tangent, face.continuity == kCurvature);
        // The patch's boundary must be on the edge too, not only on the wall's surface.
        seam.position = std::max(seam.position, patch.p.Distance(p));
    }
    return seam;
}

bool meets_promise(const occt_g2_seam &seam) {
    return seam.position <= 1e-4 && seam.angle_degrees <= 0.01 && seam.curvature_ratio <= 1;
}

const char *message_for(const Section &face) {
    return face.continuity == kCurvature ? kCurvatureMessage : kTangentMessage;
}

struct Patch {
    Handle(Geom_BSplineSurface) surface;
    int columns = 0;
    double section_gap = 0;
};

/// Segment k's patch, its columns doubled until the face-end seams meet half the tolerances and the patch follows every
/// section's segment to within a fifth of the position tolerance.
Patch build_patch(const std::vector<Section> &sections, const ColumnBasis &basis, int k) {
    const bool closed = sections.front().pieces.size() == 1;
    const Section *strongest = nullptr;
    for (const Section *end : {&sections.front(), &sections.back()}) {
        if (end->is_face && end->continuity != kFree && (!strongest || end->continuity > strongest->continuity)) {
            strongest = end;
        }
    }
    for (int count = kFirstColumns; count <= kMaxColumns; count = 2 * count - 1) {
        std::vector<std::vector<gp_Pnt>> columns;
        for (int j = 0; j < count; ++j) {
            columns.push_back(column(sections, basis, k, static_cast<double>(j) / (count - 1)));
        }
        Patch patch;
        patch.surface = skin(columns, basis, closed);
        patch.columns = count;
        bool fits = true;
        if (basis.start != kFree) {
            fits = fits && g2_blend::within_tolerance(face_seam(patch.surface, sections.front(), k, 0, 0, kCheckSamples));
        }
        if (basis.finish != kFree) {
            fits = fits && g2_blend::within_tolerance(face_seam(patch.surface, sections.back(), k, 1, 0, kCheckSamples));
        }
        for (int i = 0; i < basis.sections; ++i) {
            for (int j = 0; j <= kCheckSamples; ++j) {
                const double s = static_cast<double>(j) / kCheckSamples;
                patch.section_gap = std::max(patch.section_gap,
                                             patch.surface->Value(s, basis.v[i]).Distance(sections[i].pieces[k].value(s)));
            }
        }
        fits = fits && patch.section_gap <= 2e-5;
        if (fits) {
            return patch;
        }
    }
    throw user_error(strongest ? message_for(*strongest) : kTangentMessage);
}

/// The ThruSections loft of an all-Free loft, as occt_loft builds it, a face section through the face's own edges.
TopoDS_Shape thru_sections(const std::vector<Section> &sections, occt_history *history) {
    BRepOffsetAPI_ThruSections loft(Standard_True, Standard_False);
    std::vector<TopoDS_Edge> first;
    for (std::size_t i = 0; i < sections.size(); ++i) {
        const Section &section = sections[i];
        TopoDS_Wire wire;
        if (section.is_face) {
            BRep_Builder builder;
            builder.MakeWire(wire);
            for (const Piece &piece : section.pieces) {
                double a = 0, b = 0;
                BRep_Tool::Range(piece.edge, a, b);
                // The edge as the loop runs along it: forward when the loop's parameters increase.
                const TopoDS_Edge along = TopoDS::Edge(piece.edge.Oriented(piece.t1 > piece.t0 ? TopAbs_FORWARD : TopAbs_REVERSED));
                builder.Add(wire, along);
                if (i == 0) {
                    first.push_back(along);
                }
            }
        } else {
            wire = BRepTools::OuterWire(section.profile.face);
            if (i == 0) {
                first = section.profile.loops.front();
            }
        }
        loft.AddWire(wire);
    }
    loft.Build();
    if (!loft.IsDone()) {
        throw user_error("the loft could not be built");
    }
    const TopoDS_Shape solid = oriented(loft.Shape());
    history_builder records(solid);
    records.add(loft.FirstShape(), OCCT_FROM_START_CAP, 0, 0);
    records.add(loft.LastShape(), OCCT_FROM_END_CAP, 0, 0);
    for (int k = 0; k < static_cast<int>(first.size()); ++k) {
        records.add(loft.GeneratedFace(first[k]), OCCT_FROM_SEGMENT, 0, k);
    }
    records.move_into(history);
    return solid;
}

} // namespace

extern "C" {

occt_shape *occt_loft_ends(const occt_shape *part, const occt_loft_end *start, const occt_loft_end *end,
                           const occt_profile *profiles, int count, occt_history *history, occt_loft_report *report,
                           occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        *report = occt_loft_report{};
        const bool start_face = start && start->face_index >= 1;
        const bool end_face = end && end->face_index >= 1;
        if (start_face && !part) {
            throw user_error("Pick a face of the part for the loft's start.");
        }
        if (end_face && !part) {
            throw user_error("Pick a face of the part for the loft's end.");
        }
        if (count < 0 || (count > 0 && !profiles) || count + (start_face ? 1 : 0) + (end_face ? 1 : 0) < 2) {
            throw user_error("a loft needs at least two sections");
        }
        std::vector<Section> sections;
        TopTools_IndexedMapOfShape faces, edges;
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        if (part) {
            faces = map_of(part->shape, TopAbs_FACE);
            edges = map_of(part->shape, TopAbs_EDGE);
            TopExp::MapShapesAndAncestors(part->shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);
        }
        if (start_face) {
            sections.push_back(face_section(part->shape, *start, faces, edges, edge_faces));
        }
        for (int i = 0; i < count; ++i) {
            sections.push_back(profile_section(profiles[i]));
        }
        if (end_face) {
            sections.push_back(face_section(part->shape, *end, faces, edges, edge_faces));
        }
        const std::size_t segments = sections.front().pieces.size();
        for (const Section &section : sections) {
            if (section.pieces.size() != segments) {
                throw user_error(kSegmentsMessage);
            }
        }
        // Profiles are fixed; a face end is turned to its neighbour (the start face keeps its order when the loft
        // runs from face to face).
        if (start_face && count > 0) {
            align(sections.front(), sections[1]);
        }
        if (end_face) {
            align(sections.back(), sections[sections.size() - 2]);
        }
        for (Section &section : sections) {
            if (section.is_face) {
                plan_vertex_directions(section);
            }
        }
        report->segments = static_cast<int>(segments);
        const bool constrained = (start_face && start->continuity != kFree) || (end_face && end->continuity != kFree);
        if (!constrained) {
            const TopoDS_Shape solid = thru_sections(sections, history);
            report->used_thru_sections = 1;
            report->seams_judged = 1;
            return new occt_shape{solid};
        }
        const std::unique_ptr<ColumnBasis> basis = make_basis(sections);
        std::vector<Patch> patches;
        for (std::size_t k = 0; k < segments; ++k) {
            patches.push_back(build_patch(sections, *basis, static_cast<int>(k)));
            report->section_gap = std::max(report->section_gap, patches.back().section_gap);
            if (k < OCCT_LOFT_MAX_SEGMENTS) {
                report->columns[k] = patches.back().columns;
            }
            report->max_columns = std::max(report->max_columns, patches.back().columns);
        }
        // Neighbouring patches share their boundary column: the same poles, so the same curve.
        for (std::size_t k = 0; k < segments; ++k) {
            const Patch &a = patches[k], &b = patches[(k + 1) % segments];
            for (int j = 0; j <= kCheckSamples; ++j) {
                const double v = static_cast<double>(j) / kCheckSamples;
                report->side_gap = std::max(report->side_gap, a.surface->Value(1, v).Distance(b.surface->Value(0, v)));
            }
        }
        // The poles are shared, so the gap is rounding; anything more is a construction error, never a crease to keep.
        if (report->side_gap > 1e-7) {
            throw std::runtime_error("the loft's side patches do not share their columns");
        }
        // Faces: the patches, and the caps (a face end's is a copy of the face; a profile's, its planar face).
        std::vector<TopoDS_Face> sides;
        for (const Patch &patch : patches) {
            BRepBuilderAPI_MakeFace make(patch.surface, 0, 1, 0, 1, Precision::Confusion());
            if (!make.IsDone()) {
                throw std::runtime_error("a loft patch could not be made a face");
            }
            sides.push_back(make.Face());
        }
        auto cap = [](const Section &section) {
            return section.is_face ? TopoDS::Face(BRepBuilderAPI_Copy(section.face).Shape()) : section.profile.face;
        };
        const TopoDS_Face first_cap = cap(sections.front()), last_cap = cap(sections.back());
        BRepBuilderAPI_Sewing sewing(kSewingTolerance);
        sewing.Add(first_cap);
        for (const TopoDS_Face &face : sides) {
            sewing.Add(face);
        }
        sewing.Add(last_cap);
        sewing.Perform();
        const char *failure = message_for(start_face && start->continuity != kFree ? sections.front() : sections.back());
        if (sewing.NbFreeEdges() != 0 || sewing.NbMultipleEdges() != 0) {
            throw user_error(failure);
        }
        TopoDS_Shell shell;
        int shells = 0;
        for (TopExp_Explorer it(sewing.SewedShape(), TopAbs_SHELL); it.More(); it.Next()) {
            shell = TopoDS::Shell(it.Current());
            ++shells;
        }
        if (shells != 1) {
            throw user_error(failure);
        }
        BRepBuilderAPI_MakeSolid make_solid(shell);
        if (!make_solid.IsDone()) {
            throw user_error(failure);
        }
        const TopoDS_Shape solid = oriented(make_solid.Solid());
        if (!BRepCheck_Analyzer(solid).IsValid()) {
            throw user_error(failure);
        }
        // Judge every promised seam on the built solid, with the patches' faces as they are oriented in it.
        auto in_solid = [&](const TopoDS_Face &face) {
            const TopoDS_Shape sewn = sewing.Modified(face);
            for (TopExp_Explorer it(solid, TopAbs_FACE); it.More(); it.Next()) {
                if (it.Current().IsSame(sewn)) {
                    return TopoDS::Face(it.Current());
                }
            }
            throw std::runtime_error("a loft patch is missing from the solid");
        };
        for (int which = 0; which < 2; ++which) {
            const Section &face = which == 0 ? sections.front() : sections.back();
            if (!face.is_face || face.continuity == kFree) {
                continue;
            }
            for (std::size_t k = 0; k < segments; ++k) {
                const TopoDS_Face side = in_solid(sides[k]);
                const occt_g2_seam seam = face_seam(BRep_Tool::Surface(side), face, static_cast<int>(k), which == 0 ? 0 : 1,
                                                    side.Orientation() == TopAbs_REVERSED ? -1 : 1, kCheckSamples);
                ++report->seams_total;
                occt_g2_seam &worst = report->worst_seam;
                worst.position = std::max(worst.position, seam.position);
                worst.angle_degrees = std::max(worst.angle_degrees, seam.angle_degrees);
                worst.curvature = std::max(worst.curvature, seam.curvature);
                if (seam.curvature_ratio >= worst.curvature_ratio) {
                    worst.curvature_ratio = seam.curvature_ratio;
                    worst.curvature_allowed = seam.curvature_allowed;
                }
                if (!meets_promise(seam)) {
                    throw user_error(message_for(face));
                }
            }
        }
        report->seams_judged = 1;
        history_builder records(solid);
        records.add(sewing.Modified(first_cap), OCCT_FROM_START_CAP, 0, 0);
        records.add(sewing.Modified(last_cap), OCCT_FROM_END_CAP, 0, 0);
        for (std::size_t k = 0; k < segments; ++k) {
            records.add(sewing.Modified(sides[k]), OCCT_FROM_SEGMENT, 0, static_cast<int>(k));
        }
        records.move_into(history);
        return new occt_shape{solid};
    });
}

} // extern "C"
