#include "cocct_internal.hpp"

#include <BRepAlgoAPI_BooleanOperation.hxx>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepBuilderAPI_MakeShape.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <gp_Ax1.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>

#include <cmath>
#include <memory>

using namespace cocct;

namespace {

/// Records where each face of `input` ended up: itself if kept, its pieces if modified,
/// nothing if deleted.
void add_face_history(history_builder &records, BRepBuilderAPI_MakeShape &algo, const TopoDS_Shape &input, int operand) {
    const TopTools_IndexedMapOfShape faces = map_of(input, TopAbs_FACE);
    for (int j = 1; j <= faces.Extent(); ++j) {
        const TopoDS_Shape &face = faces(j);
        if (algo.IsDeleted(face)) {
            continue;
        }
        const TopTools_ListOfShape &modified = algo.Modified(face);
        if (modified.IsEmpty()) {
            records.add(face, OCCT_FROM_FACE, operand, j);
        } else {
            records.add_all(modified, OCCT_FROM_FACE, operand, j);
        }
    }
}

bool has_solid(const TopoDS_Shape &shape) {
    return TopExp_Explorer(shape, TopAbs_SOLID).More();
}

} // namespace

extern "C" {

occt_shape *occt_boolean(int op, const occt_shape *a, const occt_shape *const *tools, int tool_count,
                         occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        if (!a || !tools || tool_count <= 0) {
            set_error(status, "a boolean needs a solid and at least one tool");
            return nullptr;
        }
        std::unique_ptr<BRepAlgoAPI_BooleanOperation> algo;
        switch (op) {
        case 0: algo = std::make_unique<BRepAlgoAPI_Fuse>(); break;
        case 1: algo = std::make_unique<BRepAlgoAPI_Cut>(); break;
        case 2: algo = std::make_unique<BRepAlgoAPI_Common>(); break;
        default: set_error(status, "unknown boolean operation"); return nullptr;
        }
        TopTools_ListOfShape arguments;
        arguments.Append(a->shape);
        TopTools_ListOfShape toolList;
        for (int i = 0; i < tool_count; ++i) {
            toolList.Append(tools[i]->shape);
        }
        algo->SetArguments(arguments);
        algo->SetTools(toolList);
        algo->Build();
        if (!algo->IsDone() || algo->HasErrors()) {
            set_error(status, "the boolean could not be computed");
            return nullptr;
        }
        if (op != 2) {
            algo->SimplifyResult();
        }
        const TopoDS_Shape result = algo->Shape();
        if (result.IsNull() || !has_solid(result)) {
            set_error(status, "the result is empty");
            return nullptr;
        }
        history_builder records(result);
        add_face_history(records, *algo, a->shape, 0);
        for (int i = 0; i < tool_count; ++i) {
            add_face_history(records, *algo, tools[i]->shape, i + 1);
        }
        records.move_into(history);
        return new occt_shape{result};
    });
}

occt_shape *occt_transform(const occt_shape *shape, const double translation[3], int has_rotation,
                           const double axis_origin[3], const double axis_direction[3], double angle,
                           occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        gp_Trsf rotation;
        if (has_rotation) {
            rotation.SetRotation(gp_Ax1(gp_Pnt(axis_origin[0], axis_origin[1], axis_origin[2]),
                                        gp_Dir(axis_direction[0], axis_direction[1], axis_direction[2])),
                                 angle);
        }
        gp_Trsf move;
        move.SetTranslation(gp_Vec(translation[0], translation[1], translation[2]));
        const gp_Trsf total = move.Multiplied(rotation); // rotation first, then translation
        BRepBuilderAPI_Transform transform(shape->shape, total, Standard_True);
        if (!transform.IsDone()) {
            set_error(status, "the transform could not be applied");
            return nullptr;
        }
        const TopoDS_Shape result = transform.Shape();
        history_builder records(result);
        add_face_history(records, transform, shape->shape, 0);
        records.move_into(history);
        return new occt_shape{result};
    });
}

} // extern "C"
