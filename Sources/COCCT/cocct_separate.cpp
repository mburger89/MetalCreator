// Taking a value apart into its closed solids and its open pieces (NURBS gaps, Task 2; ruling R3).
//
// The value's top-level parts are walked in the shape's own order, compounds opened: a solid whose shells are all closed is a solid,
// everything else (an open shell, a loose face, a closed shell that made no valid solid, a solid with an open shell) is an open piece.
// Each part is the very same sub-shape as in the input, so a part's faces and edges are found in the input's maps by `IsSame`.

#include "cocct_internal.hpp"

#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Iterator.hxx>

#include <cstdlib>
#include <vector>

using namespace cocct;

namespace {

constexpr const char *kNothing = "This value has no solids or surfaces to separate.";

/// Whether every shell of `solid` is closed.
bool solid_is_closed(const TopoDS_Shape &solid) {
    bool any = false;
    for (TopoDS_Iterator it(solid); it.More(); it.Next()) {
        if (it.Value().ShapeType() != TopAbs_SHELL) {
            continue;
        }
        any = true;
        if (!BRep_Tool::IsClosed(it.Value())) {
            return false;
        }
    }
    return any;
}

void collect_parts(const TopoDS_Shape &shape, std::vector<TopoDS_Shape> &parts, std::vector<int> &kinds) {
    switch (shape.ShapeType()) {
    case TopAbs_COMPOUND:
    case TopAbs_COMPSOLID:
        for (TopoDS_Iterator it(shape); it.More(); it.Next()) {
            collect_parts(it.Value(), parts, kinds);
        }
        break;
    case TopAbs_SOLID:
        parts.push_back(shape);
        kinds.push_back(solid_is_closed(shape) ? 1 : 0);
        break;
    case TopAbs_SHELL:
    case TopAbs_FACE:
        parts.push_back(shape);
        kinds.push_back(0);
        break;
    default:
        break;
    }
}

} // namespace

void occt_separate_result_free(occt_separate_result *result) {
    if (!result) {
        return;
    }
    std::free(result->kinds);
    std::free(result->face_piece);
    std::free(result->face_source);
    std::free(result->edge_piece);
    std::free(result->edge_source);
    *result = occt_separate_result{};
}

occt_shape *occt_separate(const occt_shape *value, occt_separate_result *out, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!value || value->shape.IsNull() || !out) {
            throw user_error("This value can't be used.");
        }
        *out = occt_separate_result{};
        std::vector<TopoDS_Shape> parts;
        std::vector<int> kinds;
        collect_parts(value->shape, parts, kinds);
        if (parts.empty()) {
            throw user_error(kNothing);
        }
        const TopTools_IndexedMapOfShape input_faces = map_of(value->shape, TopAbs_FACE);
        const TopTools_IndexedMapOfShape input_edges = map_of(value->shape, TopAbs_EDGE);
        // Open parts that share an edge (the same edge object, `IsSame`) are one connected piece; edges that merely coincide in space
        // stay apart (joining those is Sew's job).
        const size_t count = parts.size();
        std::vector<size_t> root(count);
        for (size_t i = 0; i < count; ++i) {
            root[i] = i;
        }
        const auto find = [&root](size_t i) {
            while (root[i] != i) {
                root[i] = root[root[i]];
                i = root[i];
            }
            return i;
        };
        std::vector<int> owner(static_cast<size_t>(input_edges.Extent()) + 1, -1);
        for (size_t p = 0; p < count; ++p) {
            if (kinds[p] != 0) {
                continue;
            }
            const TopTools_IndexedMapOfShape part_edges = map_of(parts[p], TopAbs_EDGE);
            for (int e = 1; e <= part_edges.Extent(); ++e) {
                const int index = input_edges.FindIndex(part_edges(e));
                if (index < 1) {
                    continue;
                }
                if (owner[index] < 0) {
                    owner[index] = static_cast<int>(p);
                } else {
                    root[find(p)] = find(static_cast<size_t>(owner[index]));
                }
            }
        }
        // Pieces in the order of their first part; a group of several open parts is one compound.
        std::vector<TopoDS_Shape> pieces;
        std::vector<int> piece_kinds;
        std::vector<bool> placed(count, false);
        for (size_t p = 0; p < count; ++p) {
            if (placed[p]) {
                continue;
            }
            if (kinds[p] != 0) {
                placed[p] = true;
                pieces.push_back(parts[p]);
                piece_kinds.push_back(1);
                continue;
            }
            std::vector<TopoDS_Shape> members;
            for (size_t q = p; q < count; ++q) {
                if (!placed[q] && kinds[q] == 0 && find(q) == find(p)) {
                    placed[q] = true;
                    members.push_back(parts[q]);
                }
            }
            if (members.size() == 1) {
                pieces.push_back(members[0]);
            } else {
                BRep_Builder group_builder;
                TopoDS_Compound group;
                group_builder.MakeCompound(group);
                for (const TopoDS_Shape &member : members) {
                    group_builder.Add(group, member);
                }
                pieces.push_back(group);
            }
            piece_kinds.push_back(0);
        }
        std::vector<int> face_piece;
        std::vector<int> face_source;
        std::vector<int> edge_piece;
        std::vector<int> edge_source;
        BRep_Builder builder;
        TopoDS_Compound compound;
        builder.MakeCompound(compound);
        for (size_t p = 0; p < pieces.size(); ++p) {
            builder.Add(compound, pieces[p]);
            const TopTools_IndexedMapOfShape faces = map_of(pieces[p], TopAbs_FACE);
            for (int f = 1; f <= faces.Extent(); ++f) {
                face_piece.push_back(static_cast<int>(p));
                face_source.push_back(input_faces.FindIndex(faces(f)));
            }
            const TopTools_IndexedMapOfShape edges = map_of(pieces[p], TopAbs_EDGE);
            for (int e = 1; e <= edges.Extent(); ++e) {
                edge_piece.push_back(static_cast<int>(p));
                edge_source.push_back(input_edges.FindIndex(edges(e)));
            }
        }
        out->kinds = copy_out(piece_kinds);
        out->piece_count = static_cast<int>(pieces.size());
        out->face_piece = copy_out(face_piece);
        out->face_source = copy_out(face_source);
        out->face_count = static_cast<int>(face_piece.size());
        out->edge_piece = copy_out(edge_piece);
        out->edge_source = copy_out(edge_source);
        out->edge_count = static_cast<int>(edge_piece.size());
        return new occt_shape{compound};
    });
}
