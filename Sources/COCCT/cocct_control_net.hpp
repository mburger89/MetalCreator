// Moving a face onto another surface (NS-3 Task 3; Rebuild, Task 4, uses it too). Not part of the public C API.
#ifndef COCCT_CONTROL_NET_HPP
#define COCCT_CONTROL_NET_HPP

#include "cocct_internal.hpp"

#include <Geom_Surface.hxx>
#include <TopoDS_Face.hxx>

namespace cocct {

/// Puts `face` on `surface`, which must share the parameter domain of the surface its pcurves were made on. The face keeps its
/// pcurves (re-attached to the new surface), every edge's 3D curve is dropped and rebuilt from its pcurve
/// (`BRepLib::BuildCurves3d`), each vertex moves to where its edge's pcurve now lands, and `BRepLib::SameParameter` and
/// `BRepLib::UpdateTolerances` follow. The face is changed IN PLACE: the caller passes a face of a copy it owns
/// (`BRepBuilderAPI_Copy` with geometry), never one whose geometry another shape shares. Returns the face, its orientation as given.
/// An edge whose 3D curve still lies on the new surface (within 1e-7 mm at nine samples) is kept, so straight and circular edges
/// the change didn't reach stay so. `original` (optional) is the face as it was before a conversion to a B-spline gave `face` its own
/// copies of the edges, with its edges in the same order: when an edge's converted curve doesn't fit but the original's does, the
/// original's is put back. Does not run `BRepCheck_Analyzer`: the caller checks the whole result (and skips it when the input
/// itself was invalid).
TopoDS_Face replace_face_surface(const TopoDS_Face &face, const Handle(Geom_Surface) &surface,
                                 const TopoDS_Face &original = TopoDS_Face());

} // namespace cocct

#endif
