// The boundary patch (NURBS spec, NS-2 Task 4): one face that fills a closed loop of bounding pieces, by BRepFill_Filling.
//
// The pieces are the edges of some curves and some picked edges of a part. They are chained into one loop (a gap is named by
// the two pieces it lies between), added to the fill (a picked sheet edge with a support face is held tangent to it) and the
// result is measured: every piece within 1e-4 mm and every interior point within 1e-3 mm. Tangency is graded by the caller, through
// the two-body continuity call, because it needs the part as a second body.

#include "cocct_sheet.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepFill_Filling.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <GeomAbs_Shape.hxx>
#include <Geom_Surface.hxx>
#include <ShapeAnalysis_FreeBounds.hxx>
#include <TopTools_HSequenceOfShape.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Pnt.hxx>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

using namespace cocct;

namespace {

constexpr const char *kCancelled = "The operation was cancelled.";
constexpr double kJoinTolerance = 1e-4;
constexpr double kPositionTolerance = 1e-4;
constexpr double kPointTolerance = 1e-3;
constexpr int kLeastPieces = 2;
constexpr int kMostPieces = 16;
constexpr int kSamplesPerPiece = 17;

void poll(const occt_cancel *cancel) {
    if (cancel && cancel->flag.load() != 0) {
        throw user_error(kCancelled);
    }
}

std::string number(double value) {
    char text[48];
    std::snprintf(text, sizeof text, "%.9g", value);
    return std::string(1, '\x01') + text + std::string(1, '\x02');
}

/// One bounding piece, in input order.
struct piece {
    TopoDS_Edge edge;
    TopoDS_Face support; // null: held to position only
};

gp_Pnt at_fraction(const TopoDS_Edge &edge, double fraction) {
    BRepAdaptor_Curve curve(edge);
    return curve.Value(curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * fraction);
}

/// The two ends of a piece as it is oriented.
void ends_of(const TopoDS_Edge &edge, gp_Pnt &start, gp_Pnt &end) {
    BRepAdaptor_Curve curve(edge);
    start = curve.Value(curve.FirstParameter());
    end = curve.Value(curve.LastParameter());
    if (edge.Orientation() == TopAbs_REVERSED) {
        std::swap(start, end);
    }
}

std::vector<TopoDS_Edge> edges_of(const TopoDS_Wire &wire) {
    std::vector<TopoDS_Edge> edges;
    for (BRepTools_WireExplorer explorer(wire); explorer.More(); explorer.Next()) {
        edges.push_back(explorer.Current());
    }
    return edges;
}

/// Whether the wire's edges, in order, end where they started.
bool is_closed_loop(const std::vector<TopoDS_Edge> &edges) {
    if (edges.empty()) {
        return false;
    }
    gp_Pnt first, ignored, last;
    ends_of(edges.front(), first, ignored);
    ends_of(edges.back(), ignored, last);
    return first.Distance(last) <= kJoinTolerance;
}

/// The refusal for pieces that don't close: names the two nearest loose ends that belong to different pieces.
std::string gap_message(const std::vector<piece> &pieces) {
    struct loose {
        std::size_t piece_index;
        gp_Pnt point;
    };
    std::vector<loose> ends;
    for (std::size_t i = 0; i < pieces.size(); ++i) {
        gp_Pnt a, b;
        ends_of(pieces[i].edge, a, b);
        for (const gp_Pnt &p : {a, b}) {
            bool met = false;
            for (std::size_t j = 0; j < pieces.size() && !met; ++j) {
                if (j == i) {
                    continue;
                }
                gp_Pnt c, d;
                ends_of(pieces[j].edge, c, d);
                met = p.Distance(c) <= kJoinTolerance || p.Distance(d) <= kJoinTolerance;
            }
            if (!met) {
                ends.push_back({i, p});
            }
        }
    }
    double best = -1;
    std::size_t first = 0;
    std::size_t second = 0;
    for (std::size_t a = 0; a < ends.size(); ++a) {
        for (std::size_t b = a + 1; b < ends.size(); ++b) {
            if (ends[a].piece_index == ends[b].piece_index) {
                continue;
            }
            const double distance = ends[a].point.Distance(ends[b].point);
            if (best < 0 || distance < best) {
                best = distance;
                first = std::min(ends[a].piece_index, ends[b].piece_index);
                second = std::max(ends[a].piece_index, ends[b].piece_index);
            }
        }
    }
    if (best < 0) {
        return "The bounding pieces don't form a closed loop.";
    }
    return "The bounding pieces don't form a closed loop; pieces " + std::to_string(first + 1) + " and " +
           std::to_string(second + 1) + " are " + number(best) + " mm apart.";
}

/// The input piece a loop edge is: the nearest by its middle, within a hair.
int piece_of(const TopoDS_Edge &edge, const std::vector<piece> &pieces) {
    const gp_Pnt middle = at_fraction(edge, 0.5);
    int found = -1;
    double best = 1e-6;
    for (std::size_t i = 0; i < pieces.size(); ++i) {
        const double distance = at_fraction(pieces[i].edge, 0.5).Distance(middle);
        if (distance <= best) {
            best = distance;
            found = static_cast<int>(i);
        }
    }
    return found;
}

double distance_to_surface(const gp_Pnt &point, const Handle(Geom_Surface) & surface) {
    GeomAPI_ProjectPointOnSurf project(point, surface);
    return project.NbPoints() > 0 ? project.LowerDistance() : 1e9;
}

} // namespace

extern "C" {

occt_shape *occt_boundary_patch(const occt_shape *const *curves, int curve_count, const occt_shape *part,
                                const int *edge_indices, const int *face_indices, int edge_count, const double *points,
                                int point_count, const occt_shape *const *interior_curves, int interior_count,
                                int continuity, const occt_cancel *cancel, int *piece_order, int piece_capacity,
                                int *total_pieces, occt_history *history, occt_boundary_roles *roles, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        *history = occt_history{};
        *roles = occt_boundary_roles{};
        *total_pieces = 0;
        if (continuity < 0 || continuity > 1 || piece_capacity < kMostPieces || curve_count < 0 || edge_count < 0 ||
            point_count < 0 || interior_count < 0) {
            throw user_error("A patch needs 2 to 16 bounding pieces.");
        }
        std::vector<piece> pieces;
        for (int i = 0; i < curve_count; ++i) {
            if (!curves[i] || curves[i]->shape.IsNull() || curves[i]->shape.ShapeType() != TopAbs_WIRE) {
                throw user_error("This curve can't be used.");
            }
            for (const TopoDS_Edge &edge : edges_of(TopoDS::Wire(curves[i]->shape))) {
                pieces.push_back({edge, TopoDS_Face()});
            }
        }
        if (edge_count > 0) {
            if (!part || part->shape.IsNull()) {
                throw user_error("The picked edges need a part.");
            }
            const TopTools_IndexedMapOfShape part_edges = map_of(part->shape, TopAbs_EDGE);
            const TopTools_IndexedMapOfShape part_faces = map_of(part->shape, TopAbs_FACE);
            for (int i = 0; i < edge_count; ++i) {
                if (edge_indices[i] < 1 || edge_indices[i] > part_edges.Extent()) {
                    throw user_error("That edge no longer exists.");
                }
                piece item;
                item.edge = TopoDS::Edge(part_edges(edge_indices[i]));
                if (continuity >= 1 && face_indices[i] >= 1) {
                    if (face_indices[i] > part_faces.Extent()) {
                        throw user_error("That face no longer exists.");
                    }
                    item.support = TopoDS::Face(part_faces(face_indices[i]));
                }
                pieces.push_back(item);
            }
        }
        const int count = static_cast<int>(pieces.size());
        *total_pieces = count;
        if (count < kLeastPieces || count > kMostPieces) {
            throw user_error("A patch needs 2 to 16 bounding pieces.");
        }
        poll(cancel);

        // Chain the pieces into one closed loop.
        Handle(TopTools_HSequenceOfShape) input = new TopTools_HSequenceOfShape();
        for (const piece &item : pieces) {
            input->Append(item.edge);
        }
        Handle(TopTools_HSequenceOfShape) wires;
        ShapeAnalysis_FreeBounds::ConnectEdgesToWires(input, kJoinTolerance, Standard_False, wires);
        std::vector<std::vector<TopoDS_Edge>> loops;
        bool all_closed = true;
        for (int w = 1; !wires.IsNull() && w <= wires->Length(); ++w) {
            loops.push_back(edges_of(TopoDS::Wire(wires->Value(w))));
            all_closed = all_closed && is_closed_loop(loops.back());
        }
        if (loops.size() > 1 && all_closed) {
            throw user_error("The bounding pieces form more than one loop.");
        }
        if (loops.size() != 1 || !all_closed || static_cast<int>(loops[0].size()) != count) {
            throw user_error(gap_message(pieces));
        }
        // The loop's order, numbered from input piece 0.
        std::vector<int> loop_pieces;
        for (const TopoDS_Edge &edge : loops[0]) {
            const int found = piece_of(edge, pieces);
            if (found < 0 || std::find(loop_pieces.begin(), loop_pieces.end(), found) != loop_pieces.end()) {
                throw user_error(gap_message(pieces));
            }
            loop_pieces.push_back(found);
        }
        const std::size_t origin =
            static_cast<std::size_t>(std::find(loop_pieces.begin(), loop_pieces.end(), 0) - loop_pieces.begin());
        // It runs the way input piece 0 does: forwards when the loop holds that piece the way it was given.
        gp_Pnt given_start, given_end, loop_start, loop_end;
        ends_of(pieces[0].edge, given_start, given_end);
        ends_of(loops[0][origin], loop_start, loop_end);
        const bool forwards = given_start.Distance(loop_start) <= given_start.Distance(loop_end);
        const std::size_t size = loop_pieces.size();
        for (std::size_t k = 0; k < size; ++k) {
            piece_order[k] = loop_pieces[(origin + (forwards ? k : size - k)) % size];
        }
        poll(cancel);

        // Fill it.
        BRepFill_Filling fill(3, 15, 2, Standard_False, 1e-5, 1e-4, 1e-2, 0.1, 8, 9);
        for (const piece &item : pieces) {
            if (item.support.IsNull()) {
                fill.Add(item.edge, GeomAbs_C0, Standard_True);
            } else {
                fill.Add(item.edge, item.support, GeomAbs_G1, Standard_True);
            }
        }
        for (int i = 0; i < point_count; ++i) {
            fill.Add(gp_Pnt(points[3 * i], points[3 * i + 1], points[3 * i + 2]));
        }
        for (int i = 0; i < interior_count; ++i) {
            if (!interior_curves[i] || interior_curves[i]->shape.IsNull() ||
                interior_curves[i]->shape.ShapeType() != TopAbs_WIRE) {
                throw user_error("This curve can't be used.");
            }
            for (const TopoDS_Edge &edge : edges_of(TopoDS::Wire(interior_curves[i]->shape))) {
                fill.Add(edge, GeomAbs_C0, Standard_False);
            }
        }
        poll(cancel);
        fill.Build();
        poll(cancel);
        if (!fill.IsDone()) {
            throw user_error("The patch couldn't be made from these pieces.");
        }
        const TopoDS_Face face = fill.Face();
        if (face.IsNull() || !BRepCheck_Analyzer(face).IsValid()) {
            throw user_error("The patch couldn't be made from these pieces.");
        }
        const Handle(Geom_Surface) surface = BRep_Tool::Surface(face);

        // Every piece within 1e-4 mm and every point within 1e-3 mm.
        for (int i = 0; i < count; ++i) {
            poll(cancel);
            double worst = 0;
            for (int s = 0; s < kSamplesPerPiece; ++s) {
                worst = std::max(worst, distance_to_surface(at_fraction(pieces[i].edge, s / double(kSamplesPerPiece - 1)), surface));
            }
            if (worst > kPositionTolerance) {
                throw user_error("The patch misses piece " + std::to_string(i + 1) + " by " + number(worst) + " mm.");
            }
        }
        for (int i = 0; i < point_count; ++i) {
            const gp_Pnt p(points[3 * i], points[3 * i + 1], points[3 * i + 2]);
            if (distance_to_surface(p, surface) > kPointTolerance) {
                throw user_error("The patch can't pass through point " + std::to_string(i + 1) + ".");
            }
        }

        history_builder records(face);
        records.add(face, OCCT_FROM_START_CAP, 0, 0);
        records.move_into(history);
        boundary_table table(face);
        const TopTools_IndexedMapOfShape face_edges = map_of(face, TopAbs_EDGE);
        std::vector<int> assigned(static_cast<std::size_t>(count), 0);
        for (int e = 1; e <= face_edges.Extent(); ++e) {
            const TopoDS_Edge edge = TopoDS::Edge(face_edges(e));
            if (BRep_Tool::Degenerated(edge)) {
                continue;
            }
            const int found = piece_of(edge, pieces);
            if (found < 0) {
                continue;
            }
            for (int k = 0; k < count; ++k) {
                if (piece_order[k] == found && assigned[static_cast<std::size_t>(k)] == 0) {
                    assigned[static_cast<std::size_t>(k)] = 1;
                    table.set(edge, kBoundaryPiece, 0, k);
                }
            }
        }
        table.move_into(roles);
        return new occt_shape{face};
    });
}

} // extern "C"
