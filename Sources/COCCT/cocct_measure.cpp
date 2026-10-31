#include "cocct_internal.hpp"

#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Pnt.hxx>

#include <cmath>

using namespace cocct;

namespace {

TopoDS_Shape element(const occt_shape *shape, int kind, int index, const double point[3]) {
    if (kind == 0) {
        if (!std::isfinite(point[0]) || !std::isfinite(point[1]) || !std::isfinite(point[2])) {
            throw user_error("That point is not finite.");
        }
        return BRepBuilderAPI_MakeVertex(gp_Pnt(point[0], point[1], point[2])).Vertex();
    }
    if (kind != 1 && kind != 2) {
        throw user_error("These can't be measured.");
    }
    if (shape == nullptr) {
        throw user_error("These can't be measured.");
    }
    const TopTools_IndexedMapOfShape map = map_of(shape->shape, kind == 1 ? TopAbs_FACE : TopAbs_EDGE);
    if (index < 1 || index > map.Extent()) {
        throw user_error("That face or edge no longer exists.");
    }
    return map.FindKey(index);
}

} // namespace

extern "C" {

int occt_shortest_distance(const occt_shape *a, int kind_a, int index_a, const double point_a[3], const occt_shape *b, int kind_b,
                           int index_b, const double point_b[3], occt_shape_distance *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_shape_distance{};
        const TopoDS_Shape first = element(a, kind_a, index_a, point_a);
        const TopoDS_Shape second = element(b, kind_b, index_b, point_b);
        BRepExtrema_DistShapeShape extrema(first, second);
        if (!extrema.IsDone() || extrema.NbSolution() < 1) {
            throw user_error("These can't be measured.");
        }
        const gp_Pnt from = extrema.PointOnShape1(1);
        const gp_Pnt to = extrema.PointOnShape2(1);
        out->distance = extrema.Value();
        out->from[0] = from.X();
        out->from[1] = from.Y();
        out->from[2] = from.Z();
        out->to[0] = to.X();
        out->to[1] = to.Y();
        out->to[2] = to.Z();
        return 1;
    });
}

} // extern "C"
