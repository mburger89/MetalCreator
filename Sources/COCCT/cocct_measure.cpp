#include "cocct_internal.hpp"

#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Shape.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Ax2.hxx>
#include <gp_Circ.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <cmath>

using namespace cocct;

namespace {

bool finite3(const double v[3]) { return std::isfinite(v[0]) && std::isfinite(v[1]) && std::isfinite(v[2]); }

TopoDS_Shape element(const occt_measure_operand &op) {
    const int kind = op.kind;
    if (kind == 0) {
        if (!finite3(op.point)) {
            throw user_error("That point is not finite.");
        }
        return BRepBuilderAPI_MakeVertex(gp_Pnt(op.point[0], op.point[1], op.point[2])).Vertex();
    }
    if (kind == 3) {
        if (op.points == nullptr || op.point_count < 2) {
            throw user_error("These can't be measured.");
        }
        BRepBuilderAPI_MakePolygon polygon;
        for (int i = 0; i < op.point_count; ++i) {
            const double *p = op.points + 3 * i;
            if (!finite3(p)) {
                throw user_error("That point is not finite.");
            }
            polygon.Add(gp_Pnt(p[0], p[1], p[2]));
        }
        if (!polygon.IsDone()) {
            throw user_error("These can't be measured.");
        }
        return polygon.Wire();
    }
    if (kind == 4) {
        if (!finite3(op.centre) || !finite3(op.axis) || !finite3(op.start) || !std::isfinite(op.radius) || !std::isfinite(op.sweep) ||
            op.radius <= 0 || op.sweep == 0) {
            throw user_error("These can't be measured.");
        }
        const gp_Vec axis_vec(op.axis[0], op.axis[1], op.axis[2]);
        const gp_Vec x_vec(op.start[0] - op.centre[0], op.start[1] - op.centre[1], op.start[2] - op.centre[2]);
        if (axis_vec.Magnitude() < 1e-12 || x_vec.Magnitude() < 1e-12 || axis_vec.CrossMagnitude(x_vec) < 1e-12 * axis_vec.Magnitude() * x_vec.Magnitude()) {
            throw user_error("These can't be measured.");
        }
        const double sign = op.sweep < 0 ? -1.0 : 1.0;
        const gp_Dir axis(sign * axis_vec.X(), sign * axis_vec.Y(), sign * axis_vec.Z());
        const gp_Dir xdir(x_vec.X(), x_vec.Y(), x_vec.Z());
        const gp_Ax2 frame(gp_Pnt(op.centre[0], op.centre[1], op.centre[2]), axis, xdir);
        BRepBuilderAPI_MakeEdge edge(gp_Circ(frame, op.radius), 0.0, std::fabs(op.sweep));
        if (!edge.IsDone()) {
            throw user_error("These can't be measured.");
        }
        return edge.Edge();
    }
    if (kind != 1 && kind != 2) {
        throw user_error("These can't be measured.");
    }
    if (op.shape == nullptr) {
        throw user_error("These can't be measured.");
    }
    const TopTools_IndexedMapOfShape map = map_of(op.shape->shape, kind == 1 ? TopAbs_FACE : TopAbs_EDGE);
    if (op.index < 1 || op.index > map.Extent()) {
        throw user_error("That face or edge no longer exists.");
    }
    return map.FindKey(op.index);
}

} // namespace

extern "C" {

int occt_shortest_distance(const occt_measure_operand *a, const occt_measure_operand *b, occt_shape_distance *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_shape_distance{};
        const TopoDS_Shape first = element(*a);
        const TopoDS_Shape second = element(*b);
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
