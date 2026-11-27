// Blend Surface (NURBS spec, NS-4, Task 9; ruling R10): a new sheet that joins one edge of each of two bodies.
//
// Sections pair the points of the two edges at equal arc-length fractions from their paired starts (the second edge is turned when
// that makes the sum of its ends' distances smaller). Each section is the quintic Bezier of `quintic_poles`: its tangent at each end
// leaves the edge's face across the edge, its tangent length is `bulge x circular_tangent_length`, and a G2 end also takes that face's
// normal curvature as acceleration (a G1 end none). The sections are skinned along the edges (cubic first, then quintic, doubling the
// sections from 9 to at most 129 as the G2 fillet strips do) and each end is graded against its face with `edge_continuity_against`;
// a miss after the last attempt is refused in words, never returned.
//
// Two closed edges (NS-G Task 4, R6) blend into a tube: edge b starts at its point nearest edge a's start and runs the way the two
// tangents agree there, the sections are made at the same fractions (the last is the first again and is copied, not read), and each
// pole column across the sections is interpolated periodically (`g2_skin::interpolate_periodic`, one knot vector for every column), so
// the surface is periodic in u. Its two rims are the boundary roles; the seam is no role.
#include "cocct_continuity.hpp"
#include "cocct_g2_section.hpp"
#include "cocct_g2_skin.hpp"
#include "cocct_sheet.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRep_Tool.hxx>
#include <Geom2d_Curve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <vector>

using namespace cocct;

namespace {

constexpr double kTouching = 0.01;               // mm: a section chord under this is "touching"
constexpr double kPositionLimit = 1e-4;          // mm, the thresholds of Kernel.continuity
constexpr double kAngleLimit = 0.01 * kPi / 180; // rad
constexpr double kCurvatureRelative = 0.01;
constexpr double kCurvatureFloor = 1e-4;         // 1/mm
constexpr int kTableIntervals = 1024;
constexpr int kGradeSamples = 32;

struct attempt {
    int sections;
    int degree;
};
constexpr std::array<attempt, 6> kAttempts{{{9, 3}, {9, 5}, {17, 5}, {33, 5}, {65, 5}, {129, 5}}};

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
    /// The arc length from the first parameter to `t` (interpolated between the table's samples).
    double length_at(double t) const {
        const auto it = std::upper_bound(parameter.begin(), parameter.end(), t);
        const int i = std::clamp(static_cast<int>(it - parameter.begin()) - 1, 0, kTableIntervals - 1);
        const double span = parameter[i + 1] - parameter[i];
        const double fraction = span > 1e-300 ? (t - parameter[i]) / span : 0.0;
        return length[i] + (length[i + 1] - length[i]) * std::clamp(fraction, 0.0, 1.0);
    }
    double parameter_at(double wanted) const {
        const auto it = std::upper_bound(length.begin(), length.end(), wanted);
        const int i = std::clamp(static_cast<int>(it - length.begin()) - 1, 0, kTableIntervals - 1);
        const double span = length[i + 1] - length[i];
        const double fraction = span > 1e-300 ? (wanted - length[i]) / span : 0.0;
        return parameter[i] + (parameter[i + 1] - parameter[i]) * std::clamp(fraction, 0.0, 1.0);
    }
};

/// What one side of the blend reads from its edge and the face it continues.
struct blend_end {
    int continuity = 1;
    double bulge = 1;
    TopoDS_Edge edge;
    std::unique_ptr<BRepAdaptor_Curve> curve;
    length_table table;
    std::vector<TopoDS_Face> faces;
    TopoDS_Face face;
    std::unique_ptr<continuity_detail::face_side> side;
    double sign = 1; // turns `normal x tangent` into the direction that leaves the face across the edge
    bool reversed = false;
    bool closed = false;
    double origin = 0; // closed: the fraction of the edge's length at which the blend's start lies

    /// The fraction of this edge's own length that pairs with the blend's fraction `f`: turned when `reversed`, and for a closed edge
    /// counted from `origin` and wrapped round.
    double local(double f) const {
        if (!closed) {
            return reversed ? 1.0 - f : f;
        }
        const double s = origin + (reversed ? -f : f);
        return s - std::floor(s);
    }

    gp_Pnt point_at_fraction(double f) const { return curve->Value(table.parameter_at(f * table.total())); }
};

/// The end condition a section takes at fraction `f` of the end's own edge.
struct end_reading {
    g2::EndCondition condition;
    gp_Pnt point;
};

end_reading read_end(const blend_end &end, double f) {
    const double t = end.table.parameter_at(f * end.table.total());
    gp_Pnt point;
    gp_Vec tangent;
    end.curve->D1(t, point, tangent);
    if (tangent.Magnitude() < 1e-12) {
        throw user_error("An edge has no direction along its length.");
    }
    tangent.Normalize();
    const continuity_detail::side_sample read = continuity_detail::sample_side(*end.side, t, tangent);
    if (!read.ok) {
        throw user_error("An edge can't be read along its face.");
    }
    gp_Vec across = read.normal.Crossed(tangent);
    if (across.Magnitude() < 1e-12) {
        throw user_error("An edge can't be read along its face.");
    }
    const gp_Vec leaving = across.Normalized() * end.sign;
    end_reading out;
    out.point = point;
    out.condition.position = {point.X(), point.Y(), point.Z()};
    out.condition.direction = {leaving.X(), leaving.Y(), leaving.Z()};
    if (end.continuity == 2) {
        const gp_Vec acceleration = read.normal * read.curvature;
        out.condition.acceleration = {acceleration.X(), acceleration.Y(), acceleration.Z()};
    }
    return out;
}

/// The blend surface through `count` sections skinned at `degree`.
Handle(Geom_BSplineSurface) build_surface(const blend_end &a, const blend_end &b, int count, int degree, const occt_cancel *cancel) {
    const bool closed = a.closed;
    std::vector<std::vector<double>> rows;
    std::vector<double> fractions;
    for (int j = 0; j < count; ++j) {
        poll(cancel);
        const double f = static_cast<double>(j) / (count - 1);
        if (closed && j == count - 1) {
            rows.push_back(rows.front()); // the seam is sampled once
            fractions.push_back(f);
            break;
        }
        end_reading first = read_end(a, a.local(f));
        end_reading second = read_end(b, b.local(f));
        // The blend runs out of the second edge's face, so its direction there is the way into the face.
        for (double &c : second.condition.direction) {
            c = -c;
        }
        const double chord = first.point.Distance(second.point);
        if (chord < kTouching) {
            throw user_error("The edges touch; a blend needs a gap between them.");
        }
        const double theta = g2::turning_angle(first.condition.direction, second.condition.direction);
        const double length = g2::circular_tangent_length(chord, theta);
        const auto poles = g2::quintic_poles(first.condition, a.bulge * length, second.condition, b.bulge * length);
        std::vector<double> row;
        for (const g2::Vec &q : poles) {
            row.insert(row.end(), q.begin(), q.end());
        }
        rows.push_back(row);
        fractions.push_back(f);
    }
    g2_skin::Spline skin;
    try {
        skin = closed ? g2_skin::interpolate_periodic(rows, fractions, degree) : g2_skin::interpolate_open(rows, fractions, {}, degree);
    } catch (const g2_skin::singular_system &) {
        throw user_error("The blend surface couldn't be made.");
    }
    const int pole_count = static_cast<int>(skin.poles.size());
    TColgp_Array2OfPnt poles(1, pole_count, 1, 6);
    for (int k = 0; k < pole_count; ++k) {
        const std::vector<double> &q = skin.poles[static_cast<std::size_t>(k)];
        for (int i = 0; i < 6; ++i) {
            poles.SetValue(k + 1, i + 1, gp_Pnt(q[3 * i], q[3 * i + 1], q[3 * i + 2]));
        }
    }
    const int knot_count = static_cast<int>(skin.knots.size());
    TColStd_Array1OfReal uknots(1, knot_count);
    TColStd_Array1OfInteger umults(1, knot_count);
    for (int k = 0; k < knot_count; ++k) {
        uknots.SetValue(k + 1, skin.knots[static_cast<std::size_t>(k)]);
        umults.SetValue(k + 1, skin.mults[static_cast<std::size_t>(k)]);
    }
    TColStd_Array1OfReal vknots(1, 2);
    vknots.SetValue(1, 0);
    vknots.SetValue(2, 1);
    TColStd_Array1OfInteger vmults(1, 2);
    vmults.SetValue(1, 6);
    vmults.SetValue(2, 6);
    return new Geom_BSplineSurface(poles, uknots, vknots, umults, vmults, skin.degree, 5, closed ? Standard_True : Standard_False,
                                   Standard_False);
}

/// -1 (not even G0), 0, 1 or 2.
int grade_of(const occt_edge_continuity &found) {
    if (!(found.position_gap <= kPositionLimit)) {
        return -1;
    }
    if (!(found.angle_gap <= kAngleLimit)) {
        return 0;
    }
    return (found.curvature_gap <= kCurvatureRelative || found.absolute_curvature_gap <= kCurvatureFloor) ? 2 : 1;
}

/// The edge of `face` at v = 0 (`low`) or v = 1.
TopoDS_Edge iso_edge(const TopoDS_Face &face, bool low) {
    const TopTools_IndexedMapOfShape edges = map_of(face, TopAbs_EDGE);
    for (int e = 1; e <= edges.Extent(); ++e) {
        const TopoDS_Edge edge = TopoDS::Edge(edges(e));
        if (BRep_Tool::Degenerated(edge)) {
            continue;
        }
        double first = 0, last = 0;
        const Handle(Geom2d_Curve) on_face = BRep_Tool::CurveOnSurface(edge, face, first, last);
        if (on_face.IsNull()) {
            continue;
        }
        const double y = on_face->Value((first + last) / 2).Y();
        if (low ? y < 1e-6 : y > 1.0 - 1e-6) {
            return edge;
        }
    }
    throw user_error("The blend surface couldn't be made.");
}

/// Reads `end`'s edge, its faces and its length table from `shape`; the face is chosen later.
void open_end(blend_end &end, const occt_shape *shape, int edge_index) {
    if (!shape || shape->shape.IsNull()) {
        throw user_error("That surface no longer exists.");
    }
    const TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
    if (edge_index < 1 || edge_index > edges.Extent()) {
        throw user_error("That edge no longer exists.");
    }
    end.edge = TopoDS::Edge(edges(edge_index));
    TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
    TopExp::MapShapesAndAncestors(shape->shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);
    end.faces = distinct_faces(end.edge, edge_faces);
    if (end.faces.empty() || BRep_Tool::Degenerated(end.edge)) {
        throw user_error("The edge doesn't lie on a face.");
    }
    end.curve = std::make_unique<BRepAdaptor_Curve>(end.edge);
    const double lo = end.curve->FirstParameter(), hi = end.curve->LastParameter();
    BRepAdaptor_Curve &curve = *end.curve;
    end.table.build(lo, hi, [&](double t) { return curve.Value(t); });
    if (end.table.total() < 1e-9) {
        throw user_error("Blend Surface needs edges that have a length.");
    }
    end.closed = curve.Value(lo).Distance(curve.Value(hi)) < 1e-6;
}

/// Makes `b` start at its point nearest `a`'s start and run the way the tangents agree there (closed edges).
void pair_closed(const blend_end &a, blend_end &b) {
    const gp_Pnt start = a.curve->Value(a.table.parameter.front());
    int nearest = 0;
    double nearest_distance = 1e300;
    for (int i = 0; i <= kTableIntervals; ++i) {
        const double d = b.curve->Value(b.table.parameter[i]).Distance(start);
        if (d < nearest_distance) {
            nearest_distance = d, nearest = i;
        }
    }
    double lo = b.table.parameter[std::max(nearest - 1, 0)], hi = b.table.parameter[std::min(nearest + 1, kTableIntervals)];
    for (int step = 0; step < 60; ++step) {
        const double m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
        if (b.curve->Value(m1).Distance(start) < b.curve->Value(m2).Distance(start)) {
            hi = m2;
        } else {
            lo = m1;
        }
    }
    const double t_seam = 0.5 * (lo + hi);
    gp_Pnt point;
    gp_Vec tangent_a, tangent_b;
    a.curve->D1(a.table.parameter.front(), point, tangent_a);
    b.curve->D1(t_seam, point, tangent_b);
    if (tangent_a.Magnitude() < 1e-12 || tangent_b.Magnitude() < 1e-12) {
        throw user_error("An edge has no direction along its length.");
    }
    b.origin = b.table.length_at(t_seam) / b.table.total();
    b.reversed = tangent_a.Dot(tangent_b) < 0.0;
}

/// Picks the face of `end` whose leaving direction at the edge's middle points most toward `other` (R10), and the sign that makes
/// `normal x tangent` leave it.
void choose_face(blend_end &end, const gp_Pnt &other) {
    const double t_mid = end.table.parameter_at(0.5 * end.table.total());
    gp_Pnt mid_point;
    gp_Vec tangent;
    end.curve->D1(t_mid, mid_point, tangent);
    if (tangent.Magnitude() < 1e-12) {
        throw user_error("An edge has no direction at its middle.");
    }
    tangent.Normalize();
    gp_Vec toward(mid_point, other);
    if (toward.Magnitude() > 1e-12) {
        toward.Normalize();
    }
    int chosen = -1;
    double best = -2.0;
    for (std::size_t k = 0; k < end.faces.size(); ++k) {
        const continuity_detail::face_side candidate(end.edge, end.faces[k]);
        const continuity_detail::side_sample here = continuity_detail::sample_side(candidate, t_mid, tangent);
        if (!here.ok) {
            continue;
        }
        gp_Vec across = here.normal.Crossed(tangent);
        if (across.Magnitude() < 1e-12) {
            continue;
        }
        across.Normalize();
        const continuity_detail::inward found = continuity_detail::inward_direction(
            end.faces[k], BRep_Tool::Surface(end.faces[k]), mid_point, here.normal, tangent);
        if (!found.found) {
            continue;
        }
        const double orientation = found.direction.Dot(across) > 0 ? -1.0 : 1.0; // leaving = -inward
        const double score = (across * orientation).Dot(toward);
        if (score > best) {
            best = score;
            chosen = static_cast<int>(k);
            end.sign = orientation;
        }
    }
    if (chosen < 0) {
        throw user_error("An edge can't be read along its face.");
    }
    end.face = end.faces[static_cast<std::size_t>(chosen)];
    end.side = std::make_unique<continuity_detail::face_side>(end.edge, end.face);
}

occt_shape *blend(const occt_shape *first_shape, int first_edge, int first_continuity, double first_bulge,
                  const occt_shape *second_shape, int second_edge, int second_continuity, double second_bulge,
                  const occt_cancel *cancel, occt_history *history, occt_boundary_roles *roles) {
    occt_initialize();
    *history = occt_history{};
    *roles = occt_boundary_roles{};
    if ((first_continuity != 1 && first_continuity != 2) || (second_continuity != 1 && second_continuity != 2)) {
        throw user_error("Blend Surface joins at G1 or G2.");
    }
    for (const double bulge : {first_bulge, second_bulge}) {
        if (!(bulge >= 0.1 && bulge <= 2.0)) {
            throw user_error("The bulge must be from 0.1 to 2.");
        }
    }
    blend_end a, b;
    a.continuity = first_continuity;
    a.bulge = first_bulge;
    b.continuity = second_continuity;
    b.bulge = second_bulge;
    open_end(a, first_shape, first_edge);
    open_end(b, second_shape, second_edge);
    if (a.edge.IsSame(b.edge)) {
        throw user_error("Blend Surface needs two different edges.");
    }
    poll(cancel);

    if (a.closed != b.closed) {
        throw user_error("Blend Surface needs both edges closed, or both open.");
    }
    if (a.closed) {
        pair_closed(a, b);
    } else {
        // The second edge runs the way that makes the ends' distances smaller.
        const gp_Pnt a0 = a.point_at_fraction(0), a1 = a.point_at_fraction(1);
        const gp_Pnt b0 = b.point_at_fraction(0), b1 = b.point_at_fraction(1);
        b.reversed = a0.Distance(b1) + a1.Distance(b0) < a0.Distance(b0) + a1.Distance(b1) - 1e-9;
    }
    choose_face(a, b.point_at_fraction(b.local(0.5)));
    choose_face(b, a.point_at_fraction(a.local(0.5)));

    for (std::size_t k = 0; k < kAttempts.size(); ++k) {
        poll(cancel);
        const Handle(Geom_BSplineSurface) surface = build_surface(a, b, kAttempts[k].sections, kAttempts[k].degree, cancel);
        BRepBuilderAPI_MakeFace maker(surface, 1e-7);
        if (!maker.IsDone()) {
            throw user_error("The blend surface couldn't be made.");
        }
        const TopoDS_Face face = maker.Face();
        const blend_end *ends[2] = {&a, &b};
        bool met = true;
        bool curvature_missed = false;
        for (int side = 0; side < 2; ++side) {
            poll(cancel);
            int reached = -1;
            try {
                const occt_edge_continuity found =
                    edge_continuity_against(iso_edge(face, side == 0), face, ends[side]->face, kGradeSamples);
                reached = grade_of(found);
            } catch (const user_error &error) {
                if (std::string(error.what()) == kCancelled) {
                    throw;
                }
            }
            if (reached < ends[side]->continuity) {
                met = false;
                curvature_missed = curvature_missed || ends[side]->continuity == 2;
            }
        }
        if (met) {
            if (!BRepCheck_Analyzer(face).IsValid()) {
                throw user_error("The blend surface couldn't be made.");
            }
            history_builder records(face);
            records.add(face, OCCT_FROM_SEGMENT, 0, 0);
            records.move_into(history);
            boundary_table table(face);
            const TopTools_IndexedMapOfShape edges = map_of(face, TopAbs_EDGE);
            for (int e = 1; e <= edges.Extent(); ++e) {
                const TopoDS_Edge edge = TopoDS::Edge(edges(e));
                if (BRep_Tool::Degenerated(edge) || BRep_Tool::IsClosed(edge, face)) { // a tube's seam is no role
                    continue;
                }
                double lo = 0, hi = 0;
                const Handle(Geom2d_Curve) on_face = BRep_Tool::CurveOnSurface(edge, face, lo, hi);
                if (on_face.IsNull()) {
                    continue;
                }
                const gp_Pnt2d middle = on_face->Value((lo + hi) / 2);
                if (middle.Y() < 1e-6) {
                    table.set(edge, kBoundaryStart);
                } else if (middle.Y() > 1.0 - 1e-6) {
                    table.set(edge, kBoundaryEnd);
                } else if (middle.X() < 1e-6) {
                    table.set(edge, kBoundaryRail, 0);
                } else if (middle.X() > 1.0 - 1e-6) {
                    table.set(edge, kBoundaryRail, 1);
                }
            }
            table.move_into(roles);
            return new occt_shape{face};
        }
        if (k + 1 == kAttempts.size()) {
            throw user_error(curvature_missed ? "The blend can't be made curvature continuous along these edges."
                                              : "The blend can't be made tangent continuous along these edges.");
        }
    }
    throw user_error("The blend surface couldn't be made.");
}

} // namespace

extern "C" {

occt_shape *occt_blend_surface(const occt_shape *first, int first_edge, int first_continuity, double first_bulge,
                               const occt_shape *second, int second_edge, int second_continuity, double second_bulge,
                               const occt_cancel *cancel, occt_history *history, occt_boundary_roles *roles, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        return blend(first, first_edge, first_continuity, first_bulge, second, second_edge, second_continuity, second_bulge, cancel,
                     history, roles);
    });
}

} // extern "C"
