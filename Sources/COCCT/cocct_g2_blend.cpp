// G-b: curvature-continuous fillets. OpenCascade makes the circular fillet; each strip face is then replaced by a
// B-spline surface skinned from quintic G2 Hermite sections between its two spring edges, and a corner where three strips
// end by one three-sided G2 patch (cocct_g2_triangle.hpp), else a G1 refill. This file is the operation: the entry
// points, the phases in order, the history and the final validity check; the phases are in cocct_g2_strip.cpp,
// cocct_g2_ends.cpp, cocct_g2_corner.cpp and cocct_g2_seam.cpp (declared in cocct_g2_blend_internal.hpp).
#include "cocct_g2_blend_internal.hpp"

#include <BRepBuilderAPI_Copy.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepLib.hxx>
#include <BRepTools_ReShape.hxx>
#include <Geom_Surface.hxx>
#include <TopoDS_Shell.hxx>

#include <algorithm>
#include <cmath>

using namespace cocct;
using namespace cocct::g2_blend;

static void apply_replacements(Run &r) {
    TopoDS_Shape &work = r.work;
    TopoDS_Shape &result = r.result;
    BRep_Builder &builder = r.builder;
    BRepTools_ReShape &reshape = r.reshape;
    std::vector<TopoDS_Face> &g2_new_faces = r.g2_new_faces;
    if (!g2_new_faces.empty()) {
        // The new quadrilaterals join the (still free) shell of the working copy before the replacements apply.
        TopExp_Explorer shells(work, TopAbs_SHELL);
        if (!shells.More()) {
            throw user_error(kStripMessage);
        }
        TopoDS_Shell shell = TopoDS::Shell(shells.Current());
        shell.Free(Standard_True); // a copy's shapes are frozen; this one is ours
        for (const TopoDS_Face &quad : g2_new_faces) {
            builder.Add(shell, quad);
        }
    }
    result = reshape.Apply(work);
    BRepLib::SameParameter(result, 1e-4);
    BRepLib::UpdateTolerances(result);
}

extern "C" {

double occt_g2_tangent_length(double chord, double turning_angle) {
    return g2::circular_tangent_length(chord, turning_angle);
}

int occt_g2_section_test(const double end0[9], double len0, const double end1[9], double len1, double t, double out[9]) {
    auto read = [](const double *e) {
        g2::EndCondition c;
        c.position = {e[0], e[1], e[2]};
        c.direction = {e[3], e[4], e[5]};
        c.acceleration = {e[6], e[7], e[8]};
        return c;
    };
    const auto poles = g2::quintic_poles(read(end0), len0, read(end1), len1);
    g2::Vec p, d1, d2;
    g2::evaluate(poles, t, p, d1, d2);
    for (int i = 0; i < 3; ++i) {
        out[i] = p[i];
        out[3 + i] = d1[i];
        out[6 + i] = d2[i];
    }
    return 1;
}

// One build, with corner patches tried or not. A failure leaves `report` as far as it got (g2_corners says whether a
// patch had been committed).
static occt_shape *fillet_g2_run(const occt_shape *shape, const int *edge_indices, int count, double radius, double weight,
                                 bool use_patches, occt_history *history, occt_g2_report *report, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        *report = occt_g2_report{};
        if (!shape || !edge_indices || count <= 0 || !std::isfinite(radius) || radius <= 0 || !std::isfinite(weight) || weight <= 0) {
            set_error(status, "a blend needs edges, a size and a tangency weight greater than 0");
            return nullptr;
        }
        const TopTools_IndexedMapOfShape input_edges = map_of(shape->shape, TopAbs_EDGE);
        BRepFilletAPI_MakeFillet algo(shape->shape);
        for (int i = 0; i < count; ++i) {
            if (edge_indices[i] < 1 || edge_indices[i] > input_edges.Extent()) {
                set_error(status, "edge index out of range");
                return nullptr;
            }
            algo.Add(radius, TopoDS::Edge(input_edges(edge_indices[i])));
        }
        algo.Build();
        if (!algo.IsDone()) {
            set_error(status, "the fillet could not be built for this radius");
            return nullptr;
        }
        const TopoDS_Shape g1 = algo.Shape();

        // History against the circular result; a face keeps its index through the copy and the replacements.
        history_builder records(g1);
        {
            const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
            for (int j = 1; j <= faces.Extent(); ++j) {
                const TopoDS_Shape &face = faces(j);
                if (algo.IsDeleted(face)) {
                    continue;
                }
                const TopTools_ListOfShape &modified = algo.Modified(face);
                if (modified.IsEmpty()) {
                    records.add(face, OCCT_FROM_FACE, 0, j);
                } else {
                    records.add_all(modified, OCCT_FROM_FACE, 0, j);
                }
            }
        }
        Run r;
        r.radius = radius;
        r.weight = weight;
        r.use_patches = use_patches;
        r.report = report;
        std::vector<int> &strip_indices = r.strip_indices, &corner_indices = r.corner_indices;
        const TopTools_IndexedMapOfShape g1_faces = map_of(g1, TopAbs_FACE);
        // OCCT propagates a fillet along the tangent chain of each selected edge, so the strips (and corners) are
        // those of every edge of every contour, not only of the selected ones. History keeps the selected edges' only.
        auto add_blend_faces = [&](const TopoDS_Edge &edge) {
            for (TopTools_ListOfShape::Iterator it(algo.Generated(edge)); it.More(); it.Next()) {
                strip_indices.push_back(g1_faces.FindIndex(it.Value()));
            }
            TopoDS_Vertex first, last;
            TopExp::Vertices(edge, first, last);
            for (const TopoDS_Vertex &vertex : {first, last}) {
                if (!vertex.IsNull()) {
                    for (TopTools_ListOfShape::Iterator it(algo.Generated(vertex)); it.More(); it.Next()) {
                        corner_indices.push_back(g1_faces.FindIndex(it.Value()));
                    }
                }
            }
        };
        for (int i = 0; i < count; ++i) {
            const TopoDS_Edge edge = TopoDS::Edge(input_edges(edge_indices[i]));
            records.add_all(algo.Generated(edge), OCCT_FROM_EDGE, 0, edge_indices[i]);
            TopoDS_Vertex first, last;
            TopExp::Vertices(edge, first, last);
            for (const TopoDS_Vertex &vertex : {first, last}) {
                if (!vertex.IsNull()) {
                    records.add_all(algo.Generated(vertex), OCCT_FROM_EDGE, 0, edge_indices[i]);
                }
            }
        }
        for (int contour = 1; contour <= algo.NbContours(); ++contour) {
            for (int j = 1; j <= algo.NbEdges(contour); ++j) {
                add_blend_faces(algo.Edge(contour, j));
            }
        }


        BRepBuilderAPI_Copy copy(g1, Standard_True, Standard_False);
        r.work = copy.Shape();
        r.faces = map_of(r.work, TopAbs_FACE);
        const TopTools_IndexedMapOfShape &faces = r.faces;
        if (faces.Extent() != g1_faces.Extent()) {
            throw user_error(kStripMessage);
        }
        std::sort(strip_indices.begin(), strip_indices.end());
        strip_indices.erase(std::unique(strip_indices.begin(), strip_indices.end()), strip_indices.end());
        std::sort(corner_indices.begin(), corner_indices.end());
        corner_indices.erase(std::unique(corner_indices.begin(), corner_indices.end()), corner_indices.end());
        std::vector<TopoDS_Face> blend_faces;
        for (int index : strip_indices) {
            blend_faces.push_back(TopoDS::Face(faces(index)));
        }
        for (int index : corner_indices) {
            blend_faces.push_back(TopoDS::Face(faces(index)));
        }
        TopExp::MapShapesAndAncestors(r.work, TopAbs_EDGE, TopAbs_FACE, r.edge_faces);

        r.result = r.work;
        for (int index : strip_indices) {
            r.strip_faces.push_back(TopoDS::Face(faces(index)));
        }
        for (int index : corner_indices) {
            r.corner_faces.push_back(TopoDS::Face(faces(index)));
        }
        for (const TopoDS_Face &face : r.strip_faces) {
            r.strips.push_back(classify(face, r.edge_faces, blend_faces, r.strip_faces));
        }
        r.corner_done.assign(r.corner_faces.size(), false);
        r.corner_patches.resize(r.corner_faces.size());

        agree_chain_tangents(r);
        // Every strip is built first (so that two strips meeting at a mitre can be cut by each other), then the
        // mitres, then each strip's end edges and face.
        build_strips(r);
        cut_mitres(r);
        place_corner_patches(r);
        rebuild_strip_faces(r);
        refill_corners(r);
        apply_replacements(r);
        judge_result(r);

        const std::vector<TopoDS_Face> &corner_faces = r.corner_faces;
        const std::vector<bool> &corner_done = r.corner_done;
        const std::vector<std::vector<TopoDS_Face>> &corner_patches = r.corner_patches;
        const TopoDS_Shape &result = r.result;
        BRepTools_ReShape &reshape = r.reshape;
        // History: the records name faces of the circular result; the final solid has its own face map (a corner that
        // became a patch is gone from the middle of it, the patch is at the end), so each record is renumbered through
        // what its face became: its replacement, or the patch faces of a corner.
        {
            const TopTools_IndexedMapOfShape final_faces = map_of(result, TopAbs_FACE);
            auto final_index = [&](const TopoDS_Shape &face) {
                int found = final_faces.FindIndex(face);
                if (found == 0) {
                    found = final_faces.FindIndex(reshape.Apply(face));
                }
                if (found == 0) {
                    // A rebuilt copy of the same face: it keeps its surface.
                    TopLoc_Location location;
                    const Handle(Geom_Surface) surface = BRep_Tool::Surface(TopoDS::Face(face), location);
                    int matches = 0;
                    for (int j = 1; j <= final_faces.Extent(); ++j) {
                        TopLoc_Location other_location;
                        if (BRep_Tool::Surface(TopoDS::Face(final_faces(j)), other_location) == surface &&
                            other_location == location) {
                            found = j;
                            ++matches;
                        }
                    }
                    if (matches != 1) {
                        found = 0; // split faces share a handle: guessing would give a record the wrong face
                    }
                }
                return found;
            };
            std::vector<std::vector<int>> final_of(g1_faces.Extent() + 1);
            for (int i = 1; i <= g1_faces.Extent(); ++i) {
                const TopoDS_Shape &original = faces(i);
                const TopoDS_Shape replacement = reshape.IsRecorded(original) ? reshape.Value(original) : original;
                if (replacement.IsNull()) {
                    for (std::size_t ci = 0; ci < corner_faces.size(); ++ci) {
                        if (corner_faces[ci].IsSame(original)) {
                            for (const TopoDS_Face &patch : corner_patches[ci]) {
                                const int found = final_index(patch);
                                if (found > 0) {
                                    final_of[i].push_back(found);
                                }
                            }
                        }
                    }
                } else {
                    const int found = final_index(replacement);
                    if (found > 0) {
                        final_of[i].push_back(found);
                    }
                }
            }
            std::vector<occt_history_record> renumbered;
            for (const occt_history_record &record : records.records()) {
                const std::vector<int> &now = final_of[record.out_face];
                if (now.empty()) {
                    throw user_error(kStripMessage); // a record's face can't be found: its tags must not be dropped
                }
                for (int index : now) {
                    renumbered.push_back(occt_history_record{index, record.kind, record.operand, record.index});
                }
            }
            records.set_records(std::move(renumbered));
        }
        // Never return a solid OCCT's checker rejects.
        {
            const BRepCheck_Analyzer analyzer(result);
            if (!analyzer.IsValid()) {
                // Name the culprit: a corner's face (a patch, or the refill) that fails on its own is the corner's
                // fault; otherwise a strip made the solid invalid and the largest-radius search should run.
                bool corner_invalid = false;
                for (std::size_t ci = 0; ci < corner_faces.size(); ++ci) {
                    if (corner_done[ci]) {
                        for (const TopoDS_Face &patch : corner_patches[ci]) {
                            corner_invalid = corner_invalid || !analyzer.IsValid(reshape.Apply(patch));
                        }
                    } else {
                        const TopoDS_Shape now = reshape.Apply(faces(corner_indices[ci]));
                        corner_invalid = corner_invalid || (!now.IsNull() && !analyzer.IsValid(now));
                    }
                }
                throw user_error(corner_invalid ? kCornerMessage : kStripMessage);
            }
        }
        records.move_into(history);
        return new occt_shape{result};
    });
}

occt_shape *occt_fillet_g2(const occt_shape *shape, const int *edge_indices, int count, double radius, double weight,
                           occt_history *history, occt_g2_report *report, occt_status *status) {
    occt_shape *made = fillet_g2_run(shape, edge_indices, count, radius, weight, true, history, report, status);
    if (made || report->g2_corners == 0) {
        return made;
    }
    // A patch was committed and something later failed (a strip face, the solid's validity): the same fillet with
    // every corner refilled G1, as the corners a patch is not accepted for are.
    return fillet_g2_run(shape, edge_indices, count, radius, weight, false, history, report, status);
}

} // extern "C"
