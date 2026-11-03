// Profiles turned into OCCT geometry, shared by the builders (cocct_build.cpp defines these) and the end-constrained
// loft (cocct_loft_ends.cpp). Private to the shim.
#ifndef COCCT_PROFILE_HPP
#define COCCT_PROFILE_HPP

#include "cocct.h"

#include <Geom_BSplineCurve.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Ax2.hxx>
#include <gp_Pnt.hxx>

#include <vector>

namespace cocct {

/// A profile turned into a planar face, with each loop's edges in segment order (loop 0 = outer).
struct built_profile {
    TopoDS_Face face;
    std::vector<std::vector<TopoDS_Edge>> loops;
};

/// The plane's frame: origin, normal as the main direction, x axis.
gp_Ax2 frame_of(const occt_plane &plane);
/// The point at plane coordinates (x, y).
gp_Pnt point_on(const gp_Ax2 &frame, double x, double y);
/// The degree-5 curve of a kind-2 (spline) segment, in the plane's frame; throws `user_error` for a malformed spline.
Handle(Geom_BSplineCurve) spline_curve(const gp_Ax2 &frame, const occt_profile &profile, const occt_segment &segment);
/// The profile's planar face; throws `user_error` for a profile that isn't a closed, flat region.
built_profile build_profile(const occt_profile &profile);
/// Orients every solid in `shape` (a solid, or a compound of solids) so it bounds positive volume. Face identities are
/// kept, so history recorded against the builder still matches the result.
TopoDS_Shape oriented(const TopoDS_Shape &shape);

} // namespace cocct

#endif
