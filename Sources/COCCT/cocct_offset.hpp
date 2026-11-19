// Offsetting a sheet (NS-5, Task 4; rulings R7, R8, R11). Shared by Offset Surface and Thicken. Not part of the public C API.
#ifndef COCCT_OFFSET_HPP
#define COCCT_OFFSET_HPP

#include "cocct_sheet.hpp"

#include <TopoDS_Edge.hxx>
#include <TopoDS_Shape.hxx>

#include <vector>

namespace cocct {

/// A source boundary edge and the free edge of the offset face that corresponds to it (R7).
struct offset_edge_pair {
    int source_index = 0; // 1-based in the sheet's edge map
    int image_index = 0;  // 1-based in the offset shell's edge map
    TopoDS_Edge source;
    TopoDS_Edge image;
};

/// What `offset_shell` makes: the offset shape, the image of each source face (null when it has none) and the boundary-edge pairs.
struct offset_result {
    TopoDS_Shape shell;
    std::vector<TopoDS_Shape> images; // per source face, in the sheet's face map order
    std::vector<offset_edge_pair> pairs;
};

/// The message a failed offset build carries; the Swift side treats it as "this distance doesn't work".
inline constexpr const char *kOffsetFailed = "The offset couldn't be built.";
/// The message an offset whose boundary edges can't be matched to the source's carries.
inline constexpr const char *kOffsetOpenEdges = "The offset changed the surface's open edges, so it can't be offset.";

/// `sheet` offset by `distance` along its face normals (the orientation of each face counts), `BRepOffsetAPI_MakeOffsetShape` in
/// skin mode with an intersection join. Throws `user_error` (`kOffsetFailed`, `kOffsetOpenEdges`, or `kCancelled` when `cancel` was set)
/// when the shape isn't built, isn't valid, has an edge or vertex tolerance over 0.01 mm, or has boundary edges that can't be paired.
offset_result offset_shell(const TopoDS_Shape &sheet, double distance, const occt_cancel *cancel);

/// The smallest positive distance d with d x kappa = 1 on the `sign` side (+1 along the normals, -1 against), kappa the principal
/// curvatures signed positive when the centre of curvature lies on the normal's side; +infinity when none (R8).
double curvature_limit(const TopoDS_Shape &sheet, int sign);

/// Whether two different pieces of `sheet` (connected open shells or lone faces) have edges that sewing at 0.01 mm would join (R11).
bool touching_pieces(const TopoDS_Shape &sheet);

} // namespace cocct

#endif
