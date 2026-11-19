// Making solids out of closed shells (NS-5). Not part of the public C API.
#ifndef COCCT_SOLIDS_HPP
#define COCCT_SOLIDS_HPP

#include "cocct_internal.hpp"

namespace cocct {

/// The valid, outward-oriented solid a closed free shell makes, or a null shape when `shell` is open or makes no valid solid.
TopoDS_Shape solidify_closed_shell(const TopoDS_Shape &shell);

/// One solid of two closed shells, the larger-volume one its outer shell and the other a void in it (R7). Each shell is made a solid
/// alone first (null when either fails); a vertex of the inner shell must classify inside the outer solid; the result must pass
/// `BRepCheck_Analyzer`, have a positive volume and equal V(outer) - V(inner) within 1e-6 relative, else a null shape.
TopoDS_Shape solid_with_void(const TopoDS_Shape &a, const TopoDS_Shape &b);

} // namespace cocct

#endif
