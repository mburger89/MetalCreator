// Sewing faces into sheets and solids (NS-5, Task 3; rulings R5, R6, R15, R19).
//
// Every face of every input body is offered to `BRepBuilderAPI_Sewing` (on a copy of the face, so the inputs are never touched),
// except a face that coincides with one offered earlier: that one stays loose in the result (R6). Each closed shell of the result is
// made a solid; open shells and lone faces stay sheets. The history says which input face each result face came from and which input
// edges each result edge was made of.

#include "cocct_progress.hpp"
#include "cocct_sheet.hpp"
#include "cocct_solids.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepClass_FaceClassifier.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <GProp_GProps.hxx>
#include <TopAbs_State.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Iterator.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <memory>
#include <set>
#include <tuple>
#include <vector>

using namespace cocct;

namespace {

constexpr const char *kInvalidSewn = "Sewing made an invalid shape; try a smaller tolerance.";

/// One input face: where it came from, the copy sewing is given, and whether it duplicates an earlier face.
struct Source {
    int operand = 0;
    int index = 0; // 1-based in the operand's face map
    TopoDS_Face original;
    std::shared_ptr<BRepBuilderAPI_Copy> copier;
    TopoDS_Face copy;
    bool duplicate = false;
    Bnd_Box box;
    double area = 0;
};

double area_of(const TopoDS_Face &face) {
    GProp_GProps properties;
    BRepGProp::SurfaceProperties(face, properties);
    return std::abs(properties.Mass());
}

bool boxes_agree(const Bnd_Box &a, const Bnd_Box &b, double tolerance) {
    if (a.IsVoid() || b.IsVoid()) {
        return false;
    }
    double a_min[3], a_max[3], b_min[3], b_max[3];
    a.Get(a_min[0], a_min[1], a_min[2], a_max[0], a_max[1], a_max[2]);
    b.Get(b_min[0], b_min[1], b_min[2], b_max[0], b_max[1], b_max[2]);
    for (int i = 0; i < 3; ++i) {
        if (std::abs(a_min[i] - b_min[i]) > tolerance || std::abs(a_max[i] - b_max[i]) > tolerance) {
            return false;
        }
    }
    return true;
}

bool lies_on(const gp_Pnt &point, const TopoDS_Face &face, double tolerance) {
    BRepExtrema_DistShapeShape distance(BRepBuilderAPI_MakeVertex(point).Vertex(), face);
    return distance.IsDone() && distance.Value() <= tolerance;
}

/// Whether `face` lies on `earlier` within `tolerance`: a 5 x 5 grid over its parameter domain (the points the face holds) and each
/// edge's midpoint are all within `tolerance` of it.
bool lies_on_face(const TopoDS_Face &face, const TopoDS_Face &earlier, double tolerance) {
    double u0 = 0, u1 = 0, v0 = 0, v1 = 0;
    BRepTools::UVBounds(face, u0, u1, v0, v1);
    BRepAdaptor_Surface surface(face);
    if (std::isfinite(u0) && std::isfinite(u1) && std::isfinite(v0) && std::isfinite(v1)) {
        for (int i = 0; i < 5; ++i) {
            for (int j = 0; j < 5; ++j) {
                const double u = u0 + (u1 - u0) * (i + 0.5) / 5.0;
                const double v = v0 + (v1 - v0) * (j + 0.5) / 5.0;
                BRepClass_FaceClassifier classifier(face, gp_Pnt2d(u, v), 1e-9);
                if (classifier.State() != TopAbs_IN && classifier.State() != TopAbs_ON) {
                    continue;
                }
                if (!lies_on(surface.Value(u, v), earlier, tolerance)) {
                    return false;
                }
            }
        }
    }
    for (const TopoDS_Shape &edge_shape : [&] {
             std::vector<TopoDS_Shape> edges;
             const TopTools_IndexedMapOfShape map = map_of(face, TopAbs_EDGE);
             for (int i = 1; i <= map.Extent(); ++i) {
                 edges.push_back(map(i));
             }
             return edges;
         }()) {
        const TopoDS_Edge edge = TopoDS::Edge(edge_shape);
        if (BRep_Tool::Degenerated(edge)) {
            continue;
        }
        BRepAdaptor_Curve curve(edge);
        if (!lies_on(curve.Value(0.5 * (curve.FirstParameter() + curve.LastParameter())), earlier, tolerance)) {
            return false;
        }
    }
    return true;
}

/// Splits a sewn result into its solids, shells and lone faces.
void collect(const TopoDS_Shape &shape, std::vector<TopoDS_Shape> &parts) {
    if (shape.IsNull()) {
        return;
    }
    switch (shape.ShapeType()) {
    case TopAbs_COMPOUND:
    case TopAbs_COMPSOLID:
        for (TopoDS_Iterator it(shape); it.More(); it.Next()) {
            collect(it.Value(), parts);
        }
        break;
    case TopAbs_SOLID:
    case TopAbs_SHELL:
    case TopAbs_FACE:
        parts.push_back(shape);
        break;
    default:
        break;
    }
}

} // namespace

occt_shape *occt_sew(const occt_shape *const *bodies, int count, double tolerance, const occt_cancel *cancel,
                     occt_history *history, occt_edge_history *edges, int *solids, int *sheets, int *unclosable,
                     occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!bodies || count < 1) {
            throw user_error("Sew needs at least one surface.");
        }
        if (!(tolerance > 0) || !std::isfinite(tolerance)) {
            throw user_error("The tolerance must be greater than 0.");
        }
        poll(cancel);
        // The faces in input order, each copied; a face that coincides with an earlier offered one is a duplicate (R6).
        std::vector<Source> sources;
        std::vector<TopTools_IndexedMapOfShape> body_edges;
        for (int b = 0; b < count; ++b) {
            if (!bodies[b] || bodies[b]->shape.IsNull()) {
                throw user_error("This surface can't be used.");
            }
            body_edges.push_back(map_of(bodies[b]->shape, TopAbs_EDGE));
            const TopTools_IndexedMapOfShape faces = map_of(bodies[b]->shape, TopAbs_FACE);
            for (int f = 1; f <= faces.Extent(); ++f) {
                Source source;
                source.operand = b;
                source.index = f;
                source.original = TopoDS::Face(faces(f));
                source.copier = std::make_shared<BRepBuilderAPI_Copy>(source.original, Standard_False, Standard_False);
                source.copy = TopoDS::Face(source.copier->Shape());
                BRepBndLib::AddOptimal(source.original, source.box, Standard_False, Standard_False);
                source.area = area_of(source.original);
                sources.push_back(std::move(source));
            }
        }
        for (size_t i = 1; i < sources.size(); ++i) {
            poll(cancel);
            for (size_t k = 0; k < i && !sources[i].duplicate; ++k) {
                if (sources[k].duplicate || !boxes_agree(sources[i].box, sources[k].box, tolerance)) {
                    continue;
                }
                const double larger = std::max(sources[i].area, sources[k].area);
                if (std::abs(sources[i].area - sources[k].area) > 1e-6 * larger) {
                    continue;
                }
                sources[i].duplicate = lies_on_face(sources[i].original, sources[k].original, tolerance);
            }
        }
        BRepBuilderAPI_Sewing sewing(tolerance, Standard_True, Standard_True, Standard_True, Standard_False);
        int offered = 0;
        for (const Source &source : sources) {
            if (!source.duplicate) {
                sewing.Add(source.copy);
                ++offered;
            }
        }
        std::vector<TopoDS_Shape> parts;
        if (offered > 0) {
            sewing.Perform(progress_range(cancel));
            poll(cancel);
            collect(sewing.SewedShape(), parts);
        }
        int solid_count = 0;
        int sheet_count = 0;
        int unclosable_count = 0;
        std::vector<TopoDS_Shape> result_parts;
        for (const TopoDS_Shape &part : parts) {
            if (part.ShapeType() == TopAbs_SHELL && BRep_Tool::IsClosed(part)) {
                const TopoDS_Shape solid = solidify_closed_shell(part);
                if (!solid.IsNull()) {
                    ++solid_count;
                    result_parts.push_back(solid);
                    continue;
                }
                ++unclosable_count;
            } else if (part.ShapeType() == TopAbs_SOLID) {
                ++solid_count;
                result_parts.push_back(part);
                continue;
            }
            ++sheet_count;
            result_parts.push_back(part);
        }
        for (const Source &source : sources) {
            if (source.duplicate) {
                ++sheet_count;
                result_parts.push_back(source.copy);
            }
        }
        if (result_parts.empty()) {
            throw user_error(kInvalidSewn);
        }
        TopoDS_Shape result;
        if (result_parts.size() == 1) {
            result = result_parts[0];
        } else {
            BRep_Builder builder;
            TopoDS_Compound compound;
            builder.MakeCompound(compound);
            for (const TopoDS_Shape &part : result_parts) {
                builder.Add(compound, part);
            }
            result = compound;
        }
        poll(cancel);
        if (!BRepCheck_Analyzer(result).IsValid()) {
            throw user_error(kInvalidSewn);
        }
        // History: each input face's image, located in the result's faces, and each input edge's image in its edges.
        history_builder face_history(result);
        const TopTools_IndexedMapOfShape out_edges = map_of(result, TopAbs_EDGE);
        std::set<std::tuple<int, int, int>> edge_records;
        for (const Source &source : sources) {
            const TopoDS_Shape face_image = !source.duplicate && sewing.IsModified(source.copy) ? sewing.Modified(source.copy) : source.copy;
            face_history.add(face_image, OCCT_FROM_FACE, source.operand, source.index);
            const TopTools_IndexedMapOfShape face_edges = map_of(source.original, TopAbs_EDGE);
            for (int e = 1; e <= face_edges.Extent(); ++e) {
                const int original_index = body_edges[source.operand].FindIndex(face_edges(e));
                if (original_index <= 0) {
                    continue;
                }
                const TopoDS_Shape copied = source.copier->ModifiedShape(face_edges(e));
                if (copied.IsNull()) {
                    continue;
                }
                const TopoDS_Shape edge_image =
                    !source.duplicate && sewing.IsModifiedSubShape(copied) ? sewing.ModifiedSubShape(copied) : copied;
                for (TopExp_Explorer it(edge_image, TopAbs_EDGE); it.More(); it.Next()) {
                    const int out = out_edges.FindIndex(it.Current());
                    if (out > 0) {
                        edge_records.insert(std::make_tuple(out, source.operand, original_index));
                    }
                }
            }
        }
        std::vector<occt_edge_record> records;
        for (const auto &record : edge_records) {
            records.push_back(occt_edge_record{std::get<0>(record), std::get<1>(record), std::get<2>(record)});
        }
        face_history.move_into(history);
        edges->records = copy_out(records);
        edges->count = static_cast<int>(records.size());
        *solids = solid_count;
        *sheets = sheet_count;
        *unclosable = unclosable_count;
        return new occt_shape{result};
    });
}

occt_shape *occt_test_independent_copy(const occt_shape *shape, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        return new occt_shape{BRepBuilderAPI_Copy(shape->shape, Standard_True, Standard_False).Shape()};
    });
}

occt_shape *occt_test_loose_box_faces(double size, double move_top, int double_top, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        const TopoDS_Shape box = BRepPrimAPI_MakeBox(size, size, size).Shape();
        BRep_Builder builder;
        TopoDS_Compound compound;
        builder.MakeCompound(compound);
        TopoDS_Shape top;
        const TopTools_IndexedMapOfShape faces = map_of(box, TopAbs_FACE);
        for (int i = 1; i <= faces.Extent(); ++i) {
            TopoDS_Shape copy = BRepBuilderAPI_Copy(faces(i), Standard_True, Standard_False).Shape();
            Bnd_Box bounds;
            BRepBndLib::Add(copy, bounds);
            double x0, y0, z0, x1, y1, z1;
            bounds.Get(x0, y0, z0, x1, y1, z1);
            const bool is_top = std::abs(z0 - size) < 1e-5 && std::abs(z1 - size) < 1e-5;
            if (is_top && move_top != 0) {
                gp_Trsf move;
                move.SetTranslation(gp_Vec(0, 0, move_top));
                copy = BRepBuilderAPI_Transform(copy, move, Standard_True).Shape();
            }
            if (is_top) {
                top = copy;
            }
            builder.Add(compound, copy);
        }
        if (double_top != 0 && !top.IsNull()) {
            builder.Add(compound, BRepBuilderAPI_Copy(top, Standard_True, Standard_False).Shape());
        }
        return new occt_shape{compound};
    });
}
