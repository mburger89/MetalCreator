// Seams of the curvature-continuous fillet: the position, angle and curvature gaps between two faces along an edge,
// measured on a candidate strip before any topology is built and on the final solid (cocct_g2_blend_internal.hpp).

#include "cocct_g2_blend_internal.hpp"

#include <BRepAdaptor_Curve.hxx>

#include <algorithm>
#include <cmath>

namespace cocct::g2_blend {

namespace {

// Prime sample counts, so that the samples never fall on the sections (which sit at multiples of 1/2^k) and measure
// the worst place between them.
constexpr int kCheckSamples = 127;  // samples per spring edge when a candidate strip is judged
// Where the springs of two chained strips kink at their junction (the faces under them are only G1 there), the strip's
// across direction is the bisector's, and the curvature comparison skips this share of the edge next to the junction.
constexpr int kJunctionSamples = 2;

/// The worst position, angle and curvature gaps along `edge` between the two faces that share it.
occt_g2_seam measure_seam(const TopoDS_Edge &edge, const TopoDS_Face &f1, const TopoDS_Face &f2,
                          const bool exempt_ends[2] = nullptr) {
    occt_g2_seam seam{};
    BRepAdaptor_Curve curve(edge);
    for (int k = 0; k <= kMeasureSamples; ++k) {
        const double t = curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * k / kMeasureSamples;
        gp_Pnt p;
        gp_Vec tangent;
        curve.D1(t, p, tangent);
        const bool near_start = exempt_ends && exempt_ends[0] && k <= kJunctionSamples;
        const bool near_end = exempt_ends && exempt_ends[1] && k >= kMeasureSamples - kJunctionSamples;
        accumulate(seam, surface_point(f1, edge, t), surface_point(f2, edge, t), tangent, !(near_start || near_end));
    }
    return seam;
}

/// The promise itself: position 1e-4 mm, angle 0.01 degrees, curvature within its allowance.
bool meets_promise(const occt_g2_seam &seam, bool curvature = true) {
    return seam.position <= 1e-4 && seam.angle_degrees <= 0.01 && (!curvature || seam.curvature_ratio <= 1);
}

} // namespace

void accumulate(occt_g2_seam &seam, const SurfacePoint &a, const SurfacePoint &b, const gp_Vec &tangent,
                bool curvature) {
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
    if (!curvature) {
        return;
    }
    seam.curvature = std::max(seam.curvature, gap);
    if (gap / allowed >= seam.curvature_ratio) {
        seam.curvature_ratio = gap / allowed;
        seam.curvature_allowed = allowed;
    }
}

occt_g2_seam candidate_seam(const Handle(Geom_BSplineSurface) &surface, bool reversed, const Spring &spring,
                            const Handle(Geom2d_Curve) &pcurve, const std::vector<double> &fractions,
                            std::vector<double> &intervals) {
    occt_g2_seam seam{};
    BRepAdaptor_Curve curve(spring.edge);
    const int samples = std::max(kCheckSamples, 4 * static_cast<int>(fractions.size()) + 3);
    intervals.assign(fractions.size() - 1, 0.0);
    for (int k = 0; k <= samples; ++k) {
        const double t = curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * k / samples;
        const gp_Pnt2d uv = pcurve->Value(t);
        SurfacePoint strip;
        surface->D2(uv.X(), uv.Y(), strip.p, strip.su, strip.sv, strip.suu, strip.svv, strip.suv);
        strip.n = strip.su.Crossed(strip.sv);
        strip.n.Normalize();
        if (reversed) {
            strip.n.Reverse();
        }
        gp_Pnt p;
        gp_Vec tangent;
        curve.D1(t, p, tangent);
        occt_g2_seam here{};
        // The sampling start/end of the spring in parameter terms, for the junction exemption.
        const double length = std::abs(spring.t_end - spring.t_start);
        const bool near_start = spring.kinked[0] && std::abs(t - spring.t_start) < 0.0335 * length;
        const bool near_end = spring.kinked[1] && std::abs(t - spring.t_end) < 0.0335 * length;
        const bool compare_curvature = !(near_start || near_end);
        accumulate(here, strip, surface_point(spring.neighbour, spring.edge, t), tangent, compare_curvature);
        accumulate(seam, strip, surface_point(spring.neighbour, spring.edge, t), tangent, compare_curvature);
        const auto after = std::upper_bound(fractions.begin(), fractions.end(), uv.X());
        const std::size_t span = std::min<std::size_t>(std::max<std::ptrdiff_t>(after - fractions.begin() - 1, 0),
                                                       intervals.size() - 1);
        intervals[span] = std::max({intervals[span], here.position / 2e-5, here.angle_degrees / 0.005,
                                    here.curvature_ratio / 0.5});
    }
    return seam;
}

bool within_tolerance(const occt_g2_seam &seam) {
    // Half the promised tolerances, so the final measurement at other samples still has room.
    return seam.position <= 2e-5 && seam.angle_degrees <= 0.005 && seam.curvature_ratio <= 0.5;
}

void judge_result(Run &r) {
    occt_g2_report *const report = r.report;
    TopoDS_Shape &result = r.result;
    const TopTools_IndexedMapOfShape &faces = r.faces;
    const std::vector<int> &strip_indices = r.strip_indices;
    const std::vector<int> &corner_indices = r.corner_indices;
    BRepTools_ReShape &reshape = r.reshape;
    std::vector<StripEdges> &strips = r.strips;
    std::vector<TopoDS_Edge> &mitre_edges = r.mitre_edges;
    std::vector<bool> &corner_done = r.corner_done;
    std::vector<TopoDS_Face> &g2_new_faces = r.g2_new_faces;
    std::vector<TopoDS_Edge> &g2_edges = r.g2_edges;
    // Measure the seams in the result: the strips' springs, then the corners' boundaries, kept apart.
    const TopTools_IndexedMapOfShape result_faces = map_of(result, TopAbs_FACE);
    TopTools_IndexedDataMapOfShapeListOfShape result_edge_faces;
    TopExp::MapShapesAndAncestors(result, TopAbs_EDGE, TopAbs_FACE, result_edge_faces);
    // A face of the circular result, in the new solid (by index, or through the replacements once faces were added).
    auto result_face = [&](int index) {
        return g2_new_faces.empty() ? TopoDS::Face(result_faces(index)) : TopoDS::Face(reshape.Apply(faces(index)));
    };
    std::vector<TopoDS_Face> result_strips;
    for (int index : strip_indices) {
        result_strips.push_back(result_face(index));
    }
    for (std::size_t s = 0; s < result_strips.size(); ++s) {
        const TopoDS_Face &strip = result_strips[s];
        // The strips were classified before the faces were rebuilt; their spring edges are the same edges now.
        for (const Spring &spring : strips[s].spring) {
            // The springs' junction tangents were set on the strips as first classified.
            bool exempt[2] = {false, false};
            exempt[0] = spring.flipped ? spring.kinked[1] : spring.kinked[0];
            exempt[1] = spring.flipped ? spring.kinked[0] : spring.kinked[1];
            // Every promised spring seam is judged here, whatever the report's array can hold.
            const occt_g2_seam seam = measure_seam(spring.edge, strip, spring.neighbour, exempt);
            ++report->seams_total;
            if (!meets_promise(seam)) {
                throw user_error(kStripMessage);
            }
            if (report->seam_count < OCCT_G2_MAX_SEAMS) {
                report->seams[report->seam_count++] = seam;
            }
        }
    }
    report->seams_judged = 1;
    // A mitre is a crease between two strips (the circular fillet has the same one): the seam must close to within
    // the position tolerance, and its angle is recorded.
    for (const TopoDS_Edge &edge : mitre_edges) {
        if (!result_edge_faces.Contains(edge)) {
            throw user_error(kStripMessage);
        }
        const std::vector<TopoDS_Face> sides = distinct_faces(edge, result_edge_faces);
        if (sides.size() != 2) {
            throw user_error(kStripMessage);
        }
        const occt_g2_seam seam = measure_seam(edge, sides[0], sides[1]);
        if (seam.position > 1e-4) {
            throw user_error(kStripMessage);
        }
        if (report->mitre_seam_count < OCCT_G2_MAX_SEAMS) {
            report->mitre_seams[report->mitre_seam_count++] = seam;
        }
    }
    for (const TopoDS_Edge &edge : g2_edges) {
        const std::vector<TopoDS_Face> sides = distinct_faces(edge, result_edge_faces);
        if (sides.size() != 2) {
            throw user_error(kCornerMessage); // a corner's edge must border exactly two faces
        }
        const occt_g2_seam seam = measure_seam(edge, sides[0], sides[1]);
        if (!meets_promise(seam)) {
            throw user_error(kCornerMessage); // a G2 patch that misses the promise on the final solid
        }
        if (report->corner_seam_count < OCCT_G2_MAX_SEAMS) {
            report->corner_seams[report->corner_seam_count++] = seam;
        }
    }
    for (std::size_t ci = 0; ci < corner_indices.size(); ++ci) {
        if (ci < corner_done.size() && corner_done[ci]) {
            continue;
        }
        const int index = corner_indices[ci];
        const TopoDS_Face corner = result_face(index);
        for (TopExp_Explorer it(corner, TopAbs_EDGE); it.More(); it.Next()) {
            const TopoDS_Edge e = TopoDS::Edge(it.Current());
            if (BRep_Tool::Degenerated(e)) {
                continue;
            }
            const std::vector<TopoDS_Face> around = distinct_faces(e, result_edge_faces);
            if (around.size() != 2) {
                throw user_error(kCornerMessage); // a corner's edge must border exactly two faces
            }
            for (const TopoDS_Face &other : around) {
                if (other.IsSame(corner)) {
                    continue;
                }
                const occt_g2_seam seam = measure_seam(e, corner, other);
                if (seam.angle_degrees > 0.01) {
                    throw user_error(kCornerMessage); // a G1 refill is tangent to its neighbours or it is refused
                }
                if (report->corner_seam_count < OCCT_G2_MAX_SEAMS) {
                    report->corner_seams[report->corner_seam_count++] = seam;
                }
            }
        }
    }
}

} // namespace cocct::g2_blend
