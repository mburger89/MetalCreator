// The pieces of the edge-continuity grading that Match Surface (NS-4) reuses to read a target face. Not part of the public C API.
#ifndef COCCT_CONTINUITY_HPP
#define COCCT_CONTINUITY_HPP

#include <BRep_Tool.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <Geom2d_Curve.hxx>
#include <Geom_Surface.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Vec.hxx>

namespace cocct::continuity_detail {

struct side_sample {
    gp_Pnt point;
    gp_Vec normal;
    double curvature = 0;
    bool ok = false;
};

/// One face of the edge: its pcurve and surface adaptor, built once per call.
struct face_side {
    const TopoDS_Face &face;
    opencascade::handle<Geom2d_Curve> pcurve;
    BRepAdaptor_Surface surface;

    face_side(const TopoDS_Edge &edge, const TopoDS_Face &f) : face(f), surface(f, Standard_True) {
        double first = 0, last = 0;
        pcurve = BRep_Tool::CurveOnSurface(edge, f, first, last);
    }
    /// A face the edge doesn't border: its uv comes from projecting points onto it.
    explicit face_side(const TopoDS_Face &f) : face(f), surface(f, Standard_True) {}
};

/// The point, outward unit normal and normal curvature across the edge (the direction in the tangent plane perpendicular to
/// `tangent`) of the face at `uv`.
side_sample sample_side_at(const face_side &side, const gp_Pnt2d &uv, const gp_Vec &tangent);

/// `sample_side_at` at the edge's own pcurve parameter `t`.
side_sample sample_side(const face_side &side, double t, const gp_Vec &tangent);

/// The unit direction in the face's tangent plane, perpendicular to `tangent`, that runs from `p` into the face (`normal` is the
/// face's unit normal there). `found` is false when neither side is inside; `both` when both are (the edge is in the face's interior).
struct inward {
    gp_Vec direction;
    bool found = false;
    bool both = false;
};
inward inward_direction(const TopoDS_Face &face, const opencascade::handle<Geom_Surface> &surface, const gp_Pnt &p,
                        const gp_Vec &normal, const gp_Vec &tangent);

} // namespace cocct::continuity_detail

#endif
