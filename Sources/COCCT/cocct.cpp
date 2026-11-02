#include "cocct_internal.hpp"

#include <BRepCheck_Analyzer.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepGProp.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRep_Tool.hxx>
#include <Geom2d_Curve.hxx>
#include <Geom_Surface.hxx>
#include <GProp_GProps.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <Interface_Static.hxx>
#include <STEPControl_Writer.hxx>
#include <StlAPI_Writer.hxx>
#include <Standard_Failure.hxx>
#include <Precision.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Pnt2d.hxx>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <exception>

using namespace cocct;

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

int occt_is_valid(const occt_shape *shape) {
    return queried([&]() -> int { return BRepCheck_Analyzer(shape->shape).IsValid() ? 1 : 0; });
}

double occt_pcurve_domain_excursion(const occt_shape *shape) {
    return queried([&]() -> double {
        double worst = 0;
        for (TopExp_Explorer faces(shape->shape, TopAbs_FACE); faces.More(); faces.Next()) {
            const TopoDS_Face face = TopoDS::Face(faces.Current());
            const Handle(Geom_Surface) surface = BRep_Tool::Surface(face);
            double u1 = 0, u2 = 0, v1 = 0, v2 = 0;
            surface->Bounds(u1, u2, v1, v2);
            const bool check_u = !surface->IsUPeriodic() && !Precision::IsInfinite(u1) && !Precision::IsInfinite(u2);
            const bool check_v = !surface->IsVPeriodic() && !Precision::IsInfinite(v1) && !Precision::IsInfinite(v2);
            for (TopExp_Explorer edges(face, TopAbs_EDGE); edges.More(); edges.Next()) {
                double first = 0, last = 0;
                const Handle(Geom2d_Curve) pcurve = BRep_Tool::CurveOnSurface(TopoDS::Edge(edges.Current()), face, first, last);
                if (pcurve.IsNull()) {
                    continue;
                }
                for (int k = 0; k <= 64; ++k) {
                    const gp_Pnt2d uv = pcurve->Value(first + (last - first) * k / 64.0);
                    if (check_u) {
                        worst = std::max({worst, u1 - uv.X(), uv.X() - u2});
                    }
                    if (check_v) {
                        worst = std::max({worst, v1 - uv.Y(), uv.Y() - v2});
                    }
                }
            }
        }
        return worst;
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
        occt_initialize();
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
