#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBndLib.hxx>
#include <BRepGProp.hxx>
#include <BRep_Tool.hxx>
#include <Bnd_Box.hxx>
#include <ChFi3d.hxx>
#include <GProp_GProps.hxx>
#include <Interface_Static.hxx>
#include <Message.hxx>
#include <Message_Messenger.hxx>
#include <Message_PrinterOStream.hxx>
#include <Precision.hxx>
#include <STEPControl_Controller.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>

#include <mutex>

using namespace cocct;

namespace {

template <typename XYZLike>
void set3(double (&out)[3], const XYZLike &value) {
    out[0] = value.X();
    out[1] = value.Y();
    out[2] = value.Z();
}

void describe_face(const TopoDS_Face &face, occt_face_info &info) {
    BRepAdaptor_Surface surface(face, Standard_True);
    switch (surface.GetType()) {
    case GeomAbs_Plane: info.kind = 0; break;
    case GeomAbs_Cylinder: info.kind = 1; break;
    case GeomAbs_Cone: info.kind = 2; break;
    case GeomAbs_Sphere: info.kind = 3; break;
    case GeomAbs_Torus: info.kind = 4; break;
    case GeomAbs_BSplineSurface: info.kind = 5; break;
    default: info.kind = 6; break;
    }
    if (info.kind == 0) {
        // Outward normal from the surface derivatives, flipped for reversed faces.
        const double u = 0.5 * (surface.FirstUParameter() + surface.LastUParameter());
        const double v = 0.5 * (surface.FirstVParameter() + surface.LastVParameter());
        gp_Pnt point;
        gp_Vec du, dv;
        surface.D1(u, v, point, du, dv);
        gp_Vec normal = du.Crossed(dv);
        if (normal.Magnitude() > 1e-12) {
            if (face.Orientation() == TopAbs_REVERSED) {
                normal.Reverse();
            }
            normal.Normalize();
            set3(info.normal, normal);
            info.has_normal = 1;
        }
    } else if (info.kind == 1) {
        set3(info.normal, surface.Cylinder().Axis().Direction());
        info.has_normal = 1;
    } else if (info.kind == 2) {
        set3(info.normal, surface.Cone().Axis().Direction());
        info.has_normal = 1;
    } else if (info.kind == 4) {
        set3(info.normal, surface.Torus().Axis().Direction());
        info.has_normal = 1;
    }
    GProp_GProps properties;
    BRepGProp::SurfaceProperties(face, properties);
    info.area = properties.Mass();
    set3(info.centroid, properties.CentreOfMass());
}

int convexity_of(const TopoDS_Edge &edge, const TopoDS_Face &a, const TopoDS_Face &b) {
    try {
        switch (ChFi3d::DefineConnectType(edge, a, b, Precision::Angular(), Standard_False)) {
        case ChFiDS_Convex: return 0;
        case ChFiDS_Concave: return 1;
        case ChFiDS_Tangential: return 2;
        default: return 3;
        }
    } catch (...) {
        return 3;
    }
}

void describe_edge(const TopoDS_Edge &edge, const TopTools_IndexedMapOfShape &faces,
                   const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces, occt_edge_info &info) {
    info.convexity = 3;
    if (!BRep_Tool::Degenerated(edge)) {
        BRepAdaptor_Curve curve(edge);
        switch (curve.GetType()) {
        case GeomAbs_Line:
            info.kind = 0;
            set3(info.direction, curve.Line().Direction());
            info.has_direction = 1;
            break;
        case GeomAbs_Circle:
            info.kind = 1;
            set3(info.direction, curve.Circle().Axis().Direction());
            info.has_direction = 1;
            break;
        case GeomAbs_Ellipse:
            info.kind = 2;
            set3(info.direction, curve.Ellipse().Axis().Direction());
            info.has_direction = 1;
            break;
        case GeomAbs_BSplineCurve: info.kind = 3; break;
        default: info.kind = 4; break;
        }
        GProp_GProps properties;
        BRepGProp::LinearProperties(edge, properties);
        info.length = properties.Mass();
        set3(info.midpoint, curve.Value(0.5 * (curve.FirstParameter() + curve.LastParameter())));
    } else {
        info.kind = 4;
    }
    const std::vector<TopoDS_Face> adjacent = distinct_faces(edge, edge_faces);
    if (adjacent.size() == 1) {
        info.face_a = info.face_b = faces.FindIndex(adjacent[0]);
        info.convexity = 2;
    } else if (adjacent.size() >= 2) {
        info.face_a = faces.FindIndex(adjacent[0]);
        info.face_b = faces.FindIndex(adjacent[1]);
        info.convexity = convexity_of(edge, adjacent[0], adjacent[1]);
    }
}

} // namespace

extern "C" {

void occt_initialize(void) {
    static std::once_flag once;
    std::call_once(once, [] {
        try {
            STEPControl_Controller::Init();
            Interface_Static::SetCVal("write.step.unit", "MM");
            Message::DefaultMessenger()->RemovePrinters(STANDARD_TYPE(Message_PrinterOStream));
        } catch (...) {
            // Best effort: OCCT stays usable, only noisier.
        }
    });
}

void occt_history_free(occt_history *history) {
    if (history) {
        std::free(history->records);
        history->records = nullptr;
        history->count = 0;
    }
}

int occt_read_properties(const occt_shape *shape, occt_properties *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_properties{};
        GProp_GProps volume;
        BRepGProp::VolumeProperties(shape->shape, volume);
        GProp_GProps surface;
        BRepGProp::SurfaceProperties(shape->shape, surface);
        Bnd_Box box;
        BRepBndLib::AddOptimal(shape->shape, box, Standard_False, Standard_False);
        if (box.IsVoid()) {
            set_error(status, "the shape is empty");
            return 0;
        }
        out->volume = volume.Mass();
        out->area = surface.Mass();
        const gp_Pnt centre = volume.CentreOfMass();
        out->centroid[0] = centre.X();
        out->centroid[1] = centre.Y();
        out->centroid[2] = centre.Z();
        box.Get(out->min[0], out->min[1], out->min[2], out->max[0], out->max[1], out->max[2]);
        return 1;
    });
}

int occt_read_bounds(const occt_shape *shape, double min[3], double max[3], occt_status *status) {
    return guarded(status, [&]() -> int {
        if (!shape || !min || !max) {
            set_error(status, "the shape is empty");
            return 0;
        }
        Bnd_Box box;
        BRepBndLib::AddOptimal(shape->shape, box, Standard_False, Standard_False);
        if (box.IsVoid()) {
            set_error(status, "the shape is empty");
            return 0;
        }
        box.Get(min[0], min[1], min[2], max[0], max[1], max[2]);
        return 1;
    });
}

int occt_read_topology(const occt_shape *shape, occt_topology *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_topology{};
        const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
        const TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(shape->shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);

        std::vector<occt_face_info> face_info(faces.Extent());
        for (int i = 1; i <= faces.Extent(); ++i) {
            describe_face(TopoDS::Face(faces(i)), face_info[i - 1]);
        }
        std::vector<occt_edge_info> edge_info(edges.Extent());
        for (int i = 1; i <= edges.Extent(); ++i) {
            describe_edge(TopoDS::Edge(edges(i)), faces, edge_faces, edge_info[i - 1]);
        }
        out->faces = copy_out(face_info);
        out->edges = copy_out(edge_info);
        out->face_count = faces.Extent();
        out->edge_count = edges.Extent();
        return 1;
    });
}

void occt_topology_free(occt_topology *topology) {
    if (topology) {
        std::free(topology->faces);
        std::free(topology->edges);
        *topology = occt_topology{};
    }
}

} // extern "C"
