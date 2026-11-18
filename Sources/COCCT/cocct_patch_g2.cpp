// The G2 boundary patch (NURBS spec, NS-2 Task 5). Three sides reuse the fillet's degree-17 triangular patch
// (cocct_g2_triangle.hpp), four a biquintic Coons patch (cocct_patch_quad.hpp).
//
// Each side is read from the sheet face it lies on:
//   * the boundary curve C is the quintic Bezier with the edge's own end positions, tangents and second derivatives (exact, so
//     neighbouring sides agree at their corner), refused beyond 1e-7 mm of the edge ("Piece N is too complex for a G2 patch");
//   * the first cross-boundary derivative F lies in the face's tangent plane, pointing away from the face, and is the
//     neighbouring side's tangent at both ends: F = a p + b t with p the unit in-plane normal of the edge into the hole, t its unit
//     tangent, and (a, b) running from the leg at one corner to the leg at the other by a smoothstep (zero first and second
//     derivative at both ends). At a right angle that is the brief's lambda (n x t), lambda the leg's length;
//   * the second one G has the normal part II(F, F) = kappa_n(F) |F|^2 n (the face's normal curvature across the edge) and the
//     tangential part the neighbouring curve's second derivative at the corner, blended along the side the same way.
// F and G are quintic Beziers through the exact end jets of those functions (the derivatives at the ends by a fit of six
// samples within 0.05 of the end). A piece that is a curve has F and G made from its two legs alone and is held at G0.
// A neighbour's tangent out of this face's tangent plane, the leg pointing back onto the face, or two blocks at a corner that
// disagree: "The surfaces meet at corner N in a way a G2 patch can't follow."

#include "cocct_patch_g2.hpp"

#include "cocct_g2_blend_internal.hpp"
#include "cocct_g2_triangle.hpp"
#include "cocct_patch_quad.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepClass_FaceClassifier.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <Geom2d_BezierCurve.hxx>
#include <Geom_BezierCurve.hxx>
#include <Geom_BezierSurface.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopoDS_Vertex.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Vec2d.hxx>

#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <string>
#include <vector>

namespace cocct {

namespace {

using g2::Jet;
using g2::Scalar;
using g2::Quintic;
using g2::Vec;

constexpr double kFitTolerance = 1e-7;    // the quintic against the edge, mm
constexpr double kPlaneTolerance = 1e-6;  // a leg's sine against the tangent plane
constexpr double kStep = 0.01;            // the spacing of the samples that give a function's end derivatives
constexpr double kEdgeSlack = 5e-5;       // the patch against its own boundary curves, mm

std::string corner_message(int corner) {
    return "The surfaces meet at corner " + std::to_string(corner) + " in a way a G2 patch can't follow.";
}

constexpr const char *kNotMade = "The patch couldn't be made from these pieces.";

Vec from_pnt(const gp_Pnt &p) { return {p.X(), p.Y(), p.Z()}; }
Vec from_vec(const gp_Vec &v) { return {v.X(), v.Y(), v.Z()}; }
gp_Vec to_vec(const Vec &v) { return gp_Vec(v[0], v[1], v[2]); }

Vec unit(const Vec &v) {
    const double length = g2::norm(v);
    return length > 0 ? g2::scale(v, 1 / length) : v;
}

Vec cross(const Vec &a, const Vec &b) {
    return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]};
}

/// Smootherstep: 0 and 1 at the ends with zero first and second derivatives there.
double blend(double t) { return t * t * t * (10 + t * (-15 + 6 * t)); }

/// One bounding piece being read.
struct Side {
    TopoDS_Edge edge;
    TopoDS_Face support;
    int number = 0;
    double first = 0, last = 0;
    bool reversed = false; // traversed from the curve's last parameter to its first
    bool linear = false;   // the cross direction runs from one leg to the other linearly, else by a smootherstep
    Quintic c{};
    // A supported side's frame:
    double hole = 1; // the sign that makes n x t point into the hole
    // The leg's components at both ends in (p, t): a, b; and the neighbours' tangential second derivatives: wp, wt.
    double a[2] = {0, 0}, b[2] = {0, 0}, wp[2] = {0, 0}, wt[2] = {0, 0};
    Vec leg[2]{}, accel[2]{};
    Quintic f{}, g{};
    Jet fj[2]{}, gj[2]{}; // F's and G's jets (orders 0 to 2 in tau) at both ends
    // Corrections to the tangential part of G at an end that keep its first and second derivative in step with the neighbour's
    // F (four-sided patches): the component along p and along t, for the first and for the second derivative.
    double dw1p[2] = {0, 0}, dw1t[2] = {0, 0}, dw2p[2] = {0, 0}, dw2t[2] = {0, 0};

    double param(double tau) const { return reversed ? last - (last - first) * tau : first + (last - first) * tau; }
    double speed() const { return reversed ? -(last - first) : (last - first); }
    bool supported() const { return !support.IsNull(); }
};

struct Frame {
    Vec t{}, pin{}, n{};
    g2_blend::SurfacePoint sp;
};

Frame frame_at(const Side &side, double tau) {
    const double u = side.param(tau);
    Frame frame;
    frame.sp = g2_blend::surface_point(side.support, side.edge, u);
    BRepAdaptor_Curve curve(side.edge);
    gp_Pnt p;
    gp_Vec d1;
    curve.D1(u, p, d1);
    if (side.reversed) {
        d1.Reverse();
    }
    if (d1.Magnitude() < 1e-12) {
        throw user_error(kNotMade);
    }
    d1.Normalize();
    frame.t = from_vec(d1);
    frame.n = from_vec(frame.sp.n);
    frame.pin = g2::scale(unit(cross(frame.n, frame.t)), side.hole);
    return frame;
}

/// The sign that makes n x t point away from the sheet, read at the middle of the edge.
double hole_sign(const Side &side) {
    double first = 0, last = 0;
    const Handle(Geom2d_Curve) pcurve = BRep_Tool::CurveOnSurface(side.edge, side.support, first, last);
    if (pcurve.IsNull()) {
        throw user_error(kNotMade);
    }
    const double u = 0.5 * (first + last);
    gp_Pnt2d uv;
    gp_Vec2d d;
    pcurve->D1(u, uv, d);
    if (d.Magnitude() < 1e-14) {
        throw user_error(kNotMade);
    }
    gp_Vec2d across(-d.Y(), d.X());
    across.Normalize();
    const double eps = 1e-3 * (last - first) * d.Magnitude();
    auto inside = [&](double sign) {
        const gp_Pnt2d probe(uv.X() + sign * eps * across.X(), uv.Y() + sign * eps * across.Y());
        BRepClass_FaceClassifier classifier(side.support, probe, 1e-9);
        return classifier.State() == TopAbs_IN;
    };
    double into = 0;
    if (inside(1)) {
        into = 1;
    } else if (inside(-1)) {
        into = -1;
    } else {
        throw user_error(kNotMade);
    }
    BRepAdaptor_Surface surface(side.support, Standard_False);
    gp_Pnt p;
    gp_Vec su, sv;
    surface.D1(uv.X(), uv.Y(), p, su, sv);
    const Vec interior = from_vec(su * (into * across.X()) + sv * (into * across.Y()));
    Side probe_side = side;
    probe_side.hole = 1;
    const Frame frame = frame_at(probe_side, 0.5);
    // frame.pin is n x t (hole = 1); it must point away from the interior.
    return g2::dot(frame.pin, interior) > 0 ? -1.0 : 1.0;
}

/// The boundary curve: the quintic with the edge's exact end positions, tangents and second derivatives (in the traversal's own
/// parameter on [0, 1]).
void fit_curve(Side &side) {
    BRepAdaptor_Curve curve(side.edge);
    Jet jets[2];
    for (int end = 0; end < 2; ++end) {
        gp_Pnt p;
        gp_Vec d1, d2;
        curve.D2(side.param(end), p, d1, d2);
        const double speed = side.speed();
        jets[end] = {from_pnt(p), g2::scale(from_vec(d1), speed), g2::scale(from_vec(d2), speed * speed)};
    }
    side.c = g2::quintic_from_jets(jets[0], jets[1]);
    double worst = 0;
    for (int k = 0; k <= 40; ++k) {
        const double tau = k / 40.0;
        worst = std::max(worst, g2::norm(g2::sub(from_pnt(curve.Value(side.param(tau))), g2::bezier_value(side.c, tau))));
    }
    if (!(worst <= kFitTolerance)) {
        throw user_error("Piece " + std::to_string(side.number) + " is too complex for a G2 patch; split it.");
    }
}

struct Pair {
    Vec f{}, g{};
};

/// The scalar quintic with jets (0, 0, 0) at one end of [0, 1] except order `order` (1 or 2), which is 1 there, and (0, 0, 0)
/// at the other end.
const Scalar &side_basis(int end, int order) {
    static const Scalar table[2][2] = {{g2::hermite_basis(0, 1), g2::hermite_basis(0, 2)},
                                       {g2::hermite_basis(1, 1), g2::hermite_basis(1, 2)}};
    return table[end][order - 1];
}

/// F and G of a supported side at `tau` (both from one frame).
Pair evaluate_pair(const Side &side, double tau) {
    const Frame frame = frame_at(side, tau);
    const double s = side.linear ? tau : blend(tau);
    const double a = side.a[0] + (side.a[1] - side.a[0]) * s, b = side.b[0] + (side.b[1] - side.b[0]) * s;
    const Vec f = g2::add(g2::scale(frame.pin, a), g2::scale(frame.t, b));
    const double kappa = frame.sp.normal_curvature(to_vec(f));
    const double ii = kappa * g2::dot(f, f);
    double wp = side.wp[0] + (side.wp[1] - side.wp[0]) * s, wt = side.wt[0] + (side.wt[1] - side.wt[0]) * s;
    for (int e = 0; e < 2; ++e) {
        const double h1 = g2::value_at(side_basis(e, 1), tau), h2 = g2::value_at(side_basis(e, 2), tau);
        wp += side.dw1p[e] * h1 + side.dw2p[e] * h2;
        wt += side.dw1t[e] * h1 + side.dw2t[e] * h2;
    }
    Vec g = g2::scale(frame.n, ii);
    g = g2::add(g, g2::add(g2::scale(frame.pin, wp), g2::scale(frame.t, wt)));
    return {f, g};
}

/// The jets (orders 0 to 2, with respect to tau) at an end of the two functions, from six samples within 0.05 of it.
void end_jets(const Side &side, int end, Jet &f_jet, Jet &g_jet) {
    constexpr int n = 6;
    std::array<Pair, n> samples;
    for (int i = 0; i < n; ++i) {
        const double tau = end == 0 ? i * kStep : 1 - i * kStep;
        samples[static_cast<std::size_t>(i)] = evaluate_pair(side, tau);
    }
    std::vector<double> matrix(n * n);
    for (int i = 0; i < n; ++i) {
        double power = 1;
        for (int j = 0; j < n; ++j) {
            matrix[static_cast<std::size_t>(i * n + j)] = power;
            power *= i;
        }
    }
    const double direction = end == 0 ? 1.0 : -1.0;
    for (int which = 0; which < 2; ++which) {
        Vec jets[3]{};
        for (int c = 0; c < 3; ++c) {
            std::vector<double> m = matrix, rhs(n);
            for (int i = 0; i < n; ++i) {
                rhs[static_cast<std::size_t>(i)] = (which == 0 ? samples[static_cast<std::size_t>(i)].f : samples[static_cast<std::size_t>(i)].g)[c];
            }
            if (!g2::solve_dense(m, rhs, n)) {
                throw user_error(kNotMade);
            }
            jets[0][c] = rhs[0];
            jets[1][c] = direction * rhs[1] / kStep;
            jets[2][c] = 2 * rhs[2] / (kStep * kStep);
        }
        (which == 0 ? f_jet : g_jet) = {jets[0], jets[1], jets[2]};
    }
}

/// The quintics F and G against the functions they stand for, over the whole side: F must stay within 5e-5 of the tangent plane
/// (relative) and G's normal part within 1% of the face's normal curvature across, else the side can't carry a G2 patch.
void check_side(const Side &side) {
    for (int k = 1; k < 20; ++k) {
        const double tau = k / 20.0;
        const Frame frame = frame_at(side, tau);
        const Vec f = g2::bezier_value(side.f, tau), g = g2::bezier_value(side.g, tau);
        const double length = g2::norm(f);
        const double wanted = frame.sp.normal_curvature(to_vec(f)) * g2::dot(f, f);
        if (std::abs(g2::dot(f, frame.n)) > 5e-5 * length || std::abs(g2::dot(g, frame.n) - wanted) > 1e-2 * std::abs(wanted) + 1e-5 * length * length) {
            throw user_error("The patch can't be made curvature continuous along piece " + std::to_string(side.number) + ".");
        }
    }
}

/// F and G of a curve: the blend of its two legs and of the neighbours' second derivatives, with zero derivatives at both ends.
void fill_curve_side(Side &side) {
    const Jet f0 = {side.leg[0], {0, 0, 0}, {0, 0, 0}}, f1 = {side.leg[1], {0, 0, 0}, {0, 0, 0}};
    const Jet g0 = {side.accel[0], {0, 0, 0}, {0, 0, 0}}, g1 = {side.accel[1], {0, 0, 0}, {0, 0, 0}};
    side.f = g2::quintic_from_jets(f0, f1);
    side.g = g2::quintic_from_jets(g0, g1);
}

/// The exact patch diagonal scale: the diagonal of the box around every boundary pole.
double loop_diagonal(const std::vector<Side> &sides) {
    Vec low{1e300, 1e300, 1e300}, high{-1e300, -1e300, -1e300};
    for (const Side &side : sides) {
        for (const Vec &p : side.c) {
            for (int c = 0; c < 3; ++c) {
                low[c] = std::min(low[c], p[c]);
                high[c] = std::max(high[c], p[c]);
            }
        }
    }
    return g2::norm(g2::sub(high, low));
}

struct Regularity {
    double min_sine = 1e300, max_curvature = 0;
};

/// Samples a surface at `uv` points for a defined normal and the principal curvatures.
void sample_regularity(const Handle(Geom_BezierSurface) &surface, double u, double v, bool interior, Regularity &out) {
    gp_Pnt p;
    gp_Vec su, sv, suu, svv, suv;
    surface->D2(std::min(1.0, std::max(0.0, u)), std::min(1.0, std::max(0.0, v)), p, su, sv, suu, svv, suv);
    const gp_Vec nv = su.Crossed(sv);
    const double area = nv.Magnitude();
    const double e = su.Dot(su), f = su.Dot(sv), g = sv.Dot(sv);
    out.min_sine = std::min(out.min_sine, area / std::sqrt(e * g));
    if (area < 1e-14) {
        throw user_error(kNotMade);
    }
    if (!interior) {
        return;
    }
    const gp_Vec nn = nv / area;
    const double l = suu.Dot(nn), m = suv.Dot(nn), nq = svv.Dot(nn);
    const double det = e * g - f * f;
    const double kg = (l * nq - m * m) / det;
    const double hm = (e * nq - 2 * f * m + g * l) / (2 * det);
    const double disc = std::sqrt(std::max(0.0, hm * hm - kg));
    out.max_curvature = std::max(out.max_curvature, std::max(std::abs(hm + disc), std::abs(hm - disc)));
}

/// The face over `surface` whose boundary is the sides' curves, side k running from `domain[k]` to `domain[k + 1]`.
TopoDS_Face make_face(const Handle(Geom_BezierSurface) &surface, const std::vector<Side> &sides, const std::vector<gp_Pnt2d> &domain) {
    const std::size_t count = sides.size();
    BRep_Builder builder;
    // How far the surface stands off each side's own curve, which sets the edges' tolerance.
    double stand_off = 0;
    for (std::size_t k = 0; k < count; ++k) {
        for (int i = 0; i <= 20; ++i) {
            const double t = i / 20.0;
            const gp_Pnt2d &from = domain[k], &to = domain[(k + 1) % count];
            const gp_Pnt on = surface->Value(from.X() + t * (to.X() - from.X()), from.Y() + t * (to.Y() - from.Y()));
            const Vec want = g2::bezier_value(sides[k].c, t);
            stand_off = std::max(stand_off, g2::norm(g2::sub(from_pnt(on), want)));
        }
    }
    if (stand_off > kEdgeSlack) {
        throw user_error(kNotMade);
    }
    const double tolerance = std::max(1e-6, 1.5 * stand_off);
    std::vector<TopoDS_Vertex> vertices(count);
    for (std::size_t k = 0; k < count; ++k) {
        const Vec a = g2::bezier_value(sides[(k + count - 1) % count].c, 1.0), b = g2::bezier_value(sides[k].c, 0.0);
        const Vec mid = g2::scale(g2::add(a, b), 0.5);
        builder.MakeVertex(vertices[k], gp_Pnt(mid[0], mid[1], mid[2]), tolerance + 0.5 * g2::norm(g2::sub(a, b)));
    }
    TopoDS_Wire wire;
    builder.MakeWire(wire);
    for (std::size_t k = 0; k < count; ++k) {
        TColgp_Array1OfPnt poles(1, 6);
        for (int i = 0; i < 6; ++i) {
            poles.SetValue(i + 1, gp_Pnt(sides[k].c[static_cast<std::size_t>(i)][0], sides[k].c[static_cast<std::size_t>(i)][1],
                                         sides[k].c[static_cast<std::size_t>(i)][2]));
        }
        TopoDS_Edge edge;
        builder.MakeEdge(edge, Handle(Geom_BezierCurve)(new Geom_BezierCurve(poles)), tolerance);
        builder.Add(edge, vertices[k].Oriented(TopAbs_FORWARD));
        builder.Add(edge, vertices[(k + 1) % count].Oriented(TopAbs_REVERSED));
        builder.Range(edge, 0, 1);
        builder.UpdateEdge(edge, g2_blend::line2d(domain[k], domain[(k + 1) % count], 0, 1), surface, TopLoc_Location(), tolerance);
        builder.Add(wire, edge.Oriented(TopAbs_FORWARD));
    }
    TopoDS_Face face;
    builder.MakeFace(face, surface, tolerance);
    builder.Add(face, wire);
    return face;
}

} // namespace

TopoDS_Face build_g2_patch(const std::vector<g2_side> &input, const occt_cancel *cancel) {
    const int count = static_cast<int>(input.size());
    if (count != 3 && count != 4) {
        throw user_error("A G2 patch needs 3 or 4 sides; this loop has " + std::to_string(count) + ".");
    }
    std::vector<Side> sides(static_cast<std::size_t>(count));
    for (int k = 0; k < count; ++k) {
        Side &side = sides[static_cast<std::size_t>(k)];
        side.edge = input[static_cast<std::size_t>(k)].edge;
        side.support = input[static_cast<std::size_t>(k)].support;
        side.number = input[static_cast<std::size_t>(k)].input_number;
        side.linear = count == 3;
        BRepAdaptor_Curve curve(side.edge);
        side.first = curve.FirstParameter();
        side.last = curve.LastParameter();
    }
    // Which way each piece runs along the loop: the first towards the end it shares with the second, the others on from where
    // the one before ended.
    auto ends = [](const Side &side, gp_Pnt &a, gp_Pnt &b) {
        BRepAdaptor_Curve curve(side.edge);
        a = curve.Value(side.first);
        b = curve.Value(side.last);
    };
    {
        gp_Pnt a0, b0, a1, b1;
        ends(sides[0], a0, b0);
        ends(sides[1], a1, b1);
        const double near_a = std::min(a0.Distance(a1), a0.Distance(b1)), near_b = std::min(b0.Distance(a1), b0.Distance(b1));
        sides[0].reversed = near_a < near_b;
    }
    for (int k = 1; k < count; ++k) {
        gp_Pnt previous_a, previous_b, a, b;
        ends(sides[static_cast<std::size_t>(k - 1)], previous_a, previous_b);
        const gp_Pnt start = sides[static_cast<std::size_t>(k - 1)].reversed ? previous_a : previous_b;
        ends(sides[static_cast<std::size_t>(k)], a, b);
        sides[static_cast<std::size_t>(k)].reversed = start.Distance(b) < start.Distance(a);
    }
    for (Side &side : sides) {
        fit_curve(side);
    }
    poll(cancel);
    // The legs at every corner, and the frames of the supported sides.
    const auto at = [&](int k) -> Side & { return sides[static_cast<std::size_t>((k % count + count) % count)]; };
    for (int k = 0; k < count; ++k) {
        Side &side = at(k);
        side.leg[0] = g2::scale(g2::bezier_derivative(at(k - 1).c, 1.0), -1.0);
        side.leg[1] = g2::bezier_derivative(at(k + 1).c, 0.0);
        side.accel[0] = g2::bezier_second_derivative(at(k - 1).c, 1.0);
        side.accel[1] = g2::bezier_second_derivative(at(k + 1).c, 0.0);
    }
    // First every corner's geometry, so the lowest-numbered bad corner is the one named: the corner at the end of loop piece n is
    // corner n. A leg out of a face's tangent plane, or one that leaves back over the sheet, is a corner no patch can follow.
    int bad_corner = 0;
    for (int k = 0; k < count; ++k) {
        Side &side = at(k);
        if (!side.supported()) {
            continue;
        }
        try {
            side.hole = hole_sign(side);
            for (int end = 0; end < 2; ++end) {
                const Frame frame = frame_at(side, end);
                const Vec &leg = side.leg[end];
                const int corner = end == 0 ? (k == 0 ? count : k) : k + 1;
                const double length = g2::norm(leg);
                const bool in_plane = length > 1e-12 && std::abs(g2::dot(leg, frame.n)) <= kPlaneTolerance * length;
                side.a[end] = g2::dot(leg, frame.pin);
                side.b[end] = g2::dot(leg, frame.t);
                if (!in_plane || !(side.a[end] > 1e-9 * length)) {
                    bad_corner = bad_corner == 0 ? corner : std::min(bad_corner, corner);
                }
                side.wp[end] = g2::dot(side.accel[end], frame.pin);
                side.wt[end] = g2::dot(side.accel[end], frame.t);
            }
        } catch (const user_error &error) {
            if (std::string(error.what()) == kCancelled) {
                throw;
            }
            throw user_error("The patch can't be made curvature continuous along piece " + std::to_string(side.number) + ".");
        }
    }
    if (bad_corner > 0) {
        throw user_error(corner_message(bad_corner));
    }
    // A supported side's own readings can fail inside the shared surface reader, whose words are the fillet's.
    auto guarded = [](const Side &side, const std::function<void()> &body) {
        try {
            body();
        } catch (const user_error &error) {
            if (std::string(error.what()) == kCancelled) {
                throw;
            }
            throw user_error("The patch can't be made curvature continuous along piece " + std::to_string(side.number) + ".");
        }
    };
    auto read_jets = [&](Side &side) {
        guarded(side, [&] {
            end_jets(side, 0, side.fj[0], side.gj[0]);
            end_jets(side, 1, side.fj[1], side.gj[1]);
        });
    };
    for (int k = 0; k < count; ++k) {
        Side &side = at(k);
        if (side.supported()) {
            read_jets(side);
        } else {
            fill_curve_side(side);
        }
    }
    poll(cancel);
    if (count == 4) {
        // At each corner the horizontal side's G' must be the vertical side's F'' (S_uvv), the vertical side's G' the horizontal
        // side's F'' (S_uuv) and their G'' equal (S_uuvv): the tangential parts of those are free, so each side's G is
        // corrected by a Hermite term at that end (the normal parts are the faces' own and are left to the corner check).
        struct Place {
            int horizontal, horizontal_end, vertical, vertical_end;
        };
        const Place places[4] = {{0, 0, 3, 1}, {0, 1, 1, 0}, {2, 0, 1, 1}, {2, 1, 3, 0}};
        auto correct = [&](Side &side, int end, const Vec &wanted, int order) {
            const Frame frame = frame_at(side, end);
            const Vec change = g2::sub(wanted, side.gj[end][static_cast<std::size_t>(order)]);
            (order == 1 ? side.dw1p : side.dw2p)[end] += g2::dot(change, frame.pin);
            (order == 1 ? side.dw1t : side.dw2t)[end] += g2::dot(change, frame.t);
        };
        for (int pass = 0; pass < 2; ++pass) {
            for (const Place &place : places) {
                Side &h = at(place.horizontal), &v = at(place.vertical);
                if (!h.supported() || !v.supported()) {
                    continue;
                }
                const double along_h = place.horizontal == 2 ? -1.0 : 1.0, along_v = place.vertical == 3 ? -1.0 : 1.0;
                const double cross_h = place.horizontal == 2 ? -1.0 : 1.0, cross_v = place.vertical == 3 ? 1.0 : -1.0;
                guarded(h, [&] {
                    if (pass == 0) {
                        correct(h, place.horizontal_end, g2::scale(v.fj[place.vertical_end][2], along_h * cross_v), 1);
                        correct(v, place.vertical_end, g2::scale(h.fj[place.horizontal_end][2], along_v * cross_h), 1);
                    } else {
                        correct(v, place.vertical_end, h.gj[place.horizontal_end][2], 2);
                    }
                });
            }
            for (int k = 0; k < count; ++k) {
                if (at(k).supported()) {
                    read_jets(at(k));
                }
            }
        }
    }
    for (int k = 0; k < count; ++k) {
        Side &side = at(k);
        if (!side.supported()) {
            continue;
        }
        guarded(side, [&] {
            side.f = g2::quintic_from_jets(side.fj[0], side.fj[1]);
            side.g = g2::quintic_from_jets(side.gj[0], side.gj[1]);
            check_side(side);
        });
        poll(cancel);
    }
    const double diagonal = loop_diagonal(sides);
    Regularity regularity;
    Handle(Geom_BezierSurface) surface;
    std::vector<gp_Pnt2d> domain;
    if (count == 4) {
        g2::QuadSide quad[4];
        for (int k = 0; k < 4; ++k) {
            quad[k].c = at(k).c;
            quad[k].f = at(k).f;
            quad[k].g = at(k).g;
            quad[k].supported = at(k).supported();
        }
        g2::QuadPatch patch;
        g2::build_quad(quad, patch);
        for (int k = 0; k < 4; ++k) {
            if (!(patch.gap[k] <= g2::kCornerAgreement)) {
                throw user_error(corner_message(k + 1));
            }
        }
        TColgp_Array2OfPnt poles(1, 6, 1, 6);
        for (int i = 0; i < 6; ++i) {
            for (int j = 0; j < 6; ++j) {
                const Vec &v = patch.net[static_cast<std::size_t>(i)][static_cast<std::size_t>(j)];
                poles.SetValue(i + 1, j + 1, gp_Pnt(v[0], v[1], v[2]));
            }
        }
        surface = new Geom_BezierSurface(poles);
        domain = {gp_Pnt2d(0, 0), gp_Pnt2d(1, 0), gp_Pnt2d(1, 1), gp_Pnt2d(0, 1)};
        const int grid = 40;
        for (int a = 0; a <= grid; ++a) {
            for (int b = 0; b <= grid; ++b) {
                sample_regularity(surface, double(a) / grid, double(b) / grid, a > 0 && b > 0 && a < grid && b < grid, regularity);
            }
        }
    } else {
        g2::TriangleSide tri[3];
        for (int k = 0; k < 3; ++k) {
            tri[k].poles = at(k).c;
            tri[k].cross1 = at(k).f;
            tri[k].cross2 = at(k).g;
        }
        double direction_cosine = 0;
        if (!g2::across_scales(tri, direction_cosine) || direction_cosine < 0.999999) {
            throw user_error(corner_message(1));
        }
        g2::TriangleNet net;
        g2::TriangleStats stats;
        if (!g2::build_triangle(tri, net, stats)) {
            throw user_error(kNotMade);
        }
        poll(cancel);
        if (!(stats.min_lambda > 0) || !(stats.block_mismatch <= 1e-6)) {
            throw user_error(corner_message(stats.worst_corner >= 0 ? stats.worst_corner + 1 : 1));
        }
        const int n = g2::kTriangleDegree;
        const std::vector<Vec> tensor = g2::to_tensor(net);
        TColgp_Array2OfPnt poles(1, n + 1, 1, n + 1);
        for (int a = 0; a <= n; ++a) {
            for (int b = 0; b <= n; ++b) {
                const Vec &v = tensor[static_cast<std::size_t>(a) * (n + 1) + static_cast<std::size_t>(b)];
                poles.SetValue(a + 1, b + 1, gp_Pnt(v[0], v[1], v[2]));
            }
        }
        surface = new Geom_BezierSurface(poles);
        domain = {gp_Pnt2d(0, 0), gp_Pnt2d(1, 0), gp_Pnt2d(0, 1)};
        const int grid = 80;
        for (int a = 0; a <= grid; ++a) {
            for (int b = 0; a + b <= grid; ++b) {
                sample_regularity(surface, double(a) / grid, double(b) / grid, a > 0 && b > 0 && a + b < grid, regularity);
            }
        }
        for (double d : {1e-1, 3e-2, 1e-2, 1e-3, 1e-4}) {
            sample_regularity(surface, d, d, true, regularity);
            sample_regularity(surface, 1 - 2 * d, d, true, regularity);
            sample_regularity(surface, d, 1 - 2 * d, true, regularity);
        }
    }
    if (!(regularity.min_sine > 0.05) || !(regularity.max_curvature <= 10.0 / diagonal)) {
        throw user_error(kNotMade);
    }
    poll(cancel);
    TopoDS_Face face = make_face(surface, sides, domain);
    // The patch's outward side is its first supported neighbour's.
    for (std::size_t k = 0; k < sides.size(); ++k) {
        if (!sides[k].supported()) {
            continue;
        }
        const Frame frame = frame_at(sides[k], 0.5);
        const gp_Pnt2d &from = domain[k], &to = domain[(k + 1) % sides.size()];
        gp_Pnt p;
        gp_Vec su, sv;
        surface->D1(0.5 * (from.X() + to.X()), 0.5 * (from.Y() + to.Y()), p, su, sv);
        // Edge-hugging normal: the surface's, nudged a hair inwards would be the same side; the sign alone matters.
        if (su.Crossed(sv).Dot(to_vec(frame.n)) < 0) {
            face.Reverse();
        }
        break;
    }
    return face;
}

} // namespace cocct
