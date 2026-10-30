#include "cocct_internal.hpp"
#include "cocct_edge_curve.hpp"
#include "cocct_polyline.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepTools.hxx>
#include <BRep_Tool.hxx>
#include <Bnd_Box.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <ElSLib.hxx>
#include <IMeshTools_Parameters.hxx>
#include <Precision.hxx>
#include <Poly_Triangulation.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <gp_Ax3.hxx>
#include <gp_Circ.hxx>
#include <gp_Dir.hxx>
#include <gp_Pln.hxx>
#include <gp_Pnt.hxx>

#include <algorithm>
#include <cmath>

using namespace cocct;

namespace {

bool finite3(const double v[3]) {
    return std::isfinite(v[0]) && std::isfinite(v[1]) && std::isfinite(v[2]);
}

void append3(std::vector<double> &out, const gp_Pnt &p) {
    out.insert(out.end(), {p.X(), p.Y(), p.Z()});
}

} // namespace

extern "C" {

int occt_section(const occt_shape *shape, const double origin[3], const double normal[3], const double x_axis[3],
                 double tolerance, occt_section_result *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_section_result{};
        if (!std::isfinite(tolerance) || tolerance <= 0) {
            throw user_error("the section tolerance must be greater than 0");
        }
        if (!finite3(origin) || !finite3(normal) || !finite3(x_axis)) {
            throw user_error("the section plane is not a finite plane");
        }
        const gp_Vec normal_vector(normal[0], normal[1], normal[2]);
        const gp_Vec x_vector(x_axis[0], x_axis[1], x_axis[2]);
        if (normal_vector.Magnitude() < 1e-12 || x_vector.Magnitude() < 1e-12) {
            throw user_error("the section plane has no direction");
        }
        const gp_Dir direction(normal_vector);
        const gp_Pnt centre(origin[0], origin[1], origin[2]);
        // The plane's x axis is the one given, made perpendicular to the normal by the axis system.
        const gp_Pln plane(gp_Ax3(centre, direction, gp_Dir(x_vector)));

        Bnd_Box bounds;
        BRepBndLib::Add(shape->shape, bounds);
        if (bounds.IsVoid()) {
            return 1;
        }
        // The cutter is a window on the plane centred on the shape's bounding-box centre (projected onto the plane), so a part far
        // from the plane's origin is still covered.
        const double reach = std::sqrt(bounds.SquareExtent()) + 1.0;
        const gp_Pnt lower = bounds.CornerMin(), upper = bounds.CornerMax();
        const gp_Pnt middle(0.5 * (lower.X() + upper.X()), 0.5 * (lower.Y() + upper.Y()), 0.5 * (lower.Z() + upper.Z()));
        double u0 = 0, v0 = 0;
        ElSLib::Parameters(plane, middle, u0, v0);
        const TopoDS_Face cutter = BRepBuilderAPI_MakeFace(plane, u0 - reach, u0 + reach, v0 - reach, v0 + reach).Face();
        BRepAlgoAPI_Common common(shape->shape, cutter);
        if (common.HasErrors() || !common.IsDone()) {
            throw user_error("the section could not be built");
        }
        // A copy, so meshing never touches the triangulation of a face or edge the result shares with the solid.
        const TopoDS_Shape original = common.Shape();
        BRepBuilderAPI_Copy copier(original);
        const TopoDS_Shape result = copier.Shape();
        if (original.IsNull() || result.IsNull()) {
            return 1;
        }
        const TopTools_IndexedMapOfShape result_faces = map_of(result, TopAbs_FACE);
        if (result_faces.Extent() == 0) {
            return 1;
        }
        const TopTools_IndexedMapOfShape result_edges = map_of(result, TopAbs_EDGE);
        const TopTools_IndexedMapOfShape original_edges = map_of(original, TopAbs_EDGE);

        // The solid's face each section edge lies on: what the common made out of that face.
        std::vector<int> edge_source(static_cast<size_t>(result_edges.Extent()) + 1, -1);
        const TopTools_IndexedMapOfShape solid_faces = map_of(shape->shape, TopAbs_FACE);
        for (int f = 1; f <= solid_faces.Extent(); ++f) {
            for (TopTools_ListOfShape::Iterator it(common.Generated(solid_faces(f))); it.More(); it.Next()) {
                for (TopExp_Explorer edges(it.Value(), TopAbs_EDGE); edges.More(); edges.Next()) {
                    // `Generated` speaks of the common's own edges; the result is a copy of them.
                    const int found = original_edges.FindIndex(edges.Current());
                    if (found <= 0) {
                        continue;
                    }
                    const int copied = result_edges.FindIndex(copier.ModifiedShape(original_edges(found)));
                    if (copied > 0 && edge_source[static_cast<size_t>(copied)] < 0) {
                        edge_source[static_cast<size_t>(copied)] = f - 1;
                    }
                }
            }
        }

        IMeshTools_Parameters parameters;
        parameters.Deflection = tolerance;
        parameters.Angle = 0.5;
        parameters.InParallel = Standard_False;
        BRepTools::Clean(result);
        BRepMesh_IncrementalMesh mesher(result, parameters);

        std::vector<double> positions, curves, points;
        std::vector<unsigned int> indices;
        std::vector<int> region_offsets{0}, piece_region, piece_kind, piece_source, point_offsets{0};
        int region = 0;
        for (int i = 1; i <= result_faces.Extent(); ++i) {
            const TopoDS_Face face = TopoDS::Face(result_faces(i));
            TopLoc_Location location;
            const Handle(Poly_Triangulation) &triangulation = BRep_Tool::Triangulation(face, location);
            if (triangulation.IsNull() || triangulation->NbTriangles() == 0) {
                continue;
            }
            const gp_Trsf transform = location.Transformation();
            const unsigned int base = static_cast<unsigned int>(positions.size() / 3);
            for (int n = 1; n <= triangulation->NbNodes(); ++n) {
                append3(positions, triangulation->Node(n).Transformed(transform));
            }
            for (int t = 1; t <= triangulation->NbTriangles(); ++t) {
                int a = 0, b = 0, c = 0;
                triangulation->Triangle(t).Get(a, b, c);
                // Wind the triangle counter-clockwise about the plane's normal, whatever the face's orientation.
                const gp_Pnt pa = triangulation->Node(a).Transformed(transform);
                const gp_Pnt pb = triangulation->Node(b).Transformed(transform);
                const gp_Pnt pc = triangulation->Node(c).Transformed(transform);
                const gp_Vec turn = gp_Vec(pa, pb).Crossed(gp_Vec(pa, pc));
                if (turn.Dot(normal_vector) < 0) {
                    std::swap(b, c);
                }
                indices.insert(indices.end(), {base + a - 1, base + b - 1, base + c - 1});
            }
            region_offsets.push_back(static_cast<int>(indices.size() / 3));

            const TopTools_IndexedMapOfShape face_edges = map_of(face, TopAbs_EDGE);
            for (int e = 1; e <= face_edges.Extent(); ++e) {
                const TopoDS_Edge edge = TopoDS::Edge(face_edges(e));
                if (BRep_Tool::Degenerated(edge)) {
                    continue;
                }
                BRepAdaptor_Curve curve(edge);
                const int kind = edge_curve_kind(curve);
                const double first = curve.FirstParameter();
                const double last = curve.LastParameter();
                const bool bounded = !Precision::IsInfinite(first) && !Precision::IsInfinite(last);
                double numbers[11] = {};
                int piece = 0;
                if (kind == 0 && bounded) {
                    const gp_Pnt start = curve.Value(first), end = curve.Value(last);
                    const double line[6] = {start.X(), start.Y(), start.Z(), end.X(), end.Y(), end.Z()};
                    std::copy(line, line + 6, numbers);
                    piece = 1;
                } else if (kind == 1 && bounded) {
                    const gp_Circ circle = curve.Circle();
                    const gp_Pnt middle = circle.Location(), start = curve.Value(first);
                    const gp_Dir axis = circle.Axis().Direction();
                    const double circular[11] = {middle.X(), middle.Y(), middle.Z(), axis.X(), axis.Y(), axis.Z(),
                                                 circle.Radius(), start.X(), start.Y(), start.Z(), last - first};
                    std::copy(circular, circular + 11, numbers);
                    piece = 2;
                }
                if (!append_polygon_on_triangulation(edge, {face}, points)) {
                    append_sampled_curve(edge, tolerance, points);
                }
                point_offsets.push_back(static_cast<int>(points.size() / 3));
                curves.insert(curves.end(), numbers, numbers + 11);
                piece_region.push_back(region);
                piece_kind.push_back(piece);
                const int found = result_edges.FindIndex(edge);
                piece_source.push_back(found > 0 ? edge_source[static_cast<size_t>(found)] : -1);
            }
            ++region;
        }
        if (region == 0) {
            return 1;
        }

        occt_section_result built{};
        try {
            built.positions = copy_out(positions);
            built.indices = copy_out(indices);
            built.region_triangle_offsets = copy_out(region_offsets);
            built.piece_region = copy_out(piece_region);
            built.piece_kind = copy_out(piece_kind);
            built.piece_curve = copy_out(curves);
            built.piece_source_face = copy_out(piece_source);
            built.piece_points = copy_out(points);
            built.piece_point_offsets = copy_out(point_offsets);
        } catch (...) {
            occt_section_free(&built);
            throw;
        }
        built.vertex_count = static_cast<int>(positions.size() / 3);
        built.triangle_count = static_cast<int>(indices.size() / 3);
        built.region_count = region;
        built.piece_count = static_cast<int>(piece_kind.size());
        *out = built;
        return 1;
    });
}

void occt_section_free(occt_section_result *result) {
    if (result) {
        std::free(result->positions);
        std::free(result->indices);
        std::free(result->region_triangle_offsets);
        std::free(result->piece_region);
        std::free(result->piece_kind);
        std::free(result->piece_curve);
        std::free(result->piece_source_face);
        std::free(result->piece_points);
        std::free(result->piece_point_offsets);
        *result = occt_section_result{};
    }
}

} // extern "C"
