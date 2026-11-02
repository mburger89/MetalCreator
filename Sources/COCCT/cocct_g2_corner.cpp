// The corners of the curvature-continuous fillet: a corner where three strips end becomes one three-sided G2 patch
// (cocct_g2_triangle.hpp), and any other is refilled G1 (cocct_g2_blend_internal.hpp).

#include "cocct_g2_triangle.hpp"
#include "cocct_g2_blend_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepFill_Filling.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <GeomAbs_Shape.hxx>
#include <Geom_BezierCurve.hxx>
#include <Geom_BezierSurface.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopoDS_Wire.hxx>

#include <algorithm>
#include <chrono>
#include <cmath>

namespace cocct::g2_blend {

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
            for (EndCurve &curve : loop) {
                TopoDS_Vertex v1, v2;
                TopExp::Vertices(curve.old_edge, v1, v2, Standard_False);
                const bool first_is_start = close(curve.poles[0], {BRep_Tool::Pnt(v1).X(), BRep_Tool::Pnt(v1).Y(), BRep_Tool::Pnt(v1).Z()});
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
                        accumulate(seam, on_surface(states[curve.strip].built.surface, gp_Pnt2d(u_end, v), strip_reversed),
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
                builder.UpdateEdge(tri_edges[j], line2d(gp_Pnt2d(u_end, v_start), gp_Pnt2d(u_end, v_end), 0, 1),
                                   states[curve.strip].built.surface, TopLoc_Location(), kEdgeTolerance);
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
