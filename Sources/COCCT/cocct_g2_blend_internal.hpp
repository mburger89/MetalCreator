// What the files of the curvature-continuous fillet (G-b) share: the strip's springs and ends, the section data a built
// strip keeps, the state of one run, and the phases that run goes through. Private to the shim. The functions declared
// here are defined in the file named at each; everything else in those files is local to them.
//   cocct_g2_strip.cpp   springs, pairing, sections and the skinned surface; classifying a strip's edges; chained strips
//   cocct_g2_ends.cpp    slanted ends, mitres, the strip faces rebuilt on their new end edges
//   cocct_g2_corner.cpp  the degree-17 corner patches and the G1 refill
//   cocct_g2_seam.cpp    measuring and judging seams
//   cocct_g2_blend.cpp   the entry points: OCCT's fillet, the phases in order, history, validity
#ifndef COCCT_G2_BLEND_INTERNAL_HPP
#define COCCT_G2_BLEND_INTERNAL_HPP

#include "cocct_g2_section.hpp"
#include "cocct_internal.hpp"

#include <BRepTools_ReShape.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <Geom2d_BSplineCurve.hxx>
#include <Geom2d_Curve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <array>
#include <vector>

namespace cocct::g2_blend {

constexpr int kMeasureSamples = 61; // prime, so the samples never fall on the sections (at multiples of 1/2^k)
constexpr double kEdgeTolerance = 1e-6;
constexpr const char *kStripMessage = "The fillet can't be made curvature continuous at this radius.";
constexpr const char *kWeightMessage = "The tangency weight is too large for this fillet.";
constexpr const char *kCornerMessage = "The fillet's corners can't be made smooth at this radius.";

inline gp_Vec to_vec(const g2::Vec &v) { return gp_Vec(v[0], v[1], v[2]); }
inline g2::Vec from_vec(const gp_Vec &v) { return {v.X(), v.Y(), v.Z()}; }
inline g2::Vec from_pnt(const gp_Pnt &p) { return {p.X(), p.Y(), p.Z()}; }

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

SurfacePoint surface_point(const TopoDS_Face &face, const TopoDS_Edge &edge, double t);

struct Spring {
    TopoDS_Edge edge;
    TopoDS_Face neighbour;
    bool flipped = false; // sampled from its last parameter to its first
    double t_start = 0;   // the parameters sampling runs between: the edge's own, or extended past a slanted end
    double t_end = 0;
    bool has_tangent[2] = {false, false}; // a chain junction's agreed spring tangent at the start and end
    gp_Vec junction_tangent[2];
    std::vector<double> section_t;        // the built strip's sections' parameters on this edge, in sampling order
};

/// What a neighbour face gives at a section end.
struct NeighbourEnd {
    g2::EndCondition condition;
    gp_Pnt p;
    gp_Vec n;       // outward normal
    gp_Vec tangent; // of the spring edge
};

Handle(Geom2d_BSplineCurve) line2d(const gp_Pnt2d &from, const gp_Pnt2d &to, double first, double last);

struct BuiltStrip {
    Handle(Geom_BSplineSurface) surface;
    Handle(Geom2d_Curve) pcurve[2]; // of the first and second spring
    std::vector<std::array<g2::Vec, 6>> sections;
    std::vector<NeighbourEnd> first_ends, second_ends;
    std::vector<double> ta, tb; // each section's parameter on the first spring and on the second
};

bool is_blend(const TopoDS_Shape &face, const std::vector<TopoDS_Face> &blend);

struct StripEdges {
    Spring spring[2];
    TopoDS_Edge ends[2];
    TopoDS_Face end_face[2]; // null where the end borders a blend face
    TopoDS_Face end_strip[2]; // the other strip, where the end is a mitre between two strips at an angle
    TopoDS_Face end_chain[2]; // the next strip of a tangent chain, where the end is their shared junction
    bool closed = false;     // a hole edge's strip: its one seam is both ends
};

/// The springs and ends of a strip face (cocct_g2_strip.cpp).
StripEdges classify(const TopoDS_Face &strip, const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces,
                    const std::vector<TopoDS_Face> &blend, const std::vector<TopoDS_Face> &strips);

/// A strip end whose chord does not cross the springs squarely (the blend meets its end face at a slant) is built past
/// the end and trimmed by the end face. `a_end` and `b_end` are the springs' own end points, in sampling order.
struct Slant {
    bool slanted = false;
    gp_Pnt a_end, b_end;
};

/// Decides each sampling end and extends a slanted one (cocct_g2_ends.cpp).
void plan_slants(StripEdges &edges, Slant slants[2]);

/// Folds the gaps at one sample of a seam into `seam`; `a` and `b` are the two faces there, `tangent` the edge's
/// (cocct_g2_seam.cpp).
void accumulate(occt_g2_seam &seam, const SurfacePoint &a, const SurfacePoint &b, const gp_Vec &tangent,
                bool curvature = true);

/// The strip's gaps against one spring's neighbour, read off the candidate surface through the spring's pcurve before
/// any topology is built (cocct_g2_seam.cpp). `reversed`: the face is REVERSED, so its outward normal is the raw one's
/// opposite. `fractions` are the sections' places along the strip and `section_t` their parameters on this edge;
/// `intervals` gets, for each span between two sections, the worst gap found in it as a multiple of the (halved)
/// tolerances: more than 1 means the span needs a section. Every span is sampled, however narrow.
occt_g2_seam candidate_seam(const Handle(Geom_BSplineSurface) &surface, bool reversed, const Spring &spring,
                            const Handle(Geom2d_Curve) &pcurve, const std::vector<double> &fractions,
                            const std::vector<double> &section_t, std::vector<double> &intervals);

/// Half the promised tolerances, so the final measurement at other samples still has room (cocct_g2_seam.cpp).
bool within_tolerance(const occt_g2_seam &seam);

/// A strip's end edge that was replaced, with the strip face it ended up on.
struct Replaced {
    TopoDS_Edge old_edge, new_edge;
    TopoDS_Face strip;
};

        struct StripState {
            Slant slants[2];
            BuiltStrip built;
            bool swapped = false;
            TopoDS_Edge new_ends[2];
            bool flip_end[2] = {false, false}; // the new end edge runs the other way from the old one
            double spring_gap[2] = {0, 0};      // the strip's worst distance from each spring, as measured
            std::vector<std::pair<TopoDS_Edge, bool>> chain[2]; // an end that borders a G2 corner: its half edges
        };

/// Everything one run of the G2 fillet works on, passed from phase to phase. `faces` are those of `work`, a copy of
/// OCCT's circular result; the vectors parallel to `strip_faces` (`strips`, `states`) and to `corner_faces`
/// (`corner_done`, `corner_patches`) share its order.
struct Run {
    double radius = 0, weight = 0;
    bool use_patches = true;
    occt_g2_report *report = nullptr;
    TopoDS_Shape work, result;
    TopTools_IndexedMapOfShape faces;
    TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
    std::vector<int> strip_indices, corner_indices;
    std::vector<TopoDS_Face> strip_faces, corner_faces;
    BRep_Builder builder;
    BRepTools_ReShape reshape;
    std::vector<StripEdges> strips;
    std::vector<StripState> states;
    std::vector<TopoDS_Edge> kinked_joins, mitre_edges, g2_edges;
    std::vector<Replaced> replaced;
    std::vector<bool> corner_done;
    std::vector<TopoDS_Face> g2_new_faces;
    std::vector<std::vector<TopoDS_Face>> corner_patches; // the faces a replaced corner became
};

// The phases, in the order a run takes them. Each throws `user_error` when the blend can't be made.

/// Tangent chains: strips that meet end to end agree on a spring tangent there (cocct_g2_strip.cpp).
void agree_chain_tangents(Run &r);
/// Builds every strip, adding sections until its seams meet the (halved) tolerances (cocct_g2_strip.cpp).
void build_strips(Run &r);
/// Two strips that meet at an angle are cut by one another (cocct_g2_ends.cpp).
void cut_mitres(Run &r);
/// G2 corner patches where three strip ends meet; a corner not accepted is left to `refill_corners`
/// (cocct_g2_corner.cpp).
void place_corner_patches(Run &r);
/// Each strip's face rebuilt on its new end edges (cocct_g2_ends.cpp).
void rebuild_strip_faces(Run &r);
/// The corners left over, refilled G1 (cocct_g2_corner.cpp).
void refill_corners(Run &r);
/// Measures the seams in `r.result` against the promise (cocct_g2_seam.cpp).
void judge_result(Run &r);

} // namespace cocct::g2_blend

#endif
