// The end-constrained loft (G-d): a loft that starts or ends on a face of the part and leaves that face's edges along
// the part's adjacent faces, tangent (G1) or with matching curvature (G2). With every end Free it is OCCT's
// ThruSections, as occt_loft; otherwise it is skinned here: per segment of the sections, columns across the sections as
// quintic B-splines with the face end's derivatives taken from the part, skinned along the segment into one B-spline
// patch, columns added where a span misses until the face-end seams and the sections fit, the patches and caps sewn and checked.
// The fillet's surface sampling, seam accumulation and tolerances are shared (cocct_g2_blend_internal.hpp).

#include "cocct_g2_blend_internal.hpp"
#include "cocct_profile.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <GeomAbs_SurfaceType.hxx>
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
#include <Geom_Curve.hxx>
#include <TopLoc_Location.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Precision.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColStd_HArray1OfBoolean.hxx>
#include <TColStd_HArray1OfReal.hxx>
#include <TColgp_Array1OfVec.hxx>
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
constexpr const char *kWeightMessage = "The tangency weight is too large for this loft.";
constexpr const char *kFlatMessage = "The loft's end face must be flat.";
constexpr const char *kHolesMessage = "A loft can't use profiles with holes yet.";
constexpr int kFirstColumns = 9;   // columns per segment to start with
constexpr int kMaxColumns = 129;   // the cap, columns in all per segment
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
    double first = 0, last = 0;     // the edge's own parameter range
    bool periodic = false;          // a closed, periodic edge that is the whole loop (a circle): parameters wrap
    bool rephased = false;          // its start was moved to the point nearest the paired section's start
    bool wall_planar = false;
    bool reversed_in_wall = false; // the edge's orientation within the wall (as explored from the part)
    double phi0 = kPi / 2, phi1 = kPi / 2; // the across direction's angle from the loop's tangent at the two ends

    double parameter(double s) const {
        double t = t0 + s * (t1 - t0);
        if (periodic) {
            const double period = last - first;
            while (t > last + 1e-12) {
                t -= period;
            }
            while (t < first - 1e-12) {
                t += period;
            }
        }
        return t;
    }

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
        throw user_error("The loft end condition is not known.");
    }
    if (end.continuity != kFree && !(end.weight > 0 && std::isfinite(end.weight))) {
        throw user_error("The tangency weight must be greater than 0.");
    }
    Section section;
    section.is_face = true;
    section.continuity = end.continuity;
    // A loft's end face is flat (its caps and columns are built from the planar loop); a curved face is refused.
    if (BRepAdaptor_Surface(TopoDS::Face(faces(end.face_index))).GetType() != GeomAbs_Plane) {
        throw user_error(kFlatMessage);
    }
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
        piece.first = first;
        piece.last = last;
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
            piece.wall_planar = BRepAdaptor_Surface(piece.wall).GetType() == GeomAbs_Plane;
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
        throw user_error("The profile has no segments.");
    }
    if (section.pieces.size() == 1) {
        Piece &only = section.pieces.front();
        only.periodic = only.curve->IsClosed() && only.curve->IsPeriodic();
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

/// Starts a closed periodic loop (a circle) at the point of the edge nearest `target`, keeping its direction.
void rephase(Piece &piece, const gp_Pnt &target) {
    const double period = piece.last - piece.first;
    constexpr int kSteps = 720;
    auto distance = [&](double t) { return piece.curve->Value(t).SquareDistance(target); };
    int best = 0;
    double best_distance = 0;
    for (int i = 0; i < kSteps; ++i) {
        const double d = distance(piece.first + period * i / kSteps);
        if (i == 0 || d < best_distance) {
            best = i;
            best_distance = d;
        }
    }
    // Golden-section search between the neighbouring samples.
    double a = piece.first + period * (best - 1) / kSteps, b = piece.first + period * (best + 1) / kSteps;
    const double ratio = (std::sqrt(5.0) - 1) / 2;
    for (int i = 0; i < 60; ++i) {
        const double c = b - ratio * (b - a), d = a + ratio * (b - a);
        if (distance(c) < distance(d)) {
            b = d;
        } else {
            a = c;
        }
    }
    double start = 0.5 * (a + b);
    while (start > piece.last) {
        start -= period;
    }
    while (start < piece.first) {
        start += period;
    }
    const bool forward = piece.t1 > piece.t0;
    piece.t0 = start;
    piece.t1 = forward ? start + period : start - period;
    piece.rephased = true;
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
    if (count == 1 && face.pieces.front().periodic) {
        rephase(face.pieces.front(), reference.pieces.front().value(0));
        return;
    }
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
        throw user_error("The loft's sections lie on top of each other.");
    }
    for (double &value : basis->v) {
        value /= samples;
    }
    basis->v.front() = 0;
    basis->v.back() = 1;
    for (int i = 1; i < n; ++i) {
        if (basis->v[i] - basis->v[i - 1] < 1e-6) {
            throw user_error("The loft's sections lie on top of each other.");
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

/// The second derivative (with respect to the columns' parameter) of the column that two walls share at a loop vertex.
/// A wall's G2 condition constrains only the component of the column's second derivative along that wall's normal:
/// C'' . n = kappa(d) L^2 (the normal curvature along the column's direction d, with L the first derivative's length). Each
/// patch used to take its own wall's value, so the two patches' shared column disagreed in the second derivative. The
/// vertex column is one curve, so its C'' is solved once, in the plane of the two normals, to satisfy both walls.
/// `before` and `after` are always the walls in loop order, so both patches get the same vector.
gp_Vec vertex_second_derivative(const WallFrame &before, const WallFrame &after, const gp_Vec &d, double length) {
    const double scale = length * length;
    const double ka = before.w.normal_curvature(d) * scale, kb = after.w.normal_curvature(d) * scale;
    const gp_Vec &na = before.w.n, &nb = after.w.n;
    const double c = na.Dot(nb);
    const double det = 1 - c * c;
    if (det < 1e-8) {
        // The walls share a tangent plane here, so each constrains the same component of C'': they must agree.
        if (std::abs(ka - kb) > std::max(1e-4 * scale, 0.01 * std::max(std::abs(ka), std::abs(kb)))) {
            throw user_error(kCurvatureMessage);
        }
        return na * (0.5 * (ka + kb));
    }
    // C'' = alpha na + beta nb with C'' . na = ka and C'' . nb = kb.
    const double alpha = (ka - kb * c) / det, beta = (kb - ka * c) / det;
    return na * alpha + nb * beta;
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
    if (face.continuity != kCurvature) {
        second = gp_Vec(0, 0, 0);
        return;
    }
    const int count = static_cast<int>(face.pieces.size());
    const bool at_vertex = count > 1 && (s == 0.0 || s == 1.0);
    if (!at_vertex) {
        second = f.w.n * (f.w.normal_curvature(d) * length * length);
        return;
    }
    // At a vertex the column is shared with the neighbouring patch: both build the same second derivative.
    if (s == 0.0) {
        second = vertex_second_derivative(wall_frame(face.pieces[(k + count - 1) % count], 1), f, d, length);
    } else {
        second = vertex_second_derivative(f, wall_frame(face.pieces[(k + 1) % count], 0), d, length);
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

/// The patch of segment k through the columns at the given fractions of the segment (0 to 1): each row of column poles interpolated by a cubic
/// along the segment (periodically for a closed loop of one segment, whose last column is its first).
/// The row tangents a patch's skin is given where its end is a smooth vertex: per pole row, the derivative with respect to
/// the patch's fraction (empty: free).
struct EndTangents {
    std::vector<gp_Vec> start, finish;
};

Handle(Geom_BSplineSurface) skin(const std::vector<std::vector<gp_Pnt>> &columns, const std::vector<double> &fractions,
                                 const ColumnBasis &basis, bool closed, const EndTangents &tangents) {
    const int count = static_cast<int>(columns.size());
    const int size = basis.poles();
    const int points_count = closed ? count - 1 : count;
    Handle(TColStd_HArray1OfReal) params = new TColStd_HArray1OfReal(1, count);
    for (int j = 0; j < count; ++j) {
        params->SetValue(j + 1, fractions[j]);
    }
    std::vector<Handle(Geom_BSplineCurve)> rows;
    for (int r = 0; r < size; ++r) {
        Handle(TColgp_HArray1OfPnt) points = new TColgp_HArray1OfPnt(1, points_count);
        for (int j = 0; j < points_count; ++j) {
            points->SetValue(j + 1, columns[j][r]);
        }
        GeomAPI_Interpolate interpolate(points, params, closed ? Standard_True : Standard_False, 1e-9);
        const bool has_start = !closed && !tangents.start.empty(), has_finish = !closed && !tangents.finish.empty();
        if (has_start || has_finish) {
            TColgp_Array1OfVec given(1, points_count);
            Handle(TColStd_HArray1OfBoolean) flags = new TColStd_HArray1OfBoolean(1, points_count);
            for (int j = 1; j <= points_count; ++j) {
                given.SetValue(j, gp_Vec(0, 0, 0));
                flags->SetValue(j, Standard_False);
            }
            if (has_start) {
                given.SetValue(1, tangents.start[r]);
                flags->SetValue(1, Standard_True);
            }
            if (has_finish) {
                given.SetValue(points_count, tangents.finish[r]);
                flags->SetValue(points_count, Standard_True);
            }
            interpolate.Load(given, flags, Standard_False);
        }
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

/// The face end's seam on the patch of segment k at fraction s of the segment.
occt_g2_seam face_seam_at(const Handle(Geom_Surface) &surface, const Section &face, int k, double v, int outward, double s) {
    occt_g2_seam seam{};
    const Piece &piece = face.pieces[k];
    const double t = piece.parameter(s);
    const SurfacePoint wall = g2_blend::surface_point(piece.wall, piece.edge, t);
    const SurfacePoint patch = patch_point(surface, s, v, outward, wall.n);
    gp_Pnt p;
    gp_Vec tangent;
    piece.curve->D1(t, p, tangent);
    g2_blend::accumulate(seam, patch, wall, tangent, face.continuity == kCurvature);
    // The patch's boundary must be on the edge too, not only on the wall's surface.
    seam.position = std::max(seam.position, patch.p.Distance(p));
    return seam;
}

/// The face end's seam on the patch of segment k, against the part's wall, sampled `samples` + 1 times.
occt_g2_seam face_seam(const Handle(Geom_Surface) &surface, const Section &face, int k, double v, int outward, int samples) {
    occt_g2_seam seam{};
    for (int i = 0; i <= samples; ++i) {
        const occt_g2_seam at = face_seam_at(surface, face, k, v, outward, static_cast<double>(i) / samples);
        seam.position = std::max(seam.position, at.position);
        seam.angle_degrees = std::max(seam.angle_degrees, at.angle_degrees);
        seam.curvature = std::max(seam.curvature, at.curvature);
        if (at.curvature_ratio >= seam.curvature_ratio) {
            seam.curvature_ratio = at.curvature_ratio;
            seam.curvature_allowed = at.curvature_allowed;
        }
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

/// Refuses a weight so large that a column loops back on itself: along the first (or last) span of the sections, the
/// column's first derivative turns more than 120 degrees from the direction between that span's two points. (Weights up
/// to the node's 2 turn to about 109 degrees at the far end of the span and build valid solids; at 3 it is 136.)
void check_column(const std::vector<Section> &sections, const ColumnBasis &basis, int k, double s,
                 const std::vector<gp_Pnt> &poles) {
    if (basis.start == kFree && basis.finish == kFree) {
        return;
    }
    const int n = basis.sections;
    TColgp_Array1OfPnt array(1, basis.poles());
    for (int j = 0; j < basis.poles(); ++j) {
        array.SetValue(j + 1, poles[j]);
    }
    const Handle(Geom_BSplineCurve) curve = new Geom_BSplineCurve(array, basis.knots, basis.mults, kOrder - 1);
    for (int which = 0; which < 2; ++which) {
        if ((which == 0 ? basis.start : basis.finish) == kFree) {
            continue;
        }
        const int near = which == 0 ? 0 : n - 1, inner = which == 0 ? 1 : n - 2;
        // The direction of increasing v across that span.
        const gp_Vec direction = which == 0 ? gp_Vec(sections[near].pieces[k].value(s), sections[inner].pieces[k].value(s))
                                            : gp_Vec(sections[inner].pieces[k].value(s), sections[near].pieces[k].value(s));
        const double low = std::min(basis.v[near], basis.v[inner]), high = std::max(basis.v[near], basis.v[inner]);
        for (int i = 0; i <= 32; ++i) {
            gp_Pnt p;
            gp_Vec d;
            curve->D1(low + (high - low) * i / 32, p, d);
            if (d.Magnitude() > 1e-9 && direction.Magnitude() > 1e-9 && d.Dot(direction) < -0.5 * d.Magnitude() * direction.Magnitude()) {
                throw user_error(kWeightMessage);
            }
        }
    }
}

/// The unit tangent of a piece at its start (s = 0) or finish (s = 1), by a one-sided difference.
gp_Vec end_tangent(const Piece &piece, bool finish) {
    constexpr double h = 1e-6;
    const gp_Vec d = finish ? gp_Vec(piece.value(1 - h), piece.value(1)) : gp_Vec(piece.value(0), piece.value(h));
    return d.Magnitude() > 0 ? d.Normalized() : d;
}

/// The vertices (between segment k - 1 and k) where every section runs tangent-continuously, and for each the shared
/// direction of every pole row there. Two patches that leave a shared column with different derivatives along the loop
/// crease the loft's own side (G0) even where its sections are smooth; a common direction, scaled by each patch's own
/// speed, makes the two derivatives parallel (G1). True corners keep free ends.
struct SmoothVertices {
    std::vector<bool> smooth;
    // Per vertex, per pole row: the derivative with respect to the segment's fraction on the left (the segment ending
    // there) and on the right (the segment starting there), each with its own natural length and a shared direction.
    std::vector<std::vector<gp_Vec>> left, right;
};

SmoothVertices plan_smooth_vertices(const std::vector<Section> &sections, const ColumnBasis &basis) {
    const int segments = static_cast<int>(sections.front().pieces.size());
    SmoothVertices vertices;
    vertices.smooth.assign(segments, false);
    vertices.left.resize(segments);
    vertices.right.resize(segments);
    if (segments < 2) {
        return vertices;
    }
    constexpr double kAngle = 0.01 * kPi / 180; // the promised angle tolerance
    constexpr double eps = 1.0 / 64;
    for (int m = 0; m < segments; ++m) {
        const int left = (m + segments - 1) % segments;
        bool smooth = true;
        for (const Section &section : sections) {
            const gp_Vec a = end_tangent(section.pieces[left], true), b = end_tangent(section.pieces[m], false);
            if (a.Magnitude() < 0.5 || b.Magnitude() < 0.5 || a.Angle(b) > kAngle) {
                smooth = false;
                break;
            }
        }
        if (!smooth) {
            continue;
        }
        // One-sided second-order derivatives of the column poles, either side of the vertex.
        const std::vector<gp_Pnt> l0 = column(sections, basis, left, 1), l1 = column(sections, basis, left, 1 - eps),
                                  l2 = column(sections, basis, left, 1 - 2 * eps);
        const std::vector<gp_Pnt> r0 = column(sections, basis, m, 0), r1 = column(sections, basis, m, eps),
                                  r2 = column(sections, basis, m, 2 * eps);
        // Both sides share each row's direction, and their lengths stand in one ratio across the rows: then the two
        // patches' derivatives along the loop are parallel at every point of the shared column (G1), whatever the rows'
        // directions are. The ratio is the one the face ends' own rows have (the strictest rows), else the middle row's.
        const std::size_t count = l0.size();
        std::vector<gp_Vec> dl(count), dr(count);
        for (std::size_t r = 0; r < count; ++r) {
            dl[r] = (gp_Vec(l0[r].XYZ()) * 3 - gp_Vec(l1[r].XYZ()) * 4 + gp_Vec(l2[r].XYZ())) / (2 * eps);
            dr[r] = (gp_Vec(r0[r].XYZ()) * -3 + gp_Vec(r1[r].XYZ()) * 4 - gp_Vec(r2[r].XYZ())) / (2 * eps);
        }
        std::vector<std::size_t> anchors;
        if (basis.start != kFree) {
            anchors.push_back(0);
        }
        if (basis.finish != kFree) {
            anchors.push_back(count - 1);
        }
        if (anchors.empty()) {
            anchors.push_back(count / 2);
        }
        double ratio = 0;
        for (const std::size_t r : anchors) {
            const double mr = dr[r].Magnitude();
            ratio += mr > 1e-12 ? dl[r].Magnitude() / mr : 1.0;
        }
        ratio /= static_cast<double>(anchors.size());
        if (!(ratio > 1e-6 && std::isfinite(ratio))) {
            continue;
        }
        for (std::size_t r = 0; r < count; ++r) {
            const double ml = dl[r].Magnitude(), mr = dr[r].Magnitude();
            gp_Vec direction = ml > 1e-12 && mr > 1e-12 ? dl[r] / ml + dr[r] / mr : dl[r] + dr[r];
            direction = direction.Magnitude() > 1e-12 ? direction.Normalized() : direction;
            vertices.left[m].push_back(direction * ml);
            vertices.right[m].push_back(direction * (ml / ratio));
        }
        vertices.smooth[m] = true;
    }
    return vertices;
}

/// Segment k's patch. Columns start at 9 per segment (even fractions); a span whose seam or section fit misses (half the
/// tolerances for the seams, a fifth of the position tolerance for the sections, sampled inside the span and at its
/// ends) gets its middle, as the fillet's strips do; a miss at a column itself (more columns in a span cannot fix it)
/// halves every span. At 129 columns in all the call fails.
Patch build_patch(const std::vector<Section> &sections, const ColumnBasis &basis, const SmoothVertices &vertices, int k) {
    const int segments = static_cast<int>(sections.front().pieces.size());
    EndTangents tangents;
    if (vertices.smooth.size() == static_cast<std::size_t>(segments) && segments > 1) {
        const int next = (k + 1) % segments;
        if (vertices.smooth[k]) {
            tangents.start = vertices.right[k];
        }
        if (vertices.smooth[next]) {
            tangents.finish = vertices.left[next];
        }
    }
    const bool closed = sections.front().pieces.size() == 1;
    const Section *strongest = nullptr;
    for (const Section *end : {&sections.front(), &sections.back()}) {
        if (end->is_face && end->continuity != kFree && (!strongest || end->continuity > strongest->continuity)) {
            strongest = end;
        }
    }
    std::vector<double> fractions(kFirstColumns);
    for (int j = 0; j < kFirstColumns; ++j) {
        fractions[j] = static_cast<double>(j) / (kFirstColumns - 1);
    }
    std::vector<std::vector<gp_Pnt>> columns;
    auto fits_at = [&](const Patch &patch, double s) {
        bool fits = true;
        if (basis.start != kFree) {
            fits = fits && g2_blend::within_tolerance(face_seam_at(patch.surface, sections.front(), k, 0, 0, s));
        }
        if (basis.finish != kFree) {
            fits = fits && g2_blend::within_tolerance(face_seam_at(patch.surface, sections.back(), k, 1, 0, s));
        }
        for (int i = 0; i < basis.sections; ++i) {
            const double gap = patch.surface->Value(s, basis.v[i]).Distance(sections[i].pieces[k].value(s));
            if (gap > 2e-5) {
                fits = false;
            }
        }
        return fits;
    };
    for (;;) {
        // Columns are made once, as the fractions that need them appear (the new ones are the middles).
        while (columns.size() < fractions.size()) {
            columns.emplace_back();
        }
        for (std::size_t j = 0; j < fractions.size(); ++j) {
            if (columns[j].empty()) {
                columns[j] = column(sections, basis, k, fractions[j]);
                check_column(sections, basis, k, fractions[j], columns[j]);
            }
        }
        Patch patch;
        patch.surface = skin(columns, fractions, basis, closed, tangents);
        patch.columns = static_cast<int>(fractions.size());
        const std::size_t spans = fractions.size() - 1;
        std::vector<bool> split(spans, false);
        bool at_column = false;
        for (std::size_t j = 0; j <= spans; ++j) {
            if (!fits_at(patch, fractions[j])) {
                at_column = true;
            }
        }
        // Inside each span, and across the whole segment at the check's own samples (which never fall on columns).
        const double inside[] = {0.1, 0.3, 0.5, 0.7, 0.9};
        for (std::size_t j = 0; j < spans; ++j) {
            for (const double f : inside) {
                if (!fits_at(patch, fractions[j] + f * (fractions[j + 1] - fractions[j]))) {
                    split[j] = true;
                }
            }
        }
        for (int j = 0; j <= kCheckSamples; ++j) {
            const double s = static_cast<double>(j) / kCheckSamples;
            if (!fits_at(patch, s)) {
                const auto after = std::upper_bound(fractions.begin(), fractions.end(), s);
                const std::size_t span = std::min<std::size_t>(std::max<std::ptrdiff_t>(after - fractions.begin() - 1, 0), spans - 1);
                split[span] = true;
            }
        }
        std::size_t failing = static_cast<std::size_t>(std::count(split.begin(), split.end(), true));
        if (failing == 0 && !at_column) {
            for (int i = 0; i < basis.sections; ++i) {
                for (int j = 0; j <= kCheckSamples; ++j) {
                    const double s = static_cast<double>(j) / kCheckSamples;
                    patch.section_gap = std::max(patch.section_gap,
                                                 patch.surface->Value(s, basis.v[i]).Distance(sections[i].pieces[k].value(s)));
                }
            }
            return patch;
        }
        if (at_column) {
            failing = spans;
            split.assign(spans, true);
        }
        if (fractions.size() + failing > static_cast<std::size_t>(kMaxColumns)) {
            break;
        }
        std::vector<double> refined;
        std::vector<std::vector<gp_Pnt>> kept;
        for (std::size_t j = 0; j < fractions.size(); ++j) {
            refined.push_back(fractions[j]);
            kept.push_back(columns[j]);
            if (j < spans && split[j]) {
                refined.push_back(0.5 * (fractions[j] + fractions[j + 1]));
                kept.emplace_back();
            }
        }
        fractions = refined;
        columns = kept;
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
            // The loft shares no sub-shapes with the part: the face is copied whole (so the copied edges keep sharing
            // their vertices) and each piece takes the copy of its edge, found by position in the same exploration.
            const TopoDS_Shape face_copy = BRepBuilderAPI_Copy(section.face).Shape();
            TopTools_IndexedMapOfShape original_edges, copied_edges;
            TopExp::MapShapes(section.face, TopAbs_EDGE, original_edges);
            TopExp::MapShapes(face_copy, TopAbs_EDGE, copied_edges);
            for (const Piece &piece : section.pieces) {
                // The edge as the loop runs along it: forward when the loop's parameters increase. A circle that was
                // started at the point nearest the paired section is a new edge from that point.
                TopoDS_Edge along;
                if (piece.rephased) {
                    TopLoc_Location location;
                    double a = 0, b = 0;
                    Handle(Geom_Curve) curve = BRep_Tool::Curve(piece.edge, location, a, b);
                    curve = Handle(Geom_Curve)::DownCast(curve->Transformed(location.Transformation()));
                    const double low = std::min(piece.t0, piece.t1);
                    along = BRepBuilderAPI_MakeEdge(curve, low, low + (piece.last - piece.first)).Edge();
                    if (piece.t1 < piece.t0) {
                        along.Orientation(TopAbs_REVERSED);
                    }
                } else {
                    const int at = original_edges.FindIndex(piece.edge);
                    if (at < 1 || original_edges.Extent() != copied_edges.Extent()) {
                        throw std::runtime_error("the loft's face could not be copied");
                    }
                    along = TopoDS::Edge(copied_edges(at).Oriented(piece.t1 > piece.t0 ? TopAbs_FORWARD : TopAbs_REVERSED));
                }
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
        throw user_error("The loft could not be built.");
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
            throw user_error("A loft needs at least two sections.");
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
        const SmoothVertices vertices = plan_smooth_vertices(sections, *basis);
        std::vector<Patch> patches;
        for (std::size_t k = 0; k < segments; ++k) {
            patches.push_back(build_patch(sections, *basis, vertices, static_cast<int>(k)));
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
            throw user_error(message_for(start_face && start->continuity != kFree ? sections.front() : sections.back()));
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
