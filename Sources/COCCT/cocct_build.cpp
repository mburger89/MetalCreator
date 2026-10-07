#include "cocct_internal.hpp"

#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepGProp.hxx>
#include <BRepLib.hxx>
#include <BRep_Builder.hxx>
#include <BRepOffsetAPI_ThruSections.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepSweep_Revol.hxx>
#include <BRepTools.hxx>
#include <GProp_GProps.hxx>
#include <Standard_DomainError.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Solid.hxx>
#include <gp_Ax2.hxx>
#include <gp_Ax1.hxx>
#include <gp_Circ.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <stdexcept>

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
        throw user_error("the profile has no segments");
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
                throw user_error("a line in the profile has zero length");
            }
            BRepBuilderAPI_MakeEdge make(a, b);
            if (!make.IsDone()) {
                throw user_error("a line in the profile could not be built");
            }
            edge = make.Edge();
        } else {
            if (segment.kind != 1) {
                throw user_error("unknown profile segment kind");
            }
            if (!std::isfinite(segment.start) || !std::isfinite(segment.end)) {
                throw user_error("an arc in the profile has a non-finite angle");
            }
            if (!(segment.end - segment.start > 1e-12)) {
                throw user_error("an arc in the profile has no sweep");
            }
            if (!(segment.radius > 1e-9) || !std::isfinite(segment.radius)) {
                throw user_error("an arc in the profile has no radius");
            }
            if (!std::isfinite(segment.cx) || !std::isfinite(segment.cy)) {
                throw user_error("an arc in the profile has an invalid centre");
            }
            const gp_Ax2 axes(point_on(frame, segment.cx, segment.cy), frame.Direction(), frame.XDirection());
            BRepBuilderAPI_MakeEdge make(gp_Circ(axes, segment.radius), segment.start, segment.end);
            if (!make.IsDone()) {
                throw user_error("an arc in the profile could not be built");
            }
            edge = make.Edge();
        }
        wire.Add(edge);
        if (!wire.IsDone()) {
            throw user_error("the profile segments do not connect");
        }
        result.edges.push_back(wire.Edge());
    }
    BRepBuilderAPI_MakeFace face(wire.Wire(), Standard_True);
    if (!face.IsDone()) {
        throw user_error("the profile is not a closed, flat loop");
    }
    result.face = face.Face();
    return result;
}

double volume_of(const TopoDS_Shape &shape) {
    GProp_GProps properties;
    BRepGProp::VolumeProperties(shape, properties);
    return properties.Mass();
}

/// Orients one solid so its shell bounds matter (OCCT may build it inside out depending on
/// profile winding). Throws if it still has negative volume.
TopoDS_Solid oriented_solid(TopoDS_Solid solid) {
    BRepLib::OrientClosedSolid(solid);
    if (volume_of(solid) < 0) {
        throw user_error("the profile produced an inside-out solid");
    }
    return solid;
}

/// Orients every solid in `shape` (a solid, or a compound of solids). Face identities are kept,
/// so history recorded against the builder still matches the result.
TopoDS_Shape oriented(const TopoDS_Shape &shape) {
    if (shape.ShapeType() == TopAbs_SOLID) {
        return oriented_solid(TopoDS::Solid(shape));
    }
    BRep_Builder builder;
    TopoDS_Compound compound;
    builder.MakeCompound(compound);
    bool any = false;
    for (TopExp_Explorer it(shape, TopAbs_SOLID); it.More(); it.Next()) {
        builder.Add(compound, oriented_solid(TopoDS::Solid(it.Current())));
        any = true;
    }
    return any ? TopoDS_Shape(compound) : shape;
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

occt_shape *occt_revolve(const occt_profile *profile, const double axis_origin[3], const double axis_direction[3],
                         double angle, occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        if (!profile || !std::isfinite(angle) || angle <= 0 || angle > 2 * M_PI + 1e-9) {
            set_error(status, "the revolve angle must be between 0 and 360 degrees");
            return nullptr;
        }
        const built_profile built = build_profile(*profile);
        const gp_Ax1 axis(gp_Pnt(axis_origin[0], axis_origin[1], axis_origin[2]),
                          gp_Dir(axis_direction[0], axis_direction[1], axis_direction[2]));
        BRepPrimAPI_MakeRevol revol(built.face, axis, std::min(angle, 2 * M_PI));
        revol.Build();
        if (!revol.IsDone()) {
            set_error(status, "the revolve could not be built");
            return nullptr;
        }
        const TopoDS_Shape solid = oriented(revol.Shape());
        history_builder records(solid);
        records.add(revol.FirstShape(), OCCT_FROM_START_CAP, 0, 0); // not part of a full revolve's result; filtered out by history_builder
        records.add(revol.LastShape(), OCCT_FROM_END_CAP, 0, 0);
        for (int k = 0; k < static_cast<int>(built.edges.size()); ++k) {
            if (revol.Generated(built.edges[k]).IsEmpty()) {
                // A full revolution leaves Generated() empty for edges that sweep a planar face. The
                // underlying sweep still knows them. The const_cast is sound: Revol() returns a const
                // reference to MakeRevol's non-const member, and Shape(edge) does not mutate it.
                records.add(const_cast<BRepSweep_Revol &>(revol.Revol()).Shape(built.edges[k]), OCCT_FROM_SEGMENT, 0, k);
            } else {
                records.add_all(revol.Generated(built.edges[k]), OCCT_FROM_SEGMENT, 0, k);
            }
        }
        records.move_into(history);
        return new occt_shape{solid};
    });
}

occt_shape *occt_loft(const occt_profile *profiles, int count, int ruled, occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        if (!profiles || count < 2) {
            set_error(status, "a loft needs at least two sections");
            return nullptr;
        }
        std::vector<built_profile> sections;
        BRepOffsetAPI_ThruSections loft(Standard_True, ruled ? Standard_True : Standard_False);
        for (int i = 0; i < count; ++i) {
            sections.push_back(build_profile(profiles[i]));
            loft.AddWire(BRepTools::OuterWire(sections.back().face));
        }
        loft.Build();
        if (!loft.IsDone()) {
            set_error(status, "the loft could not be built");
            return nullptr;
        }
        const TopoDS_Shape solid = oriented(loft.Shape());
        history_builder records(solid);
        records.add(loft.FirstShape(), OCCT_FROM_START_CAP, 0, 0);
        records.add(loft.LastShape(), OCCT_FROM_END_CAP, 0, 0);
        const std::vector<TopoDS_Edge> &first = sections.front().edges;
        for (int k = 0; k < static_cast<int>(first.size()); ++k) {
            records.add(loft.GeneratedFace(first[k]), OCCT_FROM_SEGMENT, 0, k);
        }
        records.move_into(history);
        return new occt_shape{solid};
    });
}

} // extern "C"
