// Edge polylines shared by the shim's tessellation and section code. Not part of the public C API.
#ifndef COCCT_POLYLINE_HPP
#define COCCT_POLYLINE_HPP

#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRep_Tool.hxx>
#include <GCPnts_TangentialDeflection.hxx>
#include <Poly_PolygonOnTriangulation.hxx>
#include <Poly_Triangulation.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>

#include <vector>

namespace cocct {

/// Appends the edge's polygon on an adjacent face's triangulation, so the line is made of the very vertices the
/// mesh shows (M4 plan; carry-over "edge polylines from BRep_Tool::PolygonOnTriangulation"). The points are
/// computed exactly as occt_tessellate computes face vertices, so they compare equal bit for bit.
/// Returns false if no adjacent face has a polygon for this edge.
inline bool append_polygon_on_triangulation(const TopoDS_Edge &edge, const std::vector<TopoDS_Face> &faces,
                                            std::vector<double> &points) {
    for (const TopoDS_Face &face : faces) {
        TopLoc_Location location;
        const Handle(Poly_Triangulation) &triangulation = BRep_Tool::Triangulation(face, location);
        if (triangulation.IsNull()) {
            continue;
        }
        const Handle(Poly_PolygonOnTriangulation) &polygon =
            BRep_Tool::PolygonOnTriangulation(edge, triangulation, location);
        if (polygon.IsNull() || polygon->NbNodes() < 2) {
            continue;
        }
        const gp_Trsf transform = location.Transformation();
        const TColStd_Array1OfInteger &nodes = polygon->Nodes();
        for (int i = nodes.Lower(); i <= nodes.Upper(); ++i) {
            const gp_Pnt point = triangulation->Node(nodes(i)).Transformed(transform);
            points.insert(points.end(), {point.X(), point.Y(), point.Z()});
        }
        return true;
    }
    return false;
}

/// Fallback for an edge with no polygon on any face's triangulation: sample its curve.
inline void append_sampled_curve(const TopoDS_Edge &edge, double tolerance, std::vector<double> &points) {
    BRepAdaptor_Curve curve(edge);
    GCPnts_TangentialDeflection sampler(curve, 0.1, tolerance);
    for (int p = 1; p <= sampler.NbPoints(); ++p) {
        const gp_Pnt point = sampler.Value(p);
        points.insert(points.end(), {point.X(), point.Y(), point.Z()});
    }
}

} // namespace cocct

#endif
