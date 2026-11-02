// The ends of the strips of the curvature-continuous fillet: slanted ends built past the end face and trimmed by it,
// mitres between two strips at an angle, and each strip's face rebuilt on its new end edges
// (cocct_g2_blend_internal.hpp).

#include "cocct_g2_blend_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepLib.hxx>
#include <Extrema_ExtPC.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <GeomInt_IntSS.hxx>
#include <GeomProjLib.hxx>
#include <Geom_BezierCurve.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopoDS_Wire.hxx>

#include <algorithm>
#include <cmath>

namespace cocct::g2_blend {

/// Decides each sampling end and, for a slanted one, extends the shorter spring's sampling range past its end (by the
/// slant plus a margin) and the other's to the projection of that extended point, so the extended end is a square
/// cross-section again.
void plan_slants(StripEdges &edges, Slant slants[2]) {
    if (edges.closed) {
        return;
    }
    Spring *springs[2] = {&edges.spring[0], &edges.spring[1]};
    for (int e = 0; e < 2; ++e) {
        BRepAdaptor_Curve curves[2] = {BRepAdaptor_Curve(springs[0]->edge), BRepAdaptor_Curve(springs[1]->edge)};
        double te[2], outward[2];
        gp_Pnt point[2];
        gp_Vec tangent[2];
        for (int i = 0; i < 2; ++i) {
            const double direction = springs[i]->t_end > springs[i]->t_start ? 1 : -1;
            te[i] = e == 0 ? springs[i]->t_start : springs[i]->t_end;
            outward[i] = e == 0 ? -direction : direction;
            curves[i].D1(te[i], point[i], tangent[i]);
        }
        const gp_Vec chord(point[0], point[1]);
        gp_Vec out0 = tangent[0] * outward[0];
        out0.Normalize();
        const double m = chord.Dot(out0);
        // The end's edge, and whether it borders a face that is not a plane (a square end cannot lie on that: it is
        // built past the end and trimmed like a slanted one).
        const gp_Pnt middle((point[0].XYZ() + point[1].XYZ()) * 0.5);
        int nearest = 0;
        double nearest_gap = 1e300;
        for (int c = 0; c < 2; ++c) {
            BRepAdaptor_Curve oc(edges.ends[c]);
            const double d = oc.Value(0.5 * (oc.FirstParameter() + oc.LastParameter())).Distance(middle);
            if (d < nearest_gap) {
                nearest_gap = d;
                nearest = c;
            }
        }
        const bool curved_end = !edges.end_face[nearest].IsNull() &&
                                BRepAdaptor_Surface(edges.end_face[nearest], Standard_False).GetType() != GeomAbs_Plane;
        // A square section lies in the end face only if the springs run square to it: tilted by a hair, the section's
        // sag leaves the plane by more than the edge's tolerance (a drafted wall's edge meeting the base), so any
        // tilt is a slant.
        bool tilted_end = false;
        if (!edges.end_face[nearest].IsNull() && !curved_end) {
            const gp_Dir plane_normal = BRepAdaptor_Surface(edges.end_face[nearest], Standard_False).Plane().Axis().Direction();
            tilted_end = std::abs(gp_Vec(plane_normal).Dot(out0)) > 1e-6;
        }
        if (std::abs(m) <= 0.1 * chord.Magnitude() && !curved_end && !tilted_end) {
            continue;
        }
        // An end shared with a corner or the next strip of a chain is a section both must agree on; it stays square.
        if (edges.end_face[nearest].IsNull() && edges.end_strip[nearest].IsNull()) {
            continue;
        }
        slants[e].slanted = true;
        slants[e].a_end = point[0];
        slants[e].b_end = point[1];
        // The spring that ends first is extended; the other is extended to the projection of the first's new end.
        const int shorter = m > 0 ? 0 : 1, longer = 1 - shorter;
        const double length = 1.25 * std::abs(m) + 0.25 * chord.Magnitude();
        const double speed = std::max(tangent[shorter].Magnitude(), 1e-12);
        const double extended = te[shorter] + outward[shorter] * length / speed;
        const gp_Pnt target = curves[shorter].Value(extended);
        const double lo = std::min(springs[longer]->t_start, springs[longer]->t_end);
        const double hi = std::max(springs[longer]->t_start, springs[longer]->t_end);
        const double window = 0.5 * (hi - lo);
        Extrema_ExtPC ext(target, curves[longer], lo - window, hi + window);
        if (!ext.IsDone() || ext.NbExt() == 0) {
            throw user_error(kStripMessage);
        }
        int best = 1;
        for (int i = 2; i <= ext.NbExt(); ++i) {
            if (ext.SquareDistance(i) < ext.SquareDistance(best)) {
                best = i;
            }
        }
        double projected = ext.Point(best).Parameter();
        if (curves[longer].IsPeriodic()) {
            const double period = curves[longer].Period();
            projected += period * std::round((te[longer] - projected) / period);
        }
        if (outward[longer] * (projected - te[longer]) <= 0) {
            throw user_error(kStripMessage);
        }
        (e == 0 ? springs[shorter]->t_start : springs[shorter]->t_end) = extended;
        (e == 0 ? springs[longer]->t_start : springs[longer]->t_end) = projected;
    }
}

namespace {

/// The edge where a strip, built past its end, meets that end's face (or the partner strip at a mitre): the
/// surfaces' intersection between the two springs' own end points, with pcurves on both and the old vertices.
TopoDS_Edge trim_edge(BRep_Builder &builder, const TopoDS_Edge &old_edge, const Handle(Geom_Surface) &surface,
                      const Handle(Geom_Surface) &face_surface, const TopLoc_Location &face_location, const gp_Pnt &a_end,
                      const gp_Pnt &b_end, bool &flip) {
    if (face_surface.IsNull()) {
        throw user_error(kStripMessage);
    }
    // The intersection runs in global coordinates; the face keeps its own frame and location.
    const Handle(Geom_Surface) global_face_surface =
        face_location.IsIdentity() ? face_surface
                                   : Handle(Geom_Surface)::DownCast(face_surface->Transformed(face_location.Transformation()));
    GeomInt_IntSS intersection(surface, global_face_surface, 1e-7, Standard_True, Standard_True, Standard_True);
    int line = 0;
    double best_gap = 1e-4, pa = 0, pb = 0;
    // The parameter and distance of the point on a line: the projection, else (a point at the very end of
    // the curve, which the projection may miss by a hair) the nearer end.
    auto locate = [](const Handle(Geom_Curve) &candidate, const gp_Pnt &point, double &parameter) {
        GeomAPI_ProjectPointOnCurve project(point, candidate);
        double distance = 1e300;
        if (project.NbPoints() > 0) {
            parameter = project.LowerDistanceParameter();
            distance = project.LowerDistance();
        }
        for (double end : {candidate->FirstParameter(), candidate->LastParameter()}) {
            const double d = candidate->Value(end).Distance(point);
            if (d < distance) {
                distance = d;
                parameter = end;
            }
        }
        return distance;
    };
    for (int i = 1; i <= intersection.NbLines(); ++i) {
        const Handle(Geom_Curve) candidate = intersection.Line(i);
        double ta = 0, tb = 0;
        const double gap = locate(candidate, a_end, ta) + locate(candidate, b_end, tb);
        if (gap < best_gap) {
            best_gap = gap;
            line = i;
            pa = ta;
            pb = tb;
        }
    }
    if (line == 0 || std::abs(pa - pb) < 1e-9) {
        throw user_error(kStripMessage);
    }
    const Handle(Geom_Curve) curve = intersection.Line(line);
    const double lo = std::min(pa, pb), hi = std::max(pa, pb);
    TopoDS_Vertex v1, v2;
    TopExp::Vertices(old_edge, v1, v2, Standard_False);
    const bool first_is_v1 = BRep_Tool::Pnt(v1).Distance(curve->Value(lo)) <= BRep_Tool::Pnt(v2).Distance(curve->Value(lo));
    // The intersection runs through the springs' end points to within its own accuracy: the vertices take that
    // gap as tolerance. Up to the position promise (1e-4 mm) is accepted; a larger one is not a trimmed end of
    // this strip.
    const TopoDS_Vertex &vertex_lo = first_is_v1 ? v1 : v2, &vertex_hi = first_is_v1 ? v2 : v1;
    const double gap_lo = BRep_Tool::Pnt(vertex_lo).Distance(curve->Value(lo));
    const double gap_hi = BRep_Tool::Pnt(vertex_hi).Distance(curve->Value(hi));
    if (std::max(gap_lo, gap_hi) > 1e-4) {
        throw user_error(kStripMessage);
    }
    builder.UpdateVertex(vertex_lo, std::max(BRep_Tool::Tolerance(vertex_lo), gap_lo));
    builder.UpdateVertex(vertex_hi, std::max(BRep_Tool::Tolerance(vertex_hi), gap_hi));
    TopoDS_Edge ne;
    builder.MakeEdge(ne, curve, 1e-5);
    builder.Add(ne, vertex_lo.Oriented(TopAbs_FORWARD));
    builder.Add(ne, vertex_hi.Oriented(TopAbs_REVERSED));
    builder.Range(ne, lo, hi);
    Handle(Geom2d_Curve) on_strip = intersection.HasLineOnS1(line) ? intersection.LineOnS1(line)
                                                                     : GeomProjLib::Curve2d(curve, lo, hi, surface);
    Handle(Geom2d_Curve) on_face = intersection.HasLineOnS2(line) ? intersection.LineOnS2(line)
                                                                   : GeomProjLib::Curve2d(curve, lo, hi, global_face_surface);
    if (on_strip.IsNull() || on_face.IsNull()) {
        throw user_error(kStripMessage);
    }
    builder.UpdateEdge(ne, on_strip, surface, TopLoc_Location(), 1e-5);
    builder.Range(ne, surface, TopLoc_Location(), lo, hi);
    builder.UpdateEdge(ne, on_face, face_surface, face_location, 1e-5);
    builder.Range(ne, face_surface, face_location, lo, hi);
    flip = !first_is_v1;
    return ne;
}

} // namespace

void cut_mitres(Run &r) {
    occt_g2_report *const report = r.report;
    const std::vector<TopoDS_Face> &strip_faces = r.strip_faces;
    BRep_Builder &builder = r.builder;
    BRepTools_ReShape &reshape = r.reshape;
    std::vector<StripEdges> &strips = r.strips;
    std::vector<Replaced> &replaced = r.replaced;
    std::vector<TopoDS_Edge> &mitre_edges = r.mitre_edges;
    std::vector<StripState> &states = r.states;
    // Mitres: two strips that meet at an angle are each built past their shared end and cut by one another;
    // the new shared edge is their intersection, between the vertices of the old one.
    for (std::size_t s = 0; s < strips.size(); ++s) {
        for (int end = 0; end < 2; ++end) {
            StripEdges &edges = strips[s];
            if (edges.closed || !states[s].slants[end].slanted) {
                continue;
            }
            const Slant &slant = states[s].slants[end];
            const gp_Pnt middle((slant.a_end.XYZ() + slant.b_end.XYZ()) * 0.5);
            int chosen = 0;
            double best = 1e300;
            for (int c = 0; c < 2; ++c) {
                BRepAdaptor_Curve oc(edges.ends[c]);
                const double d = oc.Value(0.5 * (oc.FirstParameter() + oc.LastParameter())).Distance(middle);
                if (d < best) {
                    best = d;
                    chosen = c;
                }
            }
            if (edges.end_strip[chosen].IsNull() || !states[s].new_ends[chosen].IsNull()) {
                continue;
            }
            std::size_t partner = strips.size();
            for (std::size_t t = 0; t < strips.size(); ++t) {
                if (strip_faces[t].IsSame(edges.end_strip[chosen])) {
                    partner = t;
                }
            }
            if (partner == strips.size() || partner == s) {
                throw user_error(kStripMessage);
            }
            // The partner's matching end: its end edge that is this very (old) edge.
            const TopoDS_Edge old_edge = edges.ends[chosen];
            int partner_chosen = -1;
            for (int c = 0; c < 2; ++c) {
                if (strips[partner].ends[c].IsSame(old_edge)) {
                    partner_chosen = c;
                }
            }
            bool partner_extended = false;
            for (int e2 = 0; e2 < 2; ++e2) {
                partner_extended = partner_extended || states[partner].slants[e2].slanted;
            }
            if (partner_chosen < 0 || !partner_extended) {
                throw user_error(kStripMessage);
            }
            bool flip = false;
            const TopoDS_Edge ne = trim_edge(builder, old_edge, states[s].built.surface, states[partner].built.surface,
                                             TopLoc_Location(), slant.a_end, slant.b_end, flip);
            const TopAbs_Orientation oriented = flip ? TopAbs::Reverse(old_edge.Orientation()) : old_edge.Orientation();
            reshape.Replace(old_edge, ne.Oriented(oriented));
            replaced.push_back({old_edge, ne, TopoDS_Face()});
            states[s].new_ends[chosen] = ne;
            states[s].flip_end[chosen] = flip;
            states[partner].new_ends[partner_chosen] = ne;
            states[partner].flip_end[partner_chosen] = flip;
            mitre_edges.push_back(ne);
            ++report->mitres;
        }
    }
}

void rebuild_strip_faces(Run &r) {
    occt_g2_report *const report = r.report;
    const std::vector<TopoDS_Face> &strip_faces = r.strip_faces;
    BRep_Builder &builder = r.builder;
    BRepTools_ReShape &reshape = r.reshape;
    std::vector<StripEdges> &strips = r.strips;
    std::vector<Replaced> &replaced = r.replaced;
    std::vector<StripState> &states = r.states;
    for (std::size_t s = 0; s < strips.size(); ++s) {
        const TopoDS_Face old_face = strip_faces[s];
        StripEdges &edges = strips[s];
        StripState &state = states[s];
        Slant(&slants)[2] = state.slants;
        const BuiltStrip &built = state.built;
        const bool swapped = state.swapped;
        const Handle(Geom_Surface) surface = built.surface;
        TopoDS_Edge(&new_ends)[2] = state.new_ends;
        bool(&flip_end)[2] = state.flip_end;
        (void)swapped;
        // End edges become the first and last sections (shared with the next strip of a tangent chain).
        TopoDS_Edge seam_edge;       // a closed strip's one seam, both ends
        bool seam_reversed = false;
        for (int end = 0; end < (edges.closed ? 1 : 2); ++end) {
            if (slants[end].slanted) {
                // A slanted end: the strip was built past the end face; its end edge is the surface's
                // intersection with that face, between the springs' own end points.
                const gp_Pnt a_end = slants[end].a_end, b_end = slants[end].b_end;
                const gp_Pnt middle((a_end.XYZ() + b_end.XYZ()) * 0.5);
                int chosen = 0;
                double best = 1e300;
                for (int c = 0; c < 2; ++c) {
                    BRepAdaptor_Curve oc(edges.ends[c]);
                    const double d = oc.Value(0.5 * (oc.FirstParameter() + oc.LastParameter())).Distance(middle);
                    if (d < best) {
                        best = d;
                        chosen = c;
                    }
                }
                if (!new_ends[chosen].IsNull()) {
                    continue; // a mitre, made with the partner strip
                }
                const TopoDS_Edge old_edge = edges.ends[chosen];
                const TopoDS_Face end_face = edges.end_face[chosen];
                TopLoc_Location face_location;
                const Handle(Geom_Surface) face_surface = end_face.IsNull() ? Handle(Geom_Surface)()
                                                                            : BRep_Tool::Surface(end_face, face_location);
                if (face_surface.IsNull()) {
                    throw user_error(kStripMessage);
                }
                TopoDS_Edge ne = trim_edge(builder, old_edge, surface, face_surface, face_location, a_end, b_end, flip_end[chosen]);
                const TopAbs_Orientation oriented = flip_end[chosen] ? TopAbs::Reverse(old_edge.Orientation()) : old_edge.Orientation();
                reshape.Replace(old_edge, ne.Oriented(oriented));
                replaced.push_back({old_edge, ne, TopoDS_Face()});
                new_ends[chosen] = ne;
                continue;
            }
            TColgp_Array1OfPnt poles(1, 6);
            const auto &section = end == 0 ? built.sections.front() : built.sections.back();
            for (int i = 0; i < 6; ++i) {
                poles.SetValue(i + 1, gp_Pnt(section[i][0], section[i][1], section[i][2]));
            }
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
            if (!state.chain[chosen].empty()) {
                continue; // an end on a G2 corner: its two half edges stand in for it
            }
            TopoDS_Edge ne;
            bool reversed = false;
            for (const Replaced &r : replaced) {
                if (r.old_edge.IsSame(old_edge)) {
                    ne = r.new_edge; // the previous strip of a tangent chain made it
                }
            }
            if (!ne.IsNull()) {
                BRepAdaptor_Curve nc(ne);
                reversed = nc.Value(0).Distance(bezier->Value(0)) > nc.Value(0).Distance(bezier->Value(1));
                // The shared section is this strip's own, up to what the two neighbours' surfaces differ by at
                // the junction (they agree on the spring tangent; a strip-to-strip seam is promised its
                // position only): within 1e-4 mm, with the edge's tolerance covering the difference.
                double deviation = 0;
                for (int k = 0; k <= 16; ++k) {
                    const double t = k / 16.0;
                    deviation = std::max(deviation, nc.Value(t).Distance(bezier->Value(reversed ? 1 - t : t)));
                }
                if (deviation > 1e-4) {
                    throw user_error(kStripMessage);
                }
                builder.UpdateEdge(ne, std::max(BRep_Tool::Tolerance(ne), 1.5 * deviation));
            } else {
                TopoDS_Vertex v1, v2;
                TopExp::Vertices(old_edge, v1, v2, Standard_False);
                const gp_Pnt p_first = BRep_Tool::Pnt(v1);
                reversed = bezier->Value(0).Distance(p_first) > bezier->Value(1).Distance(p_first);
                Handle(Geom_BezierCurve) curve = bezier;
                if (reversed) {
                    curve = Handle(Geom_BezierCurve)::DownCast(bezier->Reversed());
                }
                builder.MakeEdge(ne, curve, kEdgeTolerance);
                builder.Add(ne, v1.Oriented(TopAbs_FORWARD));
                builder.Add(ne, v2.Oriented(TopAbs_REVERSED));
                builder.Range(ne, 0, 1);
                // The replacement carries the old occurrence's orientation: Replace composes the two.
                reshape.Replace(old_edge, ne.Oriented(old_edge.Orientation()));
                replaced.push_back({old_edge, ne, TopoDS_Face()});
            }
            if (edges.closed) {
                seam_edge = ne;
                seam_reversed = reversed;
                new_ends[0] = new_ends[1] = ne;
                break;
            }
            const double u_iso = end;
            // Section poles run from the first spring (v = 0) to the second (v = 1).
            const Handle(Geom2d_BSplineCurve) pcs = reversed ? line2d(gp_Pnt2d(u_iso, 1), gp_Pnt2d(u_iso, 0), 0, 1)
                                                               : line2d(gp_Pnt2d(u_iso, 0), gp_Pnt2d(u_iso, 1), 0, 1);
            builder.UpdateEdge(ne, pcs, surface, TopLoc_Location(), kEdgeTolerance);
            if (!edges.end_face[chosen].IsNull()) {
                if (BRepAdaptor_Surface(edges.end_face[chosen], Standard_False).GetType() != GeomAbs_Plane) {
                    throw user_error(kStripMessage);
                }
                BRepLib::BuildPCurveForEdgeOnPlane(ne, edges.end_face[chosen]);
            }
            new_ends[chosen] = ne;
        }
        // A closed strip's seam lies on the surface twice, at u = 0 and u = 1; which pcurve belongs to which
        // orientation is settled below by the face's own check.
        auto seam_pcurves = [&](bool swap) {
            auto at = [&](double u) {
                return seam_reversed ? line2d(gp_Pnt2d(u, 1), gp_Pnt2d(u, 0), 0, 1)
                                     : line2d(gp_Pnt2d(u, 0), gp_Pnt2d(u, 1), 0, 1);
            };
            builder.UpdateEdge(seam_edge, at(swap ? 1 : 0), at(swap ? 0 : 1), surface, TopLoc_Location(), kEdgeTolerance);
        };
        if (edges.closed) {
            seam_pcurves(false);
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
                bool expanded = false;
                for (int c = 0; c < 2 && !expanded; ++c) {
                    if (e.IsSame(edges.ends[c]) && !state.chain[c].empty()) {
                        // A G2 corner replaced this end by two half edges, listed in the old edge's own
                        // direction; the wire takes them in the direction it traverses the old edge.
                        auto sequence = state.chain[c];
                        const bool wire_reversed = it.Value().Orientation() == TopAbs_REVERSED;
                        if (wire_reversed) {
                            std::reverse(sequence.begin(), sequence.end());
                        }
                        for (const auto &[half_edge, against] : sequence) {
                            builder.Add(new_wire, half_edge.Oriented((against != wire_reversed) ? TopAbs_REVERSED : TopAbs_FORWARD));
                        }
                        expanded = true;
                    }
                }
                if (expanded) {
                    continue;
                }
                for (int c = 0; c < 2; ++c) {
                    if (e.IsSame(edges.ends[c])) {
                        e = new_ends[c].Oriented(flip_end[c] ? TopAbs::Reverse(it.Value().Orientation()) : it.Value().Orientation());
                    }
                }
                builder.Add(new_wire, e);
            }
            new_wire.Orientation(wires.Value().Orientation());
            builder.Add(new_face, new_wire);
        }
        new_face.Orientation(old_face.Orientation());
        if (edges.closed && !BRepCheck_Analyzer(new_face).IsValid()) {
            seam_pcurves(true);
            if (!BRepCheck_Analyzer(new_face).IsValid()) {
                throw user_error(kStripMessage);
            }
        }
        reshape.Replace(old_face, new_face);
        for (Replaced &r : replaced) {
            if (r.strip.IsNull()) {
                r.strip = new_face;
            }
        }
        ++report->strips;
    }
}

} // namespace cocct::g2_blend
