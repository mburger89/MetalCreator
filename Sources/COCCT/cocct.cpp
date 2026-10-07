#include "cocct.h"

#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepGProp.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <GProp_GProps.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <Interface_Static.hxx>
#include <STEPControl_Writer.hxx>
#include <StlAPI_Writer.hxx>
#include <Standard_Failure.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Shape.hxx>

#include <cmath>
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

/// Runs a query, returning -1 if anything throws. No exception may cross into Swift.
template <typename Body>
auto queried(Body body) -> decltype(body()) {
    try {
        return body();
    } catch (...) {
        return static_cast<decltype(body())>(-1);
    }
}

} // namespace

extern "C" {

occt_shape *occt_make_box(double dx, double dy, double dz, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!(std::isfinite(dx) && std::isfinite(dy) && std::isfinite(dz) && dx > 0 && dy > 0 && dz > 0)) {
            set_error(status, "box sides must be greater than 0");
            return nullptr;
        }
        BRepPrimAPI_MakeBox maker(dx, dy, dz);
        return new occt_shape{maker.Shape()};
    });
}

void occt_shape_free(occt_shape *shape) { delete shape; }

double occt_volume(const occt_shape *shape) {
    return queried([&]() -> double {
        GProp_GProps props;
        BRepGProp::VolumeProperties(shape->shape, props);
        return props.Mass();
    });
}

int occt_face_count(const occt_shape *shape) {
    return queried([&]() -> int { return map_of(shape->shape, TopAbs_FACE).Extent(); });
}

int occt_edge_count(const occt_shape *shape) {
    return queried([&]() -> int { return map_of(shape->shape, TopAbs_EDGE).Extent(); });
}

double occt_edge_length(const occt_shape *shape, int index) {
    return queried([&]() -> double {
        TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        if (index < 1 || index > edges.Extent()) {
            return -1;
        }
        GProp_GProps props;
        BRepGProp::LinearProperties(edges(index), props);
        return props.Mass();
    });
}

occt_shape *occt_fillet_edge(const occt_shape *shape, int edge_index, double radius, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!(std::isfinite(radius) && radius > 0)) {
            set_error(status, "fillet radius must be greater than 0");
            return nullptr;
        }
        TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        if (edge_index < 1 || edge_index > edges.Extent()) {
            set_error(status, "edge index out of range");
            return nullptr;
        }
        BRepFilletAPI_MakeFillet fillet(shape->shape);
        fillet.Add(radius, TopoDS::Edge(edges(edge_index)));
        fillet.Build();
        if (!fillet.IsDone()) {
            set_error(status, "fillet could not be built for this radius");
            return nullptr;
        }
        return new occt_shape{fillet.Shape()};
    });
}

int occt_write_step(const occt_shape *shape, const char *path, occt_status *status) {
    return guarded(status, [&]() -> int {
        if (!path) {
            set_error(status, "no output path");
            return 0;
        }
        STEPControl_Writer writer;
        Interface_Static::SetCVal("write.step.unit", "MM");
        if (writer.Transfer(shape->shape, STEPControl_AsIs) != IFSelect_RetDone) {
            set_error(status, "STEP transfer failed");
            return 0;
        }
        if (writer.Write(path) != IFSelect_RetDone) {
            set_error(status, "STEP file could not be written");
            return 0;
        }
        return 1;
    });
}

int occt_write_stl(const occt_shape *shape, const char *path, double linear_deflection, occt_status *status) {
    return guarded(status, [&]() -> int {
        if (!path) {
            set_error(status, "no output path");
            return 0;
        }
        if (!(std::isfinite(linear_deflection) && linear_deflection > 0)) {
            set_error(status, "STL deflection must be greater than 0");
            return 0;
        }
        BRepMesh_IncrementalMesh mesher(shape->shape, linear_deflection);
        StlAPI_Writer writer;
        if (!writer.Write(shape->shape, path)) {
            set_error(status, "STL file could not be written");
            return 0;
        }
        return 1;
    });
}

} // extern "C"
