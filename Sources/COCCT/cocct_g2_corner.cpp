// The corners of the curvature-continuous fillet: a corner where three strips end becomes one three-sided G2 patch
// (cocct_g2_triangle.hpp), and any other is refilled G1 (cocct_g2_blend_internal.hpp).

#include "cocct_g2_triangle.hpp"
#include "cocct_g2_blend_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepFill_Filling.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <GeomAbs_Shape.hxx>
#include <Geom2d_BezierCurve.hxx>
#include <Geom_BezierCurve.hxx>
#include <Geom_BezierSurface.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array1OfPnt2d.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopoDS_Wire.hxx>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <vector>

namespace cocct::g2_blend {

namespace {

/// Carries a strip's surface on past its ends in u, exactly and in place: the end span's own polynomial over a longer
/// interval (its poles re-blossomed over it), so `low` and `high` lie inside the surface's u range. Every point of the old
/// range keeps its parameters, so the pcurves already on this surface (springs, the other end, another corner's side)
/// stay right with no remapping, and the surface's handle is unchanged.
void extend_in_u(const Handle(Geom_BSplineSurface) &surface, double low, double high) {
    if (surface->IsURational() || surface->IsUPeriodic()) {
        throw user_error(kStripMessage);
    }
    const int p = surface->UDegree();
    // The pole of the polynomial with Bezier poles `points` over [0, 1] that goes with the blossom (a^(p-k), b^k).
    auto blossom = [p](std::vector<gp_XYZ> points, double a, double b, int k) {
        for (int r = 1; r <= p; ++r) {
            const double t = r <= p - k ? a : b;
            for (int i = 0; i + r <= p; ++i) {
                points[static_cast<std::size_t>(i)] = points[static_cast<std::size_t>(i)] * (1 - t) + points[static_cast<std::size_t>(i) + 1] * t;
            }
        }
        return points[0];
    };
    for (int side = 0; side < 2; ++side) {
        const int n = surface->NbUKnots();
        const double first = surface->UKnot(1), last = surface->UKnot(n);
        const double target = side == 0 ? low : high;
        if (side == 0 ? target >= first : target <= last) {
            continue;
        }
        // The end span as one Bezier span: its inner knot raised to multiplicity p (and lowered again below).
        const int inner = side == 0 ? 2 : n - 1;
        const int kept = surface->UMultiplicity(inner);
        const bool raised = n > 2 && kept < p;
        if (raised) {
            surface->IncreaseUMultiplicity(inner, p);
        }
        const double a0 = side == 0 ? first : surface->UKnot(inner), a1 = side == 0 ? surface->UKnot(inner) : last;
        const double ta = side == 0 ? (target - a0) / (a1 - a0) : 0.0, tb = side == 0 ? 1.0 : (target - a0) / (a1 - a0);
        const int start = side == 0 ? 1 : surface->NbUPoles() - p;
        for (int j = 1; j <= surface->NbVPoles(); ++j) {
            std::vector<gp_XYZ> points(static_cast<std::size_t>(p) + 1);
            for (int i = 0; i <= p; ++i) {
                points[static_cast<std::size_t>(i)] = surface->Pole(start + i, j).XYZ();
            }
            std::vector<gp_XYZ> moved(static_cast<std::size_t>(p) + 1);
            for (int k = 0; k <= p; ++k) {
                moved[static_cast<std::size_t>(k)] = blossom(points, ta, tb, k);
            }
            for (int k = 0; k <= p; ++k) {
                surface->SetPole(start + k, j, gp_Pnt(moved[static_cast<std::size_t>(k)]));
            }
        }
        surface->SetUKnot(side == 0 ? 1 : n, target);
        if (raised) {
            // The two spans still join as smoothly as before: the knot comes off again to within 1e-9 mm, and where it
            // would not, the raised knot is kept (the same surface either way).
            surface->RemoveUKnot(inner, kept, 1e-9);
        }
    }
}

} // namespace

void place_corner_patches(Run &r) {
    occt_g2_report *const report = r.report;
    const double radius = r.radius;
    const bool use_patches = r.use_patches;
    const std::vector<TopoDS_Face> &strip_faces = r.strip_faces;
    const std::vector<TopoDS_Face> &corner_faces = r.corner_faces;
    BRep_Builder &builder = r.builder;
    BRepTools_ReShape &reshape = r.reshape;
    std::vector<StripEdges> &strips = r.strips;
    std::vector<bool> &corner_done = r.corner_done;
    std::vector<TopoDS_Face> &g2_new_faces = r.g2_new_faces;
    std::vector<std::vector<TopoDS_Face>> &corner_patches = r.corner_patches;
    std::vector<TopoDS_Edge> &g2_edges = r.g2_edges;
    std::vector<StripState> &states = r.states;
    // G2 corner patches. A corner whose three edges are all strip ends is replaced by one three-sided Bezier patch
    // (cocct_g2_triangle.hpp) that joins the three strips G2. A corner the patch is not accepted for (see below)
    // is left to the G1 refill after this loop.
    for (std::size_t ci = 0; ci < corner_faces.size() && use_patches; ++ci) {
        const TopoDS_Face old_corner = corner_faces[ci];
        try {
            struct EndCurve {
                std::size_t strip = 0;
                int end = 0;
                TopoDS_Edge old_edge;
                std::array<g2::Vec, 6> poles{};       // oriented V_j -> V_{j+1}
                std::array<g2::Vec, 6> cross1{}, cross2{}; // cross-boundary derivatives, oriented alike
                bool reversed = false;                 // against the strip's v
                TopoDS_Vertex from, to;
                g2::Scalar mitre = g2::Scalar(6, 0.0); // the side's offset in u from the strip's end, a quintic in t
                bool mitred = false;
            };
            std::vector<EndCurve> found;
            for (TopExp_Explorer it(old_corner, TopAbs_EDGE); it.More(); it.Next()) {
                const TopoDS_Edge e = TopoDS::Edge(it.Current());
                if (BRep_Tool::Degenerated(e)) {
                    continue;
                }
                bool known = false;
                for (const EndCurve &c : found) {
                    known = known || c.old_edge.IsSame(e);
                }
                if (known) {
                    continue;
                }
                BRepAdaptor_Curve ec(e);
                const gp_Pnt mid = ec.Value(0.5 * (ec.FirstParameter() + ec.LastParameter()));
                EndCurve curve;
                curve.old_edge = e;
                double best = 1e300;
                for (std::size_t s = 0; s < strips.size(); ++s) {
                    bool owns = false;
                    for (int c = 0; c < 2; ++c) {
                        owns = owns || (strips[s].ends[c].IsSame(e) && strips[s].end_face[c].IsNull() &&
                                        strips[s].end_strip[c].IsNull() && strips[s].end_chain[c].IsNull());
                    }
                    if (!owns || strips[s].closed) {
                        continue;
                    }
                    for (int end = 0; end < 2; ++end) {
                        if (states[s].slants[end].slanted) {
                            continue;
                        }
                        const auto &section = end == 0 ? states[s].built.sections.front() : states[s].built.sections.back();
                        g2::Vec at;
                        g2::Vec d1, d2;
                        g2::evaluate(section, 0.5, at, d1, d2);
                        const double d = gp_Pnt(at[0], at[1], at[2]).Distance(mid);
                        if (d < best) {
                            best = d;
                            curve.strip = s;
                            curve.end = end;
                        }
                    }
                }
                if (best > 0.5 * radius) {
                    throw user_error(kStripMessage);
                }
                found.push_back(curve);
            }
            if (found.size() != 3) {
                throw user_error(kStripMessage);
            }
            // Cross-boundary data from each strip's surface at its end.
            for (EndCurve &curve : found) {
                const BuiltStrip &built = states[curve.strip].built;
                const auto &section = curve.end == 0 ? built.sections.front() : built.sections.back();
                const double u_end = curve.end == 0 ? 0.0 : 1.0;
                const double sigma = curve.end == 0 ? -1.0 : 1.0;
                std::array<g2::Vec, 6> d1s{}, d2s{};
                for (int j = 0; j < 6; ++j) {
                    gp_Pnt p;
                    gp_Vec su, sv, suu, svv, suv;
                    built.surface->D2(u_end, j / 5.0, p, su, sv, suu, svv, suv);
                    d1s[j] = {sigma * su.X(), sigma * su.Y(), sigma * su.Z()};
                    d2s[j] = {suu.X(), suu.Y(), suu.Z()};
                }
                curve.poles = section;
                curve.cross1 = g2::bezier_through(d1s);
                curve.cross2 = g2::bezier_through(d2s);
            }
            // Order the three curves into a loop V_0 -> V_1 -> V_2 -> V_0, each oriented along it.
            auto close = [](const g2::Vec &a, const g2::Vec &b) { return g2::norm(g2::sub(a, b)) < 1e-6; };
            std::vector<EndCurve> loop;
            loop.push_back(found[0]);
            std::vector<bool> used(3, false);
            used[0] = true;
            while (loop.size() < 3) {
                bool advanced = false;
                for (std::size_t k = 1; k < 3 && !advanced; ++k) {
                    if (used[k]) {
                        continue;
                    }
                    EndCurve next = found[k];
                    const g2::Vec tail = loop.back().poles[5];
                    if (close(next.poles[0], tail)) {
                        next.reversed = false;
                    } else if (close(next.poles[5], tail)) {
                        next.reversed = true;
                        std::reverse(next.poles.begin(), next.poles.end());
                        std::reverse(next.cross1.begin(), next.cross1.end());
                        std::reverse(next.cross2.begin(), next.cross2.end());
                    } else {
                        continue;
                    }
                    loop.push_back(next);
                    used[k] = true;
                    advanced = true;
                }
                if (!advanced) {
                    throw user_error(kStripMessage);
                }
            }
            if (!close(loop[2].poles[5], loop[0].poles[0])) {
                throw user_error(kStripMessage);
            }
            // Mitred sides. G2 to strip j along side j fixes, at a corner V of the hole, every third derivative of
            // the patch with a factor along that side. The two sides at V (tangents a, b) both fix f3(a, a, b) and
            // f3(a, b, b), f3 the patch's cubic form there. A strip's profile leaves its spring cubically
            // (f3 = 6k v^3, v across the strip, k != 0 for the quintic G2 section), so the two values agree only when
            // v_A(b) = v_B(a) = 0 (a polynomial patch is C3 at V; nothing else solves it): each side leaves V along
            // the other strip's spring. A section square to the spine does that only where the springs meet at a
            // right angle; elsewhere the side is moved off the section to the curve u = u_end + g(t) on its strip,
            // g a quintic with g = g'' = 0 at both ends and g' the slope that turns the side onto the neighbouring
            // strip's spine there (which is also what `across_scales` asks of the cross derivatives).
            for (int j = 0; j < 3; ++j) {
                EndCurve &curve = loop[j];
                const Handle(Geom_BSplineSurface) &surface = states[curve.strip].built.surface;
                const double u_end = curve.end == 0 ? 0.0 : 1.0;
                const double v0 = curve.reversed ? 1.0 : 0.0, dv = curve.reversed ? -1.0 : 1.0;
                double slope[2] = {0, 0};
                for (int e = 0; e < 2; ++e) {
                    // The neighbour's spine at this end of the side, written as alpha S_u + beta S_v of this strip.
                    const gp_Vec target =
                        e == 0 ? to_vec(loop[(j + 2) % 3].cross1[5]) : to_vec(loop[(j + 1) % 3].cross1[0]).Reversed();
                    gp_Pnt p;
                    gp_Vec su, sv;
                    surface->D1(u_end, v0 + e * dv, p, su, sv);
                    const double a = su.Dot(su), b = su.Dot(sv), c = sv.Dot(sv), tu = su.Dot(target), tv = sv.Dot(target);
                    const double det = a * c - b * b;
                    const double alpha = (c * tu - b * tv) / det, beta = (a * tv - b * tu) / det;
                    if (!(beta * dv > 0)) {
                        throw user_error(kStripMessage); // the neighbouring spine does not lead into this strip
                    }
                    slope[e] = alpha * dv / beta;
                    if (std::abs(slope[e]) < 1e-12) {
                        slope[e] = 0; // already square to the neighbour there: rounding must not move the side off its end
                    }
                }
                if (slope[0] == 0 && slope[1] == 0) {
                    continue; // the section is already mitred: a right-angle corner
                }
                const double at0[3] = {0, slope[0], 0}, at1[3] = {0, slope[1], 0};
                curve.mitre = g2::hermite_poles(at0, at1);
                curve.mitred = true;
                // Where the side runs on into the hole (an acute corner), the strip is carried on with it, so that the
                // side's pcurve lies inside the surface's domain.
                double u_low = 0, u_high = 1;
                for (int k = 0; k <= 256; ++k) {
                    const double u = u_end + g2::value_at(curve.mitre, k / 256.0);
                    u_low = std::min(u_low, u);
                    u_high = std::max(u_high, u);
                }
                if (u_low < 0 || u_high > 1) {
                    const double margin = 0.1 * std::max(-u_low, u_high - 1);
                    extend_in_u(surface, u_low < 0 ? u_low - margin : 0.0, u_high > 1 ? u_high + margin : 1.0);
                }
                const double sigma = curve.end == 0 ? -1.0 : 1.0;
                auto sample = [&](double t, g2::Vec &point, g2::Vec &d1, g2::Vec &d2) {
                    gp_Pnt p;
                    gp_Vec su, sv, suu, svv, suv;
                    surface->D2(u_end + g2::value_at(curve.mitre, t), v0 + dv * t, p, su, sv, suu, svv, suv);
                    point = {p.X(), p.Y(), p.Z()};
                    d1 = {sigma * su.X(), sigma * su.Y(), sigma * su.Z()};
                    d2 = {suu.X(), suu.Y(), suu.Z()};
                };
                std::array<g2::Vec, 6> points{}, d1s{}, d2s{};
                for (int k = 0; k < 6; ++k) {
                    sample(k / 5.0, points[k], d1s[k], d2s[k]);
                }
                curve.poles = g2::bezier_through(points);
                curve.cross1 = g2::bezier_through(d1s);
                curve.cross2 = g2::bezier_through(d2s);
                // The side is the quintic through six points of the curve on the strip: exact where the strip is
                // an extrusion (u affine along a straight spine), and refused where it is not within 1e-7 mm.
                double fit = 0;
                for (int k = 0; k < 40; ++k) {
                    const double t = (k + 0.5) / 40;
                    g2::Vec point, d1, d2;
                    sample(t, point, d1, d2);
                    fit = std::max(fit, g2::norm(g2::sub(point, g2::bezier_value(curve.poles, t))));
                }
                if (!(fit <= 1e-7)) {
                    throw user_error(kStripMessage);
                }
            }
            for (EndCurve &curve : loop) {
                TopoDS_Vertex v1, v2;
                TopExp::Vertices(curve.old_edge, v1, v2, Standard_False);
                // The nearer vertex: a mitred side is read off the strip's surface, which may stand off OCCT's vertex
                // by about the vertex's tolerance (1.2e-6 mm on a drafted prism).
                const gp_Pnt first(curve.poles[0][0], curve.poles[0][1], curve.poles[0][2]);
                const bool first_is_start = first.Distance(BRep_Tool::Pnt(v1)) <= first.Distance(BRep_Tool::Pnt(v2));
                curve.from = first_is_start ? v1 : v2;
                curve.to = first_is_start ? v2 : v1;
            }
            ++report->corner_attempts;
            const auto clock0 = std::chrono::steady_clock::now();
            g2::TriangleSide tri_sides[3];
            for (int j = 0; j < 3; ++j) {
                tri_sides[j].poles = loop[j].poles;
                tri_sides[j].cross1 = loop[j].cross1;
                tri_sides[j].cross2 = loop[j].cross2;
            }
            // 1. The across scales: each strip's cross-boundary derivative must be the neighbouring end curve's tangent.
            double direction_cosine = 0;
            if (!g2::across_scales(tri_sides, direction_cosine) || direction_cosine < 0.999999) {
                throw user_error(kStripMessage);
            }
            g2::TriangleNet tri_net;
            g2::TriangleStats stats;
            if (!g2::build_triangle(tri_sides, tri_net, stats)) {
                throw user_error(kStripMessage);
            }
            // 2. lambda > 0 over every side (the reparametrisation is monotone) and the shared blocks agree.
            if (!(stats.min_lambda > 0) || !(stats.block_mismatch <= 1e-6)) {
                throw user_error(kStripMessage);
            }
            const int n = g2::kTriangleDegree;
            const std::vector<g2::Vec> tensor = g2::to_tensor(tri_net);
            TColgp_Array2OfPnt tri_poles(1, n + 1, 1, n + 1);
            for (int a = 0; a <= n; ++a) {
                for (int b = 0; b <= n; ++b) {
                    const g2::Vec &v = tensor[static_cast<std::size_t>(a) * (n + 1) + b];
                    tri_poles.SetValue(a + 1, b + 1, gp_Pnt(v[0], v[1], v[2]));
                }
            }
            const Handle(Geom_BezierSurface) tri_surface = new Geom_BezierSurface(tri_poles);
            // 3. Regularity: a defined normal and principal curvatures within 4 / r over the interior and near the corners.
            double min_sine = 1e300, max_interior = 0;
            {
                auto sample = [&](double x, double y, bool interior) {
                    gp_Pnt p;
                    gp_Vec su, sv, suu, svv, suv;
                    tri_surface->D2(std::min(1.0, std::max(0.0, x)), std::min(1.0, std::max(0.0, y)), p, su, sv, suu, svv, suv);
                    const gp_Vec nv = su.Crossed(sv);
                    const double area = nv.Magnitude();
                    const double e = su.Dot(su), f = su.Dot(sv), g = sv.Dot(sv);
                    min_sine = std::min(min_sine, area / std::sqrt(e * g));
                    if (area < 1e-14) {
                        throw user_error(kStripMessage);
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
                    max_interior = std::max(max_interior, std::max(std::abs(hm + disc), std::abs(hm - disc)));
                };
                const int grid = 80;
                for (int a = 0; a <= grid; ++a) {
                    for (int b = 0; a + b <= grid; ++b) {
                        sample(static_cast<double>(a) / grid, static_cast<double>(b) / grid, a > 0 && b > 0 && a + b < grid);
                    }
                }
                for (double d : {1e-1, 3e-2, 1e-2, 1e-3, 1e-4}) {
                    sample(d, d, true);
                    sample(1 - 2 * d, d, true);
                    sample(d, 1 - 2 * d, true);
                    sample(d, 0, false);
                    sample(0, d, false);
                    sample(1 - d, d, false);
                    sample(1 - d, 0, false);
                    sample(d, 1 - d, false);
                    sample(0, 1 - d, false);
                }
            }
            if (!(min_sine > 0.05) || !(max_interior <= 4.0 / radius)) {
                throw user_error(kStripMessage); // the patch is not regular enough
            }
            const gp_Pnt2d domain[3] = {gp_Pnt2d(0, 0), gp_Pnt2d(1, 0), gp_Pnt2d(0, 1)};
            // 4. The seams against the three strips, before anything is committed: the half of the promised tolerances
            //    that strips are held to.
            {
                auto on_surface = [](const Handle(Geom_Surface) &surface, const gp_Pnt2d &uv, bool reversed) {
                    SurfacePoint point;
                    surface->D2(uv.X(), uv.Y(), point.p, point.su, point.sv, point.suu, point.svv, point.suv);
                    point.n = point.su.Crossed(point.sv);
                    point.n.Normalize();
                    if (reversed) {
                        point.n.Reverse();
                    }
                    return point;
                };
                // The patch's outward side is the circular corner's, as for the face built below.
                bool tri_reversed = false;
                {
                    gp_Pnt middle;
                    gp_Vec da, db;
                    tri_surface->D1(1.0 / 3, 1.0 / 3, middle, da, db);
                    GeomAPI_ProjectPointOnSurf project(middle, BRep_Tool::Surface(old_corner));
                    double pu = 0, pv = 0;
                    project.LowerDistanceParameters(pu, pv);
                    gp_Pnt on_old;
                    gp_Vec oa, ob;
                    BRep_Tool::Surface(old_corner)->D1(pu, pv, on_old, oa, ob);
                    gp_Vec n_old = oa.Crossed(ob);
                    if (old_corner.Orientation() == TopAbs_REVERSED) {
                        n_old.Reverse();
                    }
                    tri_reversed = da.Crossed(db).Dot(n_old) < 0;
                }
                for (int j = 0; j < 3; ++j) {
                    const EndCurve &curve = loop[j];
                    const double u_end = curve.end == 0 ? 0.0 : 1.0;
                    const bool strip_reversed = strip_faces[curve.strip].Orientation() == TopAbs_REVERSED;
                    occt_g2_seam seam{};
                    for (int k = 0; k <= kMeasureSamples; ++k) {
                        const double t = static_cast<double>(k) / kMeasureSamples;
                        const double v = curve.reversed ? 1 - t : t;
                        const gp_Pnt2d uv_tri(domain[j].X() + t * (domain[(j + 1) % 3].X() - domain[j].X()),
                                              domain[j].Y() + t * (domain[(j + 1) % 3].Y() - domain[j].Y()));
                        const g2::Vec tangent_vector = g2::bezier_derivative(curve.poles, t);
                        gp_Vec tangent = to_vec(tangent_vector);
                        if (tangent.Magnitude() < 1e-12) {
                            throw user_error(kStripMessage);
                        }
                        const gp_Pnt2d uv_strip(u_end + g2::value_at(curve.mitre, t), v);
                        accumulate(seam, on_surface(states[curve.strip].built.surface, uv_strip, strip_reversed),
                                   on_surface(tri_surface, uv_tri, tri_reversed), tangent);
                    }
                    if (!within_tolerance(seam)) {
                        throw user_error(kStripMessage);
                    }
                }
            }
            TopoDS_Edge tri_edges[3];
            for (int j = 0; j < 3; ++j) {
                TColgp_Array1OfPnt end_poles(1, 6);
                for (int i = 0; i < 6; ++i) {
                    end_poles.SetValue(i + 1, gp_Pnt(loop[j].poles[i][0], loop[j].poles[i][1], loop[j].poles[i][2]));
                }
                builder.MakeEdge(tri_edges[j], Handle(Geom_BezierCurve)(new Geom_BezierCurve(end_poles)), kEdgeTolerance);
                builder.Add(tri_edges[j], loop[j].from.Oriented(TopAbs_FORWARD));
                builder.Add(tri_edges[j], loop[j].to.Oriented(TopAbs_REVERSED));
                builder.Range(tri_edges[j], 0, 1);
                const EndCurve &curve = loop[j];
                const double u_end = curve.end == 0 ? 0.0 : 1.0;
                const double v_start = curve.reversed ? 1.0 : 0.0, v_end = curve.reversed ? 0.0 : 1.0;
                if (curve.mitred) {
                    // u = u_end + g(t), v linear in t: a quintic Bezier pcurve (it may leave the surface's u range by
                    // a little where the strip is extended into the hole; the B-spline's end span carries it on).
                    TColgp_Array1OfPnt2d uv(1, 6);
                    for (int i = 0; i < 6; ++i) {
                        uv.SetValue(i + 1, gp_Pnt2d(u_end + curve.mitre[static_cast<std::size_t>(i)],
                                                    v_start + (v_end - v_start) * i / 5.0));
                    }
                    builder.UpdateEdge(tri_edges[j], Handle(Geom2d_BezierCurve)(new Geom2d_BezierCurve(uv)),
                                       states[curve.strip].built.surface, TopLoc_Location(), kEdgeTolerance);
                } else {
                    builder.UpdateEdge(tri_edges[j], line2d(gp_Pnt2d(u_end, v_start), gp_Pnt2d(u_end, v_end), 0, 1),
                                       states[curve.strip].built.surface, TopLoc_Location(), kEdgeTolerance);
                }
                builder.UpdateEdge(tri_edges[j], line2d(domain[j], domain[(j + 1) % 3], 0, 1), tri_surface, TopLoc_Location(),
                                   kEdgeTolerance);
            }
            TopoDS_Face tri_face;
            builder.MakeFace(tri_face, tri_surface, kEdgeTolerance);
            TopoDS_Wire tri_wire;
            builder.MakeWire(tri_wire);
            for (int j = 0; j < 3; ++j) {
                builder.Add(tri_wire, tri_edges[j].Oriented(TopAbs_FORWARD));
            }
            builder.Add(tri_face, tri_wire);
            {
                gp_Pnt middle;
                gp_Vec da, db;
                tri_surface->D1(1.0 / 3, 1.0 / 3, middle, da, db);
                GeomAPI_ProjectPointOnSurf project(middle, BRep_Tool::Surface(old_corner));
                double pu = 0, pv = 0;
                project.LowerDistanceParameters(pu, pv);
                gp_Pnt on_old;
                gp_Vec oa, ob;
                BRep_Tool::Surface(old_corner)->D1(pu, pv, on_old, oa, ob);
                gp_Vec n_old = oa.Crossed(ob);
                if (old_corner.Orientation() == TopAbs_REVERSED) {
                    n_old.Reverse();
                }
                if (da.Crossed(db).Dot(n_old) < 0) {
                    tri_face.Orientation(TopAbs_REVERSED);
                }
            }
            // Commit: the strips' end edges become the patch's sides, the old corner goes, the patch comes.
            for (int j = 0; j < 3; ++j) {
                const EndCurve &curve = loop[j];
                StripState &state = states[curve.strip];
                TopoDS_Vertex old_first, old_last;
                TopExp::Vertices(curve.old_edge, old_first, old_last, Standard_False);
                const bool old_runs_with_loop = old_first.IsSame(curve.from);
                for (int c = 0; c < 2; ++c) {
                    if (strips[curve.strip].ends[c].IsSame(curve.old_edge)) {
                        state.chain[c] = {{tri_edges[j], !old_runs_with_loop}};
                    }
                }
            }
            reshape.Remove(old_corner);
            g2_new_faces.push_back(tri_face);
            corner_patches[ci].push_back(tri_face);
            for (int j = 0; j < 3; ++j) {
                g2_edges.push_back(tri_edges[j]);
            }
            corner_done[ci] = true;
            ++report->g2_corners;
            ++report->corners;
            report->corner_milliseconds +=
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - clock0).count();
            report->corner_block_mismatch = std::max(report->corner_block_mismatch, stats.block_mismatch);
            report->corner_min_lambda = report->g2_corners == 1 ? stats.min_lambda : std::min(report->corner_min_lambda, stats.min_lambda);
            report->corner_max_curvature = std::max(report->corner_max_curvature, max_interior);
            report->corner_min_sine = report->g2_corners == 1 ? min_sine : std::min(report->corner_min_sine, min_sine);
        } catch (const std::exception &) {
            // The G1 refill takes this corner.
        } catch (const Standard_Failure &) {
        }
    }
}

void refill_corners(Run &r) {
    occt_g2_report *const report = r.report;
    const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces = r.edge_faces;
    const std::vector<TopoDS_Face> &corner_faces = r.corner_faces;
    BRep_Builder &builder = r.builder;
    BRepTools_ReShape &reshape = r.reshape;
    std::vector<Replaced> &replaced = r.replaced;
    std::vector<bool> &corner_done = r.corner_done;
    // Corner patches: refilled with MakeFilling constrained G1 against the strips (and the original faces) and
    // counted in g1_corners; if that misses the position or angle tolerance the fillet fails. A crease is
    // never returned. OCCT 7.9's MakeFilling cannot constrain G2 (GeomAbs_G2 is refused, order 2 builds
    // garbage), so there is no G2 attempt.
    struct CornerEdge {
        TopoDS_Edge shared;
        TopoDS_Face support;
    };
    for (std::size_t ci = 0; ci < corner_faces.size(); ++ci) {
        if (corner_done[ci]) {
            continue;
        }
        const TopoDS_Face old_corner = corner_faces[ci];
        std::vector<CornerEdge> ces;
        for (TopExp_Explorer it(old_corner, TopAbs_EDGE); it.More(); it.Next()) {
            const TopoDS_Edge e = TopoDS::Edge(it.Current());
            if (BRep_Tool::Degenerated(e)) {
                continue; // the sphere's pole
            }
            bool seen = false;
            CornerEdge ce;
            ce.shared = e;
            for (const Replaced &r : replaced) {
                if (r.old_edge.IsSame(e)) {
                    ce.shared = r.new_edge;
                    ce.support = r.strip;
                }
            }
            for (const CornerEdge &known : ces) {
                seen = seen || known.shared.IsSame(ce.shared);
            }
            if (seen) {
                continue;
            }
            if (ce.support.IsNull()) {
                for (const TopoDS_Face &f : distinct_faces(e, edge_faces)) {
                    if (!f.IsSame(old_corner)) {
                        ce.support = f;
                    }
                }
            }
            if (ce.support.IsNull() || is_blend(ce.support, corner_faces)) {
                throw user_error(kCornerMessage);
            }
            ces.push_back(ce);
        }
        struct Candidate {
            TopoDS_Face face;
            bool ok = false;
        };
        auto attempt = [&](GeomAbs_Shape order) -> Candidate {
            Candidate candidate;
            // One plain attempt: loading the old circular corner as the initial surface never worked with the new
            // boundary edges and cost 25 s on a pyramid's apex before the plain fill succeeded in milliseconds.
            for (int pass_count = 0; pass_count < 1 && !candidate.ok; ++pass_count) {
                try {
                    BRepFill_Filling fill(5, 30, 5, Standard_False, 1e-6, 1e-6, 1e-4, 1e-3, 12, 20);
                    for (const CornerEdge &ce : ces) {
                        fill.Add(TopoDS::Edge(ce.shared.Oriented(TopAbs_FORWARD)), ce.support, order, Standard_True);
                    }
                    fill.Build();
                    if (!fill.IsDone()) {
                        continue;
                    }
                    TopoDS_Face filled = fill.Face();
                    // The outward normal at the patch's middle must match the circular corner's there.
                    BRepAdaptor_Surface ns(filled, Standard_False);
                    gp_Pnt q;
                    gp_Vec a, b;
                    ns.D1(0.5 * (ns.FirstUParameter() + ns.LastUParameter()),
                          0.5 * (ns.FirstVParameter() + ns.LastVParameter()), q, a, b);
                    gp_Vec n_new = a.Crossed(b);
                    if (filled.Orientation() == TopAbs_REVERSED) {
                        n_new.Reverse();
                    }
                    GeomAPI_ProjectPointOnSurf project(q, BRep_Tool::Surface(old_corner));
                    double u = 0, v = 0;
                    project.LowerDistanceParameters(u, v);
                    gp_Pnt c2;
                    gp_Vec oa, ob;
                    BRepAdaptor_Surface(old_corner, Standard_False).D1(u, v, c2, oa, ob);
                    gp_Vec n_old = oa.Crossed(ob);
                    if (old_corner.Orientation() == TopAbs_REVERSED) {
                        n_old.Reverse();
                    }
                    if (n_new.Dot(n_old) < 0) {
                        filled.Reverse();
                    }
                    // Measure each boundary against its support, through the fill's own edge copies.
                    bool pass = true;
                    for (const CornerEdge &ce : ces) {
                        BRepAdaptor_Curve sc(ce.shared);
                        const gp_Pnt sm = sc.Value(0.5 * (sc.FirstParameter() + sc.LastParameter()));
                        TopoDS_Edge fe;
                        for (TopExp_Explorer it(filled, TopAbs_EDGE); it.More(); it.Next()) {
                            BRepAdaptor_Curve fc(TopoDS::Edge(it.Current()));
                            if (fc.Value(0.5 * (fc.FirstParameter() + fc.LastParameter())).Distance(sm) < 1e-6) {
                                fe = TopoDS::Edge(it.Current());
                            }
                        }
                        if (fe.IsNull()) {
                            pass = false;
                            break;
                        }
                        BRepAdaptor_Curve fc(fe);
                        occt_g2_seam seam{};
                        for (int k = 0; k <= kMeasureSamples; ++k) {
                            const double t = sc.FirstParameter() + (sc.LastParameter() - sc.FirstParameter()) * k / kMeasureSamples;
                            gp_Pnt p;
                            gp_Vec tangent;
                            sc.D1(t, p, tangent);
                            accumulate(seam, surface_point(ce.support, ce.shared, t), surface_point(filled, fe, t), tangent);
                        }
                        pass = pass && seam.position <= 1e-4 && seam.angle_degrees <= 0.01;
                        if (std::abs(fc.FirstParameter() - sc.FirstParameter()) > 1e-9 ||
                            std::abs(fc.LastParameter() - sc.LastParameter()) > 1e-9) {
                            pass = false;
                        }
                    }
                    if (pass) {
                        candidate.face = filled;
                        candidate.ok = true;
                    }
                } catch (const Standard_Failure &failure) {
                    continue;
                }
            }
            return candidate;
        };
        const Candidate chosen = attempt(GeomAbs_G1);
        if (!chosen.ok) {
            throw user_error(kCornerMessage);
        }
        ++report->g1_corners;
        // BRepFill_Filling makes copies of its boundary edges; rebuild the face on the shared edges.
        TopoDS_Face filled = chosen.face;
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
                for (const CornerEdge &ce : ces) {
                    BRepAdaptor_Curve nc(ce.shared);
                    if (nc.Value(0.5 * (nc.FirstParameter() + nc.LastParameter())).Distance(fm) < 1e-6) {
                        shared = ce.shared;
                    }
                }
                if (shared.IsNull() || pc.IsNull()) {
                    throw user_error(kCornerMessage);
                }
                BRepAdaptor_Curve nc(shared);
                if (nc.Value(nc.FirstParameter()).Distance(fc.Value(fc.FirstParameter())) > 1e-6) {
                    throw user_error(kCornerMessage);
                }
                // The fill meets its boundary to its own accuracy (up to the position promise): the edge's tolerance
                // covers how far its pcurve's surface point is from the shared 3D curve, as BRepCheck measures it.
                double deviation = 0;
                for (int k = 0; k <= kMeasureSamples; ++k) {
                    const double t = f2 + (l2 - f2) * k / kMeasureSamples;
                    const gp_Pnt2d uv = pc->Value(t);
                    const double ts = nc.FirstParameter() + (nc.LastParameter() - nc.FirstParameter()) * k / kMeasureSamples;
                    deviation = std::max(deviation, fill_surface->Value(uv.X(), uv.Y()).Distance(nc.Value(ts)));
                }
                builder.UpdateEdge(shared, pc, fill_surface, TopLoc_Location(), std::max(kEdgeTolerance, 1.5 * deviation));
                builder.Add(wire, shared.Oriented(it.Value().Orientation()));
            }
            wire.Orientation(wires.Value().Orientation());
            builder.Add(rebuilt, wire);
        }
        rebuilt.Orientation(filled.Orientation());
        reshape.Replace(old_corner, rebuilt);
        ++report->corners;
    }
}

} // namespace cocct::g2_blend
