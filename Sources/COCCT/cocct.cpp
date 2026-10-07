#include "cocct.h"

#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <GProp_GProps.hxx>
#include <Standard_Failure.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Shape.hxx>

#include <cstring>
#include <exception>

struct occt_shape {
    TopoDS_Shape shape;
};

namespace {

void set_ok(occt_status *status) {
    if (status) {
        status->ok = 1;
        status->message[0] = '\0';
    }
}

void set_error(occt_status *status, const char *message) {
    if (status) {
        status->ok = 0;
        std::strncpy(status->message, message ? message : "unknown OCCT error", sizeof(status->message) - 1);
        status->message[sizeof(status->message) - 1] = '\0';
    }
}

/// Runs `body`, converting every C++ exception into an error status. No exception may
/// cross into Swift.
template <typename Body>
auto guarded(occt_status *status, Body body) -> decltype(body()) {
    try {
        set_ok(status);
        return body();
    } catch (const Standard_Failure &failure) {
        const char *message = failure.GetMessageString();
        set_error(status, (message && *message) ? message : failure.DynamicType()->Name());
    } catch (const std::exception &error) {
        set_error(status, error.what());
    } catch (...) {
        set_error(status, "unknown OCCT exception");
    }
    return decltype(body()){};
}

TopTools_IndexedMapOfShape map_of(const TopoDS_Shape &shape, TopAbs_ShapeEnum kind) {
    TopTools_IndexedMapOfShape map;
    TopExp::MapShapes(shape, kind, map);
    return map;
}

} // namespace

extern "C" {

occt_shape *occt_make_box(double dx, double dy, double dz, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!(dx > 0 && dy > 0 && dz > 0)) {
            set_error(status, "box sides must be greater than 0");
            return nullptr;
        }
        BRepPrimAPI_MakeBox maker(dx, dy, dz);
        return new occt_shape{maker.Shape()};
    });
}

void occt_shape_free(occt_shape *shape) { delete shape; }

double occt_volume(const occt_shape *shape) {
    GProp_GProps props;
    BRepGProp::VolumeProperties(shape->shape, props);
    return props.Mass();
}

int occt_face_count(const occt_shape *shape) { return map_of(shape->shape, TopAbs_FACE).Extent(); }

int occt_edge_count(const occt_shape *shape) { return map_of(shape->shape, TopAbs_EDGE).Extent(); }

double occt_edge_length(const occt_shape *shape, int index) {
    TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
    if (index < 1 || index > edges.Extent()) {
        return -1;
    }
    GProp_GProps props;
    BRepGProp::LinearProperties(edges(index), props);
    return props.Mass();
}

} // extern "C"
