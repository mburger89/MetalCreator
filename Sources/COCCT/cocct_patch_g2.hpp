// The G2 boundary patch (NURBS spec, NS-2 Task 5): what `occt_boundary_patch` calls when a piece lies on a sheet and the
// patch is to meet it curvature continuously. Private to the shim.
#ifndef COCCT_PATCH_G2_HPP
#define COCCT_PATCH_G2_HPP

#include "cocct_sheet.hpp"

#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>

#include <vector>

namespace cocct {

/// One bounding piece in loop order. `support` is null for a curve, held in position only.
struct g2_side {
    TopoDS_Edge edge;
    TopoDS_Face support;
    int input_number = 0; // 1-based, as the person numbers the pieces
};

/// The face of the three- or four-sided patch over `sides` (in loop order, joined end to end), tangent and curvature continuous
/// to each side's support. Three sides use the fillet's degree-17 triangular patch, four a biquintic Coons patch. Throws
/// `user_error` with the reason when it can't be made; `occt_cancel` is polled between the steps.
TopoDS_Face build_g2_patch(const std::vector<g2_side> &sides, const occt_cancel *cancel);

} // namespace cocct

#endif
