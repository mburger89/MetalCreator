#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepLib_ToolTriangulatedShape.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <GCPnts_TangentialDeflection.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <IMeshTools_Parameters.hxx>
#include <Poly_PolygonOnTriangulation.hxx>
#include <Poly_Triangulation.hxx>
#include <STEPControl_Reader.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>

#include <cmath>

using namespace cocct;

namespace {

/// Appends the edge's polygon on an adjacent face's triangulation, so the line is made of the very vertices the
/// mesh shows (M4 plan; carry-over "edge polylines from BRep_Tool::PolygonOnTriangulation"). The points are
/// computed exactly as occt_tessellate computes face vertices, so they compare equal bit for bit.
/// Returns false if no adjacent face has a polygon for this edge.
bool append_polygon_on_triangulation(const TopoDS_Edge &edge, const std::vector<TopoDS_Face> &faces,
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
void append_sampled_curve(const TopoDS_Edge &edge, double tolerance, std::vector<double> &points) {
    BRepAdaptor_Curve curve(edge);
    GCPnts_TangentialDeflection sampler(curve, 0.1, tolerance);
    for (int p = 1; p <= sampler.NbPoints(); ++p) {
        const gp_Pnt point = sampler.Value(p);
        points.insert(points.end(), {point.X(), point.Y(), point.Z()});
    }
}

} // namespace

extern "C" {

int occt_tessellate(const occt_shape *shape, double tolerance, occt_mesh *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_mesh{};
        if (!std::isfinite(tolerance) || tolerance <= 0) {
            set_error(status, "the tessellation tolerance must be greater than 0");
            return 0;
        }
        // Drop triangulations left in the (shared) shape by earlier meshing, such as a finer display mesh or an
        // STL export, so the result depends only on this shape and tolerance. Safe: every caller holds
        // OCCTKernel.serialized, and every other solid re-meshes on its own next tessellate.
        BRepTools::Clean(shape->shape);
        IMeshTools_Parameters parameters;
        parameters.Deflection = tolerance;
        parameters.Angle = 0.5;
        parameters.InParallel = Standard_False;
        BRepMesh_IncrementalMesh mesher(shape->shape, parameters);
        const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
        std::vector<double> positions, normals;
        std::vector<unsigned int> indices;
        std::vector<int> triangle_faces;
        for (int i = 1; i <= faces.Extent(); ++i) {
            const TopoDS_Face face = TopoDS::Face(faces(i));
            TopLoc_Location location;
            const Handle(Poly_Triangulation) &triangulation = BRep_Tool::Triangulation(face, location);
            if (triangulation.IsNull()) {
                continue;
            }
            BRepLib_ToolTriangulatedShape::ComputeNormals(face, triangulation);
            const gp_Trsf transform = location.Transformation();
            const bool reversed = face.Orientation() == TopAbs_REVERSED;
            const unsigned int base = static_cast<unsigned int>(positions.size() / 3);
            for (int n = 1; n <= triangulation->NbNodes(); ++n) {
                const gp_Pnt point = triangulation->Node(n).Transformed(transform);
                positions.insert(positions.end(), {point.X(), point.Y(), point.Z()});
                gp_Vec normal(triangulation->Normal(n));
                normal.Transform(transform);
                if (reversed) {
                    normal.Reverse();
                }
                if (normal.Magnitude() > 1e-12) {
                    normal.Normalize();
                }
                normals.insert(normals.end(), {normal.X(), normal.Y(), normal.Z()});
            }
            for (int t = 1; t <= triangulation->NbTriangles(); ++t) {
                int a = 0, b = 0, c = 0;
                triangulation->Triangle(t).Get(a, b, c);
                if (reversed) {
                    std::swap(b, c);
                }
                indices.insert(indices.end(), {base + a - 1, base + b - 1, base + c - 1});
                triangle_faces.push_back(i - 1);
            }
        }

        const TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(shape->shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);
        std::vector<double> edge_points;
        std::vector<int> edge_offsets{0};
        for (int e = 1; e <= edges.Extent(); ++e) {
            const TopoDS_Edge edge = TopoDS::Edge(edges(e));
            const std::vector<TopoDS_Face> adjacent = distinct_faces(edge, edge_faces);
            const bool seam = adjacent.size() == 1;
            if (!BRep_Tool::Degenerated(edge) && !seam) {
                if (!append_polygon_on_triangulation(edge, adjacent, edge_points)) {
                    append_sampled_curve(edge, tolerance, edge_points);
                }
            }
            edge_offsets.push_back(static_cast<int>(edge_points.size() / 3));
        }

        out->positions = copy_out(positions);
        out->normals = copy_out(normals);
        out->indices = copy_out(indices);
        out->triangle_faces = copy_out(triangle_faces);
        out->edge_points = copy_out(edge_points);
        out->edge_offsets = copy_out(edge_offsets);
        out->vertex_count = static_cast<int>(positions.size() / 3);
        out->triangle_count = static_cast<int>(triangle_faces.size());
        out->edge_count = edges.Extent();
        return 1;
    });
}

void occt_mesh_free(occt_mesh *mesh) {
    if (mesh) {
        std::free(mesh->positions);
        std::free(mesh->normals);
        std::free(mesh->indices);
        std::free(mesh->triangle_faces);
        std::free(mesh->edge_points);
        std::free(mesh->edge_offsets);
        *mesh = occt_mesh{};
    }
}

occt_shape *occt_make_compound(const occt_shape *const *shapes, int count, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!shapes || count <= 0) {
            set_error(status, "there is nothing to combine");
            return nullptr;
        }
        BRep_Builder builder;
        TopoDS_Compound compound;
        builder.MakeCompound(compound);
        for (int i = 0; i < count; ++i) {
            builder.Add(compound, shapes[i]->shape);
        }
        return new occt_shape{compound};
    });
}

occt_shape *occt_read_step(const char *path, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!path) {
            set_error(status, "no file path given");
            return nullptr;
        }
        occt_initialize();
        STEPControl_Reader reader;
        if (reader.ReadFile(path) != IFSelect_RetDone) {
            set_error(status, "the STEP file could not be read");
            return nullptr;
        }
        reader.TransferRoots();
        const TopoDS_Shape shape = reader.OneShape();
        if (shape.IsNull()) {
            set_error(status, "the STEP file contains no shapes");
            return nullptr;
        }
        return new occt_shape{shape};
    });
}

} // extern "C"
