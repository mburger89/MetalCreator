#include "cocct_internal.hpp"

#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <GProp_GProps.hxx>
#include <Standard_DomainError.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <gp_Ax2.hxx>
#include <gp_Circ.hxx>
#include <gp_Vec.hxx>

#include <cmath>

using namespace cocct;

namespace {

/// A profile turned into a planar face, with its edges in segment order.
struct built_profile {
    TopoDS_Face face;
    std::vector<TopoDS_Edge> edges;
};

gp_Ax2 frame_of(const occt_plane &plane) {
    return gp_Ax2(gp_Pnt(plane.origin[0], plane.origin[1], plane.origin[2]),
                  gp_Dir(plane.normal[0], plane.normal[1], plane.normal[2]),
                  gp_Dir(plane.x_axis[0], plane.x_axis[1], plane.x_axis[2]));
}

gp_Pnt point_on(const gp_Ax2 &frame, double x, double y) {
    return gp_Pnt(frame.Location().XYZ() + frame.XDirection().XYZ() * x + frame.YDirection().XYZ() * y);
}

built_profile build_profile(const occt_profile &profile) {
    if (!profile.segments || profile.segment_count <= 0) {
        throw Standard_DomainError("the profile has no segments");
    }
    const gp_Ax2 frame = frame_of(profile.plane);
    BRepBuilderAPI_MakeWire wire;
    built_profile result;
    for (int k = 0; k < profile.segment_count; ++k) {
        const occt_segment &segment = profile.segments[k];
        TopoDS_Edge edge;
        if (segment.kind == 0) {
            const gp_Pnt a = point_on(frame, segment.x0, segment.y0);
            const gp_Pnt b = point_on(frame, segment.x1, segment.y1);
            if (a.Distance(b) <= 1e-9) {
                throw Standard_DomainError("a line in the profile has zero length");
            }
            BRepBuilderAPI_MakeEdge make(a, b);
            if (!make.IsDone()) {
                throw Standard_DomainError("a line in the profile could not be built");
            }
            edge = make.Edge();
        } else {
            if (!(segment.radius > 1e-9) || !std::isfinite(segment.radius)) {
                throw Standard_DomainError("an arc in the profile has no radius");
            }
            const gp_Ax2 axes(point_on(frame, segment.cx, segment.cy), frame.Direction(), frame.XDirection());
            BRepBuilderAPI_MakeEdge make(gp_Circ(axes, segment.radius), segment.start, segment.end);
            if (!make.IsDone()) {
                throw Standard_DomainError("an arc in the profile could not be built");
            }
            edge = make.Edge();
        }
        wire.Add(edge);
        if (!wire.IsDone()) {
            throw Standard_DomainError("the profile segments do not connect");
        }
        result.edges.push_back(wire.Edge());
    }
    BRepBuilderAPI_MakeFace face(wire.Wire(), Standard_True);
    if (!face.IsDone()) {
        throw Standard_DomainError("the profile is not a closed, flat loop");
    }
    result.face = face.Face();
    return result;
}

/// OCCT may return an inside-out solid depending on profile winding; flip it if so.
TopoDS_Shape oriented(const TopoDS_Shape &shape) {
    GProp_GProps properties;
    BRepGProp::VolumeProperties(shape, properties);
    return properties.Mass() < 0 ? shape.Reversed() : shape;
}

} // namespace

extern "C" {

occt_shape *occt_extrude(const occt_profile *profile, double distance, occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        if (!profile || !std::isfinite(distance) || distance <= 0) {
            set_error(status, "extrude distance must be greater than 0");
            return nullptr;
        }
        const built_profile built = build_profile(*profile);
        const gp_Vec vector(gp_Dir(profile->plane.normal[0], profile->plane.normal[1], profile->plane.normal[2]));
        BRepPrimAPI_MakePrism prism(built.face, vector * distance);
        prism.Build();
        if (!prism.IsDone()) {
            set_error(status, "the extrusion could not be built");
            return nullptr;
        }
        const TopoDS_Shape solid = oriented(prism.Shape());
        history_builder records(solid);
        records.add(prism.FirstShape(), OCCT_FROM_START_CAP, 0, 0);
        records.add(prism.LastShape(), OCCT_FROM_END_CAP, 0, 0);
        for (int k = 0; k < static_cast<int>(built.edges.size()); ++k) {
            records.add_all(prism.Generated(built.edges[k]), OCCT_FROM_SEGMENT, 0, k);
        }
        records.move_into(history);
        return new occt_shape{solid};
    });
}

} // extern "C"
