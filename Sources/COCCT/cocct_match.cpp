// Match Surface: a sheet of one face changed along one untrimmed iso edge so that it meets a target edge at G0, G1 or G2
// (NURBS spec, NS-4, Task 8; ruling R9).
//
// The cross degree is raised to at least c + 1 and the along degree to at least 3 (both exact, in homogeneous coordinates for a
// rational surface), so rows 0..c of the net carry the match and the opposite edge never moves. Rows are then fitted one at a time by
// linear least squares with every weight held fixed: with fixed weights S = A / W is linear in the poles, and so are its r-derivatives,
// and at r = 0 of a clamped direction the coefficient of pole (k, j) in the k-th r-derivative is w_kj N_k^(k)(0) N_j(s) / W(s, 0), so the
// right-hand side is the target minus the same derivative of the net with row k zeroed. Each result is graded with
// `edge_continuity_against` and, when it falls short, the spans along the edge are doubled (up to 5 times).
//
// A closed edge (NS-G Task 3, R5) is a closed iso of a surface periodic along it, matched to a closed target edge. The surface stays
// periodic: the along-edge basis wraps (OCCT's periodic pole convention, see `periodic_flat`), no pole row is pinned, and the normal
// equations are cyclic (`band_border_system`: a banded interior plus a border of the last `degree` poles, as Rebuild's periodic fit). The pairing starts at the target parameter nearest the sheet's
// seam point and runs the way the two tangents agree there.
#include "cocct_arc_table.hpp"
#include "cocct_band_border.hpp"
#include "cocct_continuity.hpp"
#include "cocct_control_net.hpp"
#include "cocct_iso_sides.hpp"
#include "cocct_sheet.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRep_Tool.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Standard_Failure.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

using namespace cocct;
using namespace cocct::iso;
using namespace cocct::continuity_detail;

namespace {

constexpr double kEndGap = 0.01;                  // mm: ends further apart than this refuse
constexpr double kPositionLimit = 1e-4;           // mm, the thresholds of Kernel.continuity
constexpr double kAngleLimit = 0.01 * kPi / 180;  // rad
constexpr double kCurvatureRelative = 0.01;
constexpr double kCurvatureFloor = 1e-4;          // 1/mm
constexpr int kRefinements = 5;
constexpr long kMaxPoles = 100000;
constexpr int kAlongDegree = 3;                   // the along direction is raised to this at least

// ---- B-spline basis functions ---------------------------------------------------------------------------------------------

std::vector<double> flat_of(const Handle(Geom_BSplineSurface) &surface, bool u_direction) {
    std::vector<double> flat;
    const int knots = u_direction ? surface->NbUKnots() : surface->NbVKnots();
    for (int k = 1; k <= knots; ++k) {
        const int mult = u_direction ? surface->UMultiplicity(k) : surface->VMultiplicity(k);
        const double value = u_direction ? surface->UKnot(k) : surface->VKnot(k);
        for (int m = 0; m < mult; ++m) {
            flat.push_back(value);
        }
    }
    return flat;
}

/// The knot span (0-based index `i` with `flat[i] <= t < flat[i + 1]`) that holds `t`, the last one at the end of the range.
int find_span(const std::vector<double> &flat, int degree, int poles, double t) {
    if (t >= flat[poles]) {
        return poles - 1;
    }
    if (t <= flat[degree]) {
        return degree;
    }
    int lo = degree, hi = poles;
    while (hi - lo > 1) {
        const int mid = (lo + hi) / 2;
        if (t >= flat[mid]) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    return lo;
}

/// The values and derivatives up to `orders` of the `degree + 1` basis functions that are non-zero in `span`
/// (The NURBS Book, A2.3): `ders[k][r]` is the k-th derivative of the function with index `span - degree + r`.
std::vector<std::vector<double>> basis_derivatives(const std::vector<double> &knots, int degree, int span, double t, int orders) {
    const int p = degree;
    std::vector<std::vector<double>> ndu(p + 1, std::vector<double>(p + 1, 0.0));
    std::vector<double> left(p + 1, 0.0), right(p + 1, 0.0);
    ndu[0][0] = 1.0;
    for (int j = 1; j <= p; ++j) {
        left[j] = t - knots[span + 1 - j];
        right[j] = knots[span + j] - t;
        double saved = 0.0;
        for (int r = 0; r < j; ++r) {
            ndu[j][r] = right[r + 1] + left[j - r];
            const double temp = ndu[r][j - 1] / ndu[j][r];
            ndu[r][j] = saved + right[r + 1] * temp;
            saved = left[j - r] * temp;
        }
        ndu[j][j] = saved;
    }
    std::vector<std::vector<double>> ders(orders + 1, std::vector<double>(p + 1, 0.0));
    for (int j = 0; j <= p; ++j) {
        ders[0][j] = ndu[j][p];
    }
    std::vector<std::vector<double>> a(2, std::vector<double>(p + 1, 0.0));
    for (int r = 0; r <= p; ++r) {
        int s1 = 0, s2 = 1;
        a[0][0] = 1.0;
        for (int k = 1; k <= orders; ++k) {
            double d = 0.0;
            const int rk = r - k, pk = p - k;
            if (r >= k) {
                a[s2][0] = a[s1][0] / ndu[pk + 1][rk];
                d = a[s2][0] * ndu[rk][pk];
            }
            const int j1 = rk >= -1 ? 1 : -rk;
            const int j2 = (r - 1 <= pk) ? k - 1 : p - r;
            for (int j = j1; j <= j2; ++j) {
                a[s2][j] = (a[s1][j] - a[s1][j - 1]) / ndu[pk + 1][rk + j];
                d += a[s2][j] * ndu[rk + j][pk];
            }
            if (r <= pk) {
                a[s2][k] = -a[s1][k - 1] / ndu[pk + 1][r];
                d += a[s2][k] * ndu[r][pk];
            }
            ders[k][r] = d;
            std::swap(s1, s2);
        }
    }
    double factor = p;
    for (int k = 1; k <= orders; ++k) {
        for (int j = 0; j <= p; ++j) {
            ders[k][j] *= factor;
        }
        factor *= (p - k);
    }
    return ders;
}

/// The knots of a periodic direction as one sequence over five periods (cycle -2 to 2), the cycle 0 starting at `origin`. OCCT keeps a
/// periodic direction's `n` poles with distinct knots K_0..K_m (K_m = K_0 + period) of multiplicities M_i whose first m sum to `n`;
/// the span that holds K_0 uses poles 0..p, so basis function `j` of this sequence is pole `(j - origin - M_0 + 1 + p) mod n`.
struct periodic_knots {
    std::vector<double> sequence;
    int origin = 0;
    int poles = 0;
};

periodic_knots periodic_flat(const Handle(Geom_BSplineSurface) &surface, bool u_direction) {
    periodic_knots out;
    const int knots = u_direction ? surface->NbUKnots() : surface->NbVKnots();
    const double first = u_direction ? surface->UKnot(1) : surface->VKnot(1);
    const double last = u_direction ? surface->UKnot(knots) : surface->VKnot(knots);
    const double period = last - first;
    for (int cycle = -2; cycle <= 2; ++cycle) {
        if (cycle == 0) {
            out.origin = static_cast<int>(out.sequence.size());
        }
        for (int k = 1; k < knots; ++k) {
            const int mult = u_direction ? surface->UMultiplicity(k) : surface->VMultiplicity(k);
            const double value = (u_direction ? surface->UKnot(k) : surface->VKnot(k)) + cycle * period;
            for (int m = 0; m < mult; ++m) {
                out.sequence.push_back(value);
            }
            if (cycle == 0) {
                out.poles += mult;
            }
        }
    }
    return out;
}

/// The span (index into `knots.sequence`) of cycle 0 that holds `t` in [K_0, K_m).
int find_periodic_span(const periodic_knots &knots, double t) {
    const auto begin = knots.sequence.begin() + knots.origin;
    const auto it = std::upper_bound(begin, begin + knots.poles, t);
    return std::max(knots.origin, static_cast<int>(it - knots.sequence.begin()) - 1);
}

// ---- the sheet seen with its edge at the start of the cross direction ------------------------------------------------------

/// The surface with `cross_u` naming the cross direction (r, across the edge, 0 at the edge) and the other the along direction (s).
struct net {
    Handle(Geom_BSplineSurface) surface;
    bool cross_u = true;

    int cross_poles() const { return cross_u ? surface->NbUPoles() : surface->NbVPoles(); }
    int along_poles() const { return cross_u ? surface->NbVPoles() : surface->NbUPoles(); }
    int cross_degree() const { return cross_u ? surface->UDegree() : surface->VDegree(); }
    int along_degree() const { return cross_u ? surface->VDegree() : surface->UDegree(); }
    bool rational() const { return surface->IsURational() || surface->IsVRational(); }
    gp_Pnt pole(int c, int a) const { return cross_u ? surface->Pole(c, a) : surface->Pole(a, c); }
    void set_pole(int c, int a, const gp_Pnt &p) const { cross_u ? surface->SetPole(c, a, p) : surface->SetPole(a, c, p); }
    double weight(int c, int a) const {
        if (!rational()) {
            return 1.0;
        }
        return cross_u ? surface->Weight(c, a) : surface->Weight(a, c);
    }
    double cross_start() const { double u0, u1, v0, v1; surface->Bounds(u0, u1, v0, v1); return cross_u ? u0 : v0; }
    double along_start() const { double u0, u1, v0, v1; surface->Bounds(u0, u1, v0, v1); return cross_u ? v0 : u0; }
    double along_end() const { double u0, u1, v0, v1; surface->Bounds(u0, u1, v0, v1); return cross_u ? v1 : u1; }
    bool along_periodic() const { return cross_u ? surface->IsVPeriodic() : surface->IsUPeriodic(); }
    bool cross_periodic() const { return cross_u ? surface->IsUPeriodic() : surface->IsVPeriodic(); }
    std::vector<double> cross_flat() const { return flat_of(surface, cross_u); }
    /// The along knots: for a periodic direction the extended sequence of `periodic_flat`.
    std::vector<double> along_flat() const {
        return along_periodic() ? periodic_flat(surface, !cross_u).sequence : flat_of(surface, !cross_u);
    }
    int along_first_multiplicity() const { return cross_u ? surface->VMultiplicity(1) : surface->UMultiplicity(1); }

    /// The point at along parameter `a` on the edge row, the first and second derivatives across, and the first along.
    void evaluate(double a, gp_Pnt &p, gp_Vec &cross1, gp_Vec &cross2, gp_Vec &along1) const {
        const double r = cross_start();
        gp_Vec du, dv, duu, dvv, duv;
        if (cross_u) {
            surface->D2(r, a, p, du, dv, duu, dvv, duv);
            cross1 = du, cross2 = duu, along1 = dv;
        } else {
            surface->D2(a, r, p, du, dv, duu, dvv, duv);
            cross1 = dv, cross2 = dvv, along1 = du;
        }
    }
    gp_Pnt edge_point(double a) const {
        gp_Pnt p;
        gp_Vec c1, c2, a1;
        evaluate(a, p, c1, c2, a1);
        return p;
    }
};

// ---- the match ----------------------------------------------------------------------------------------------------------------

/// What the target says at each sample along the edge.
struct sample_data {
    double s = 0;
    gp_Pnt point;
    gp_Vec leaving;     // unit, in the target's tangent plane, perpendicular to the edge, away from the target face
    gp_Vec normal;      // the target's oriented unit normal
    double curvature = 0; // its normal curvature across the edge, against `normal`
    double speed = 0;   // |S_r| of the sheet before the match
    gp_Vec cross2;      // S_rr of the sheet before the match
};

/// Splits the grade a measured edge reaches: -1 (not even G0), 0, 1 or 2.
int grade_of(const occt_edge_continuity &found) {
    if (!(found.position_gap <= kPositionLimit)) {
        return -1;
    }
    if (!(found.angle_gap <= kAngleLimit)) {
        return 0;
    }
    return (found.curvature_gap <= kCurvatureRelative || found.absolute_curvature_gap <= kCurvatureFloor) ? 2 : 1;
}

std::string miss_sentence(int asked, int reached) {
    if (asked == 0 || reached < 0) {
        return "Match couldn't make the edge meet the target within 0.0001 mm.";
    }
    if (asked == 1) {
        return "Match couldn't make the edge tangent continuous with the target; it reached G0. Choose G0, or rebuild the surface "
               "with more spans.";
    }
    return std::string("Match couldn't make the edge curvature continuous with the target; it reached G") + std::to_string(reached) +
           ". Choose G" + std::to_string(reached) + ", or rebuild the surface with more spans.";
}

/// Makes the surface periodic along its edge direction when it already closes there: the end pole rows coincide within
/// `kNetCoincidence` with equal weights, OCCT accepts the change, the periodic surface reproduces the original on a grid, and the
/// along first derivative and the cross derivative agree at the two ends (so the seam is smooth). False when any of that fails.
bool make_along_periodic(net &sheet) {
    const int na = sheet.along_poles(), nc = sheet.cross_poles();
    for (int c = 1; c <= nc; ++c) {
        if (sheet.pole(c, 1).Distance(sheet.pole(c, na)) > kNetCoincidence ||
            std::abs(sheet.weight(c, 1) - sheet.weight(c, na)) > 1e-9) {
            return false;
        }
    }
    Handle(Geom_BSplineSurface) periodic = Handle(Geom_BSplineSurface)::DownCast(sheet.surface->Copy());
    try {
        if (sheet.cross_u) {
            periodic->SetVPeriodic();
        } else {
            periodic->SetUPeriodic();
        }
    } catch (const Standard_Failure &) {
        return false;
    }
    net candidate;
    candidate.surface = periodic;
    candidate.cross_u = sheet.cross_u;
    if (!candidate.along_periodic()) {
        return false;
    }
    const double a0 = sheet.along_start(), a1 = sheet.along_end();
    const double r0 = sheet.cross_start();
    double u0, u1, v0, v1;
    sheet.surface->Bounds(u0, u1, v0, v1);
    const double r1 = sheet.cross_u ? u1 : v1;
    for (int ci = 0; ci <= 2; ++ci) {
        const double r = r0 + (r1 - r0) * ci / 2.0;
        for (int i = 0; i <= 32; ++i) {
            const double a = a0 + (a1 - a0) * i / 32.0;
            const gp_Pnt was = sheet.cross_u ? sheet.surface->Value(r, a) : sheet.surface->Value(a, r);
            const gp_Pnt now = sheet.cross_u ? periodic->Value(r, a) : periodic->Value(a, r);
            if (was.Distance(now) > kNetCoincidence) {
                return false;
            }
        }
        // The seam is smooth when both first derivatives (along and across) are the same at its two ends.
        gp_Pnt p;
        gp_Vec c_start, c_end, a_start, a_end;
        gp_Vec du, dv, duu, dvv, duv;
        for (int end = 0; end < 2; ++end) {
            const double a = end == 0 ? a0 : a1;
            if (sheet.cross_u) {
                sheet.surface->D2(r, a, p, du, dv, duu, dvv, duv);
                (end == 0 ? c_start : c_end) = du;
                (end == 0 ? a_start : a_end) = dv;
            } else {
                sheet.surface->D2(a, r, p, du, dv, duu, dvv, duv);
                (end == 0 ? c_start : c_end) = dv;
                (end == 0 ? a_start : a_end) = du;
            }
        }
        const double scale = 1.0 + std::max(a_start.Magnitude(), c_start.Magnitude());
        if ((a_start - a_end).Magnitude() > 1e-6 * scale || (c_start - c_end).Magnitude() > 1e-6 * scale) {
            return false;
        }
    }
    sheet.surface = periodic;
    return true;
}

occt_shape *match(const occt_shape *shape, int face_index, int edge_index, const occt_shape *target, int target_edge_index,
                  int continuity, const occt_cancel *cancel) {
    occt_initialize();
    if (!shape || shape->shape.IsNull() || !target || target->shape.IsNull()) {
        throw user_error("That surface no longer exists.");
    }
    if (continuity < 0 || continuity > 2) {
        throw user_error("Match Surface joins at G0, G1 or G2.");
    }
    const bool input_valid = BRepCheck_Analyzer(shape->shape).IsValid();

    // The sheet's edge: an open edge of one face, untrimmed.
    edit_copy edit = make_edit_copy(shape, face_index);
    const TopoDS_Face face = edit.face();
    const TopTools_IndexedMapOfShape edges = map_of(edit.work, TopAbs_EDGE);
    if (edge_index < 1 || edge_index > edges.Extent()) {
        throw user_error("That edge no longer exists.");
    }
    const TopoDS_Edge edge = TopoDS::Edge(edges(edge_index).Oriented(TopAbs_FORWARD));
    TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
    TopExp::MapShapesAndAncestors(edit.work, TopAbs_EDGE, TopAbs_FACE, edge_faces);
    if (!is_boundary_edge(edge, distinct_faces(edge, edge_faces))) {
        throw user_error("Match Surface changes an open edge of the sheet; this edge has two faces.");
    }
    const bounds original_bounds = bounds_of(edit.surface);
    double pcurve_first = 0, pcurve_last = 0;
    const Handle(Geom2d_Curve) pcurve = BRep_Tool::CurveOnSurface(edge, face, pcurve_first, pcurve_last);
    if (pcurve.IsNull()) {
        throw user_error("A face's edge has no curve on its surface.");
    }
    const side_curve side = classify(pcurve, pcurve_first, pcurve_last, original_bounds);
    if (side.side < 0) {
        throw user_error("Match Surface works on an untrimmed edge of its surface; this edge is a trim.");
    }
    net base;
    base.surface = Handle(Geom_BSplineSurface)::DownCast(edit.surface->Copy());
    base.cross_u = side.side == kUStart || side.side == kUEnd;
    if (base.cross_periodic()) {
        // Unreachable in practice: an untrimmed edge that runs along a direction whose other direction is periodic is that
        // direction's seam (or its two ends meeting), which has two faces and is refused above.
        throw user_error("Match Surface can't match an edge of a surface that closes on itself yet.");
    }
    bool cyclic = base.along_periodic(); // a closed iso of a surface periodic along it (R5)
    if (side.side == kUEnd) {
        base.surface->UReverse();
    } else if (side.side == kVEnd) {
        base.surface->VReverse();
    }
    {
        const int cross = std::max(base.cross_degree(), continuity + 1);
        const int along = std::max(base.along_degree(), kAlongDegree);
        base.surface->IncreaseDegree(base.cross_u ? cross : along, base.cross_u ? along : cross);
    }
    if (cyclic && !base.along_periodic()) {
        throw user_error("Match couldn't keep the surface closed.");
    }
    const double r0 = base.cross_start();
    const double a0 = base.along_start(), a1 = base.along_end();

    // The target edge and the face it continues.
    const TopTools_IndexedMapOfShape target_edges = map_of(target->shape, TopAbs_EDGE);
    if (target_edge_index < 1 || target_edge_index > target_edges.Extent()) {
        throw user_error("That edge no longer exists.");
    }
    const TopoDS_Edge target_edge = TopoDS::Edge(target_edges(target_edge_index));
    TopTools_IndexedDataMapOfShapeListOfShape target_edge_faces;
    TopExp::MapShapesAndAncestors(target->shape, TopAbs_EDGE, TopAbs_FACE, target_edge_faces);
    const std::vector<TopoDS_Face> target_faces = distinct_faces(target_edge, target_edge_faces);
    if (target_faces.empty() || BRep_Tool::Degenerated(target_edge)) {
        throw user_error("The target edge doesn't lie on a face.");
    }
    BRepAdaptor_Curve target_curve(target_edge);
    const double t_lo = target_curve.FirstParameter(), t_hi = target_curve.LastParameter();

    // The sheet's edge and the target's, paired by the fraction of their length from the end of the target nearer the edge's start.
    length_table sheet_table, target_table;
    sheet_table.build(a0, a1, [&](double a) { return base.edge_point(a); });
    target_table.build(t_lo, t_hi, [&](double t) { return target_curve.Value(t); });
    if (sheet_table.total() < 1e-9 || target_table.total() < 1e-9) {
        throw user_error("Match Surface needs edges that have a length.");
    }
    const gp_Pnt sheet_start = base.edge_point(a0), sheet_end = base.edge_point(a1);
    const gp_Pnt target_lo = target_curve.Value(t_lo), target_hi = target_curve.Value(t_hi);
    const bool closed_target = target_lo.Distance(target_hi) <= kClosedGap;
    if ((cyclic || sheet_start.Distance(sheet_end) <= kClosedGap) != closed_target) {
        throw user_error("Match Surface can't match a closed edge to an open one.");
    }
    if (closed_target && !cyclic) {
        // A closed edge of a surface that is closed but not periodic along it (a clamped loft of closed sections): made periodic
        // when it closes smoothly, else refused.
        if (!make_along_periodic(base)) {
            throw user_error("Match Surface can't match a closed edge of a surface that doesn't close smoothly.");
        }
        cyclic = true;
    }
    bool forward = sheet_start.Distance(target_lo) <= sheet_start.Distance(target_hi);
    double target_origin = 0.0; // cyclic: the arc length of the target's start (nearest the sheet's seam) from its own first point
    if (cyclic) {
        // The target parameter nearest the sheet's seam point.
        const double t_seam = nearest_parameter(target_curve, target_table, sheet_start);
        target_origin = target_table.length_at(t_seam);
        gp_Pnt seam_point;
        gp_Vec target_tangent, sheet_tangent;
        target_curve.D1(t_seam, seam_point, target_tangent);
        gp_Pnt sheet_seam;
        gp_Vec c1, c2;
        base.evaluate(a0, sheet_seam, c1, c2, sheet_tangent);
        if (target_tangent.Magnitude() < 1e-12 || sheet_tangent.Magnitude() < 1e-12) {
            throw user_error("The edges have no direction at the sheet's seam.");
        }
        forward = target_tangent.Dot(sheet_tangent) > 0.0;
    } else {
        const double end_gap = std::max(sheet_start.Distance(forward ? target_lo : target_hi),
                                        sheet_end.Distance(forward ? target_hi : target_lo));
        if (end_gap > kEndGap) {
            throw user_error("The edges' ends are " + number(end_gap) + " mm apart; Match needs them to meet.");
        }
    }
    // The target parameter paired with the sheet's `fraction` of its length from its start (cyclic: wrapping round the target).
    const auto paired = [&](double fraction) {
        if (!cyclic) {
            return target_table.parameter_at((forward ? fraction : 1.0 - fraction) * target_table.total());
        }
        const double total = target_table.total();
        double wanted = target_origin + (forward ? 1.0 : -1.0) * fraction * total;
        wanted -= std::floor(wanted / total) * total;
        return target_table.parameter_at(wanted);
    };

    // The target face whose continuation the sheet takes, and which way is "away from it" along the face's own normal.
    const double sheet_mid_parameter = 0.5 * (a0 + a1);
    const double t_mid = cyclic ? paired(sheet_table.length_at(sheet_mid_parameter) / sheet_table.total()) : 0.5 * (t_lo + t_hi);
    gp_Pnt mid_point;
    gp_Vec mid_tangent;
    target_curve.D1(t_mid, mid_point, mid_tangent);
    if (mid_tangent.Magnitude() < 1e-12) {
        throw user_error("The target edge has no direction at its middle.");
    }
    mid_tangent.Normalize();
    gp_Pnt sheet_mid;
    gp_Vec sheet_cross1, sheet_cross2, sheet_along1;
    base.evaluate(sheet_mid_parameter, sheet_mid, sheet_cross1, sheet_cross2, sheet_along1);
    if (sheet_cross1.Magnitude() < 1e-12) {
        throw user_error("Match Surface can't match an edge the surface doesn't leave.");
    }
    const gp_Vec sheet_inward = sheet_cross1.Normalized();
    int chosen = -1;
    double best = -2.0, sign = 1.0;
    for (std::size_t k = 0; k < target_faces.size(); ++k) {
        const face_side side_k(target_edge, target_faces[k]);
        const side_sample here = sample_side(side_k, t_mid, mid_tangent);
        if (!here.ok) {
            continue;
        }
        gp_Vec across = here.normal.Crossed(mid_tangent);
        if (across.Magnitude() < 1e-12) {
            continue;
        }
        across.Normalize();
        const inward found = inward_direction(target_faces[k], BRep_Tool::Surface(target_faces[k]), mid_point, here.normal, mid_tangent);
        if (!found.found) {
            continue;
        }
        const double orientation = found.direction.Dot(across) > 0 ? -1.0 : 1.0; // leaving = -inward
        const double score = (across * orientation).Dot(sheet_inward);
        if (score > best) {
            best = score, chosen = static_cast<int>(k), sign = orientation;
        }
    }
    if (chosen < 0) {
        throw user_error("The target face can't be read along its edge.");
    }
    const TopoDS_Face &target_face = target_faces[chosen];
    const face_side target_side(target_edge, target_face);

    // Rows 0..continuity are fitted; each level doubles the spans along the edge.
    net level = base;
    level.surface = Handle(Geom_BSplineSurface)::DownCast(base.surface->Copy());
    int reached = -1;
    for (int refinement = 0; refinement <= kRefinements; ++refinement) {
        poll(cancel);
        if (refinement > 0) {
            const std::vector<double> flat = level.along_flat();
            std::vector<double> mids;
            for (std::size_t i = 0; i + 1 < flat.size(); ++i) {
                const double mid = 0.5 * (flat[i] + flat[i + 1]);
                if (flat[i + 1] > flat[i] + 1e-12 && mid > a0 && mid < a1) {
                    mids.push_back(mid);
                }
            }
            if (mids.empty() ||
                static_cast<long>(level.along_poles() + mids.size()) * level.cross_poles() > kMaxPoles) {
                break;
            }
            TColStd_Array1OfReal knots(1, static_cast<int>(mids.size()));
            TColStd_Array1OfInteger mults(1, static_cast<int>(mids.size()));
            for (std::size_t i = 0; i < mids.size(); ++i) {
                knots(static_cast<int>(i) + 1) = mids[i];
                mults(static_cast<int>(i) + 1) = 1;
            }
            Handle(Geom_BSplineSurface) refined = Handle(Geom_BSplineSurface)::DownCast(level.surface->Copy());
            if (level.cross_u) {
                refined->InsertVKnots(knots, mults, 0.0, Standard_True);
            } else {
                refined->InsertUKnots(knots, mults, 0.0, Standard_True);
            }
            level.surface = refined;
            if (cyclic && !level.along_periodic()) {
                throw user_error("Match couldn't keep the surface closed.");
            }
        }

        const int na = level.along_poles();
        const int pa = level.along_degree();
        const int pc = level.cross_degree();
        const int count = cyclic ? 4 * na : 4 * na + 1; // a closed edge doesn't sample its seam twice
        const std::vector<double> along_knots = level.along_flat();
        const std::vector<double> cross_knots = level.cross_flat();
        const auto cross_basis = basis_derivatives(cross_knots, pc, pc, r0, continuity);

        // What the target and the sheet as it was say at each sample.
        std::vector<sample_data> samples(count);
        double mean_speed = 0.0;
        int speeds = 0;
        for (int i = 0; i < count; ++i) {
            sample_data &sample = samples[i];
            sample.s = a0 + (a1 - a0) * i / (cyclic ? count : count - 1);
            gp_Pnt old_point;
            gp_Vec cross1, cross2, along1;
            level.evaluate(sample.s, old_point, cross1, cross2, along1);
            sample.speed = cross1.Magnitude();
            sample.cross2 = cross2;
            if (sample.speed > 1e-12) {
                mean_speed += sample.speed;
                ++speeds;
            }
            const double fraction = sheet_table.length_at(sample.s) / sheet_table.total();
            const double t = paired(fraction);
            gp_Vec tangent;
            target_curve.D1(t, sample.point, tangent);
            if (tangent.Magnitude() < 1e-12) {
                throw user_error("The target edge has no direction along its length.");
            }
            tangent.Normalize();
            const side_sample read = sample_side(target_side, t, tangent);
            if (!read.ok) {
                throw user_error("The target face can't be read along its edge.");
            }
            gp_Vec across = read.normal.Crossed(tangent);
            if (across.Magnitude() < 1e-12) {
                throw user_error("The target face can't be read along its edge.");
            }
            sample.leaving = across.Normalized() * sign;
            sample.normal = read.normal;
            sample.curvature = read.curvature;
        }
        if (speeds == 0) {
            throw user_error("Match Surface can't match an edge the surface doesn't leave.");
        }
        mean_speed /= speeds;
        for (sample_data &sample : samples) {
            if (sample.speed <= 1e-12) {
                sample.speed = mean_speed;
            }
        }

        // The along basis at every sample, once.
        struct along_row {
            std::vector<int> index;   // the 0-based pole of each non-zero basis function (wrapped round a periodic edge)
            std::vector<double> values;
            double denominator = 1.0; // W(s, 0)
        };
        std::vector<along_row> rows(count);
        const periodic_knots wrap = cyclic ? periodic_flat(level.surface, !level.cross_u) : periodic_knots();
        const int first_multiplicity = cyclic ? level.along_first_multiplicity() : 0;
        for (int i = 0; i < count; ++i) {
            int span = 0;
            double t = samples[i].s;
            if (cyclic) {
                t = t >= a1 - 1e-12 ? a0 : t; // the end of the period is its start
                span = find_periodic_span(wrap, t);
            } else {
                span = find_span(along_knots, pa, na, t);
            }
            const auto ders = basis_derivatives(along_knots, pa, span, t, 0);
            rows[i].values = ders[0];
            double w = 0.0;
            gp_XYZ edge_point(0, 0, 0);
            for (int r = 0; r <= pa; ++r) {
                const int j = span - pa + r;
                rows[i].index.push_back(cyclic ? ((j - wrap.origin - first_multiplicity + 1 + pa) % na + na) % na : j);
                const double weighted = level.weight(1, rows[i].index[r] + 1) * ders[0][r];
                w += weighted;
                edge_point += level.pole(1, rows[i].index[r] + 1).XYZ() * weighted;
            }
            rows[i].denominator = w;
            if (cyclic && i % (count / 4 + 1) == 0) {
                // The wrapped basis must be OCCT's own: read the edge row back through it.
                const gp_Pnt expected = level.edge_point(samples[i].s);
                if (gp_Pnt(edge_point / w).Distance(expected) > 1e-6 * (1.0 + expected.XYZ().Modulus())) {
                    throw user_error("Match couldn't read the closed surface.");
                }
            }
        }

        net fit;
        fit.cross_u = level.cross_u;
        fit.surface = Handle(Geom_BSplineSurface)::DownCast(level.surface->Copy());
        for (int k = 0; k <= continuity; ++k) {
            // The k-th r-derivative at r = 0 of the net with row k set to zero.
            net zeroed;
            zeroed.cross_u = fit.cross_u;
            zeroed.surface = Handle(Geom_BSplineSurface)::DownCast(fit.surface->Copy());
            for (int j = 1; j <= na; ++j) {
                zeroed.set_pole(k + 1, j, gp_Pnt(0, 0, 0));
            }
            const bool pinned_ends = k == 0 && !cyclic;
            const int unknowns = na - (pinned_ends ? 2 : 0);
            const int offset = pinned_ends ? 1 : 0; // unknown u is pole index u + offset (0-based)
            // A closed edge's wrapped basis touches the last `pa` poles with everything: a banded interior and a border.
            const int border = cyclic ? std::min(pa, na) : 0;
            band_border_system system(std::max(unknowns, 0) - border, border, pa);
            std::vector<double> rhs(static_cast<size_t>(std::max(unknowns, 0)) * 3, 0.0);
            for (int i = 0; i < count; ++i) {
                const sample_data &sample = samples[i];
                gp_Pnt point;
                gp_Vec cross1, cross2, along1;
                zeroed.evaluate(sample.s, point, cross1, cross2, along1);
                gp_Vec have = k == 0 ? gp_Vec(gp_Pnt(0, 0, 0), point) : k == 1 ? cross1 : cross2;
                gp_Vec want;
                if (k == 0) {
                    want = gp_Vec(gp_Pnt(0, 0, 0), sample.point);
                } else if (k == 1) {
                    want = sample.leaving * sample.speed;
                } else {
                    const gp_Vec tangential = sample.cross2 - sample.normal * sample.cross2.Dot(sample.normal);
                    want = tangential + sample.normal * (sample.curvature * sample.speed * sample.speed);
                }
                gp_Vec residual = want - have;
                const along_row &row = rows[i];
                // The coefficient of pole (k, j).
                std::vector<double> coefficient(pa + 1, 0.0);
                for (int r = 0; r <= pa; ++r) {
                    const int j0 = row.index[r]; // 0-based pole index
                    coefficient[r] = level.weight(k + 1, j0 + 1) * cross_basis[k][k] * row.values[r] / row.denominator;
                }
                // Pinned ends of row 0 move to the right-hand side.
                for (int r = 0; r <= pa; ++r) {
                    const int j0 = row.index[r];
                    if (pinned_ends && (j0 == 0 || j0 == na - 1)) {
                        const gp_Pnt end = j0 == 0 ? samples.front().point : samples.back().point;
                        residual -= gp_Vec(gp_Pnt(0, 0, 0), end) * coefficient[r];
                    }
                }
                for (int r1 = 0; r1 <= pa; ++r1) {
                    const int u1 = row.index[r1] - offset;
                    if (u1 < 0 || u1 >= unknowns) {
                        continue;
                    }
                    for (int c = 0; c < 3; ++c) {
                        rhs[static_cast<size_t>(u1) * 3 + c] += (c == 0 ? residual.X() : c == 1 ? residual.Y() : residual.Z()) * coefficient[r1];
                    }
                    for (int r2 = 0; r2 <= pa; ++r2) {
                        const int u2 = row.index[r2] - offset;
                        if (u2 < 0 || u2 >= unknowns) {
                            continue;
                        }
                        system.add(u1, u2, coefficient[r1] * coefficient[r2]);
                    }
                }
            }
            if (pinned_ends) {
                fit.set_pole(1, 1, samples.front().point);
                fit.set_pole(1, na, samples.back().point);
            }
            if (unknowns > 0) {
                const double ridge = 1e-12 * system.largest_diagonal() + 1e-300;
                for (int u = 0; u < unknowns; ++u) {
                    system.add(u, u, ridge);
                }
                if (!system.factor()) {
                    throw user_error("Match couldn't fit the surface to the target edge.");
                }
                system.solve(rhs.data(), 3);
                for (int u = 0; u < unknowns; ++u) {
                    const size_t at = static_cast<size_t>(u) * 3;
                    fit.set_pole(k + 1, u + offset + 1, gp_Pnt(rhs[at], rhs[at + 1], rhs[at + 2]));
                }
            }
        }

        // The candidate in the surface's own orientation, on a fresh copy of the sheet, then measured.
        Handle(Geom_BSplineSurface) candidate = Handle(Geom_BSplineSurface)::DownCast(fit.surface->Copy());
        if (side.side == kUEnd) {
            candidate->UReverse();
        } else if (side.side == kVEnd) {
            candidate->VReverse();
        }
        poll(cancel);
        edit_copy built = make_edit_copy(shape, face_index);
        const TopoDS_Face built_face = built.face();
        replace_face_surface(built_face, candidate, built.converted ? built.original : TopoDS_Face());
        const TopTools_IndexedMapOfShape built_edges = map_of(built.work, TopAbs_EDGE);
        const TopoDS_Edge built_edge = TopoDS::Edge(built_edges(edge_index));
        poll(cancel);
        const occt_edge_continuity found = edge_continuity_against(built_edge, built_face, target_face, 32);
        reached = grade_of(found);
        if (reached >= continuity) {
            if (input_valid && !BRepCheck_Analyzer(built.work).IsValid()) {
                throw user_error("Matching gives an invalid surface.");
            }
            return new occt_shape{built.work};
        }
    }
    throw user_error(miss_sentence(continuity, reached));
}

} // namespace

extern "C" {

occt_shape *occt_match_face(const occt_shape *shape, int face_index, int edge_index, const occt_shape *target, int target_edge_index,
                            int continuity, const occt_cancel *cancel, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        return match(shape, face_index, edge_index, target, target_edge_index, continuity, cancel);
    });
}

} // extern "C"
