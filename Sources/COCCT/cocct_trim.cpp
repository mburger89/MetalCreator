// Splitting a sheet by curves or bodies (NURBS spec, NS-4 Task 4; rulings R2, R4, R6, R7).
//
// The cutter is a prism of the curves (R7), the curves projected along the sheet's normals, or a body. `BRepAlgoAPI_Splitter` divides
// the sheet. A cut edge that has the same face on both sides (the cutter ended inside a face) is dropped by splitting again with only
// the edges that divide. Then each face of the result is given a point inside it, which decides its sides of every cutter element it
// borders and whether it is inside a closed cutter.

#include "cocct_sheet.hpp"
#include "cocct_splitter.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepAlgoAPI_Splitter.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepClass3d_SolidClassifier.hxx>
#include <BRepClass_FaceClassifier.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepGProp_Face.hxx>
#include <BRepOffsetAPI_NormalProjection.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepTools.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <BRep_Builder.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <GCPnts_QuasiUniformDeflection.hxx>
#include <GeomAbs_Shape.hxx>
#include <Geom2d_Curve.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <memory>
#include <numeric>
#include <vector>

using namespace cocct;

namespace {

constexpr const char *kClosedSolid = "Trim and Split take a sheet; this is a closed solid.";
constexpr const char *kCutterFailure = "The cutter couldn't divide this surface.";
constexpr const char *kNoCut = "The cutter doesn't cut the surface.";
constexpr double kNameTolerance = 1e-3;

enum split_side { kFront = 0, kBack = 1, kInsideSide = 2, kOutsideSide = 3 };

/// One thing a cut edge can lie on: a prism face, a projected edge or a face of the cutting body.
struct Element {
    int id = 0;
    TopoDS_Shape shape;
    int curve = -1;
    TopoDS_Edge wire_edge;
    bool reversed = false;
};

/// A closed curve in one plane: its polygon in the plane's own coordinates.
struct Loop {
    bool usable = false;
    gp_Pnt origin;
    gp_Dir normal;
    gp_Dir x_axis;
    gp_Dir y_axis;
    std::vector<gp_Pnt2d> points;
};

bool has_solid(const TopoDS_Shape &shape) {
    return TopExp_Explorer(shape, TopAbs_SOLID).More();
}

std::vector<TopoDS_Edge> wire_edges(const TopoDS_Wire &wire) {
    std::vector<TopoDS_Edge> edges;
    for (BRepTools_WireExplorer explorer(wire); explorer.More(); explorer.Next()) {
        edges.push_back(explorer.Current());
    }
    return edges;
}

std::vector<gp_Pnt> polyline_of(const std::vector<TopoDS_Edge> &edges) {
    std::vector<gp_Pnt> points;
    for (const TopoDS_Edge &edge : edges) {
        if (BRep_Tool::Degenerated(edge)) {
            continue;
        }
        BRepAdaptor_Curve curve(edge);
        std::vector<gp_Pnt> run;
        GCPnts_QuasiUniformDeflection sampler(curve, 0.002);
        if (sampler.IsDone()) {
            for (int i = 1; i <= sampler.NbPoints(); ++i) {
                run.push_back(sampler.Value(i));
            }
        } else {
            run.push_back(curve.Value(curve.FirstParameter()));
            run.push_back(curve.Value(curve.LastParameter()));
        }
        if (edge.Orientation() == TopAbs_REVERSED) {
            std::reverse(run.begin(), run.end());
        }
        for (const gp_Pnt &point : run) {
            if (points.empty() || points.back().Distance(point) > 1e-12) {
                points.push_back(point);
            }
        }
    }
    return points;
}

/// The loop of a closed curve that lies in one plane (within 1e-4 mm), else not usable.
Loop loop_of(const TopoDS_Wire &wire, const std::vector<TopoDS_Edge> &edges) {
    Loop loop;
    if (!BRep_Tool::IsClosed(wire)) {
        return loop;
    }
    const std::vector<gp_Pnt> points = polyline_of(edges);
    if (points.size() < 3) {
        return loop;
    }
    gp_XYZ centroid(0, 0, 0);
    for (const gp_Pnt &point : points) {
        centroid += point.XYZ();
    }
    centroid /= static_cast<double>(points.size());
    gp_XYZ newell(0, 0, 0);
    for (size_t i = 0; i < points.size(); ++i) {
        const gp_XYZ a = points[i].XYZ() - centroid;
        const gp_XYZ b = points[(i + 1) % points.size()].XYZ() - centroid;
        newell += a.Crossed(b);
    }
    if (newell.Modulus() < 1e-9) {
        return loop;
    }
    const gp_Dir normal(newell);
    for (const gp_Pnt &point : points) {
        if (std::abs((point.XYZ() - centroid).Dot(normal.XYZ())) > 1e-4) {
            return loop;
        }
    }
    loop.origin = gp_Pnt(centroid);
    loop.normal = normal;
    gp_Vec first(loop.origin, points[0]);
    first -= gp_Vec(normal) * first.Dot(gp_Vec(normal));
    if (first.Magnitude() < 1e-12) {
        return loop;
    }
    loop.x_axis = gp_Dir(first);
    loop.y_axis = gp_Dir(gp_Vec(normal).Crossed(gp_Vec(loop.x_axis)));
    for (const gp_Pnt &point : points) {
        const gp_Vec v(loop.origin, point);
        loop.points.emplace_back(v.Dot(gp_Vec(loop.x_axis)), v.Dot(gp_Vec(loop.y_axis)));
    }
    loop.usable = true;
    return loop;
}

/// Whether `point`, taken along `direction` (or straight down onto the plane when null), lies inside `loop`'s polygon. Sets `ok` false
/// when the direction runs in the plane.
bool loop_contains(const Loop &loop, const gp_Pnt &point, const gp_Vec *direction, bool &ok) {
    ok = true;
    gp_Pnt on_plane = point;
    const gp_Vec normal(loop.normal);
    if (direction) {
        const double denominator = direction->Dot(normal);
        if (std::abs(denominator) < 1e-9) {
            ok = false;
            return false;
        }
        const double t = gp_Vec(point, loop.origin).Dot(normal) / denominator;
        on_plane = point.Translated((*direction) * t);
    } else {
        const double t = gp_Vec(point, loop.origin).Dot(normal);
        on_plane = point.Translated(normal * t);
    }
    const gp_Vec v(loop.origin, on_plane);
    const double x = v.Dot(gp_Vec(loop.x_axis));
    const double y = v.Dot(gp_Vec(loop.y_axis));
    bool inside = false;
    const size_t count = loop.points.size();
    for (size_t i = 0, j = count - 1; i < count; j = i++) {
        const gp_Pnt2d &a = loop.points[i];
        const gp_Pnt2d &b = loop.points[j];
        if ((a.Y() > y) != (b.Y() > y) && x < (b.X() - a.X()) * (y - a.Y()) / (b.Y() - a.Y()) + a.X()) {
            inside = !inside;
        }
    }
    return inside;
}

/// For each shape of `sources` (the sheet's faces or edges), the shapes of the result it became, as the splitter's history says.
void source_map(BRepAlgoAPI_Splitter &splitter, const TopTools_IndexedMapOfShape &sources, const TopTools_IndexedMapOfShape &result,
                std::vector<int> &out) {
    out.assign(result.Extent(), 0);
    for (int i = 1; i <= sources.Extent(); ++i) {
        const TopoDS_Shape &source = sources(i);
        const TopTools_ListOfShape &modified = splitter.Modified(source);
        if (modified.IsEmpty()) {
            if (!splitter.IsDeleted(source)) {
                const int index = result.FindIndex(source);
                if (index > 0) {
                    out[index - 1] = i;
                }
            }
            continue;
        }
        for (TopTools_ListOfShape::Iterator it(modified); it.More(); it.Next()) {
            const int index = result.FindIndex(it.Value());
            if (index > 0) {
                out[index - 1] = i;
            }
        }
    }
}

/// The faces as a sheet: one shell per set of faces that join over shared edges (cut edges included), so a sheet whose faces are
/// loose, as an imported one can be, stays valid. One set is that shell; several are a compound of shells.
TopoDS_Shape assemble_sheet(const std::vector<TopoDS_Face> &faces) {
    BRep_Builder builder;
    TopoDS_Compound all;
    builder.MakeCompound(all);
    for (const TopoDS_Face &face : faces) {
        builder.Add(all, face);
    }
    TopTools_IndexedMapOfShape face_map;
    for (const TopoDS_Face &face : faces) {
        face_map.Add(face);
    }
    TopTools_IndexedDataMapOfShapeListOfShape ancestors;
    TopExp::MapShapesAndAncestors(all, TopAbs_EDGE, TopAbs_FACE, ancestors);
    std::vector<int> parent(face_map.Extent());
    std::iota(parent.begin(), parent.end(), 0);
    const auto root = [&](int x) {
        while (parent[x] != x) {
            parent[x] = parent[parent[x]];
            x = parent[x];
        }
        return x;
    };
    for (int e = 1; e <= ancestors.Extent(); ++e) {
        int first = -1;
        for (TopTools_ListOfShape::Iterator it(ancestors(e)); it.More(); it.Next()) {
            const int index = face_map.FindIndex(it.Value()) - 1;
            if (index < 0) {
                continue;
            }
            if (first < 0) {
                first = index;
            } else {
                const int a = root(first);
                const int b = root(index);
                parent[std::max(a, b)] = std::min(a, b);
            }
        }
    }
    std::vector<int> labels;
    std::vector<TopoDS_Shell> shells;
    for (int f = 0; f < face_map.Extent(); ++f) {
        const int r = root(f);
        auto found = std::find(labels.begin(), labels.end(), r);
        if (found == labels.end()) {
            labels.push_back(r);
            TopoDS_Shell shell;
            builder.MakeShell(shell);
            shells.push_back(shell);
            found = labels.end() - 1;
        }
        builder.Add(shells[found - labels.begin()], face_map(f + 1));
    }
    if (shells.size() == 1) {
        return shells[0];
    }
    TopoDS_Compound compound;
    builder.MakeCompound(compound);
    for (const TopoDS_Shell &shell : shells) {
        builder.Add(compound, shell);
    }
    return compound;
}

/// A point strictly inside `face`: the UV box sampled 8 x 8, then 32 x 32, then 128 x 128, the inside sample nearest the box's middle.
bool interior_point(const TopoDS_Face &face, gp_Pnt &point) {
    double u0 = 0;
    double u1 = 0;
    double v0 = 0;
    double v1 = 0;
    BRepTools::UVBounds(face, u0, u1, v0, v1);
    BRepAdaptor_Surface surface(face);
    for (const int n : {8, 32, 128}) {
        bool found = false;
        double best = 0;
        double best_u = 0;
        double best_v = 0;
        for (int i = 0; i < n; ++i) {
            for (int j = 0; j < n; ++j) {
                const double u = u0 + (i + 0.5) / n * (u1 - u0);
                const double v = v0 + (j + 0.5) / n * (v1 - v0);
                BRepClass_FaceClassifier classifier;
                classifier.Perform(face, gp_Pnt2d(u, v), 1e-7);
                if (classifier.State() != TopAbs_IN) {
                    continue;
                }
                const double d = std::hypot((u - 0.5 * (u0 + u1)) / std::max(u1 - u0, 1e-12),
                                            (v - 0.5 * (v0 + v1)) / std::max(v1 - v0, 1e-12));
                if (!found || d < best) {
                    found = true;
                    best = d;
                    best_u = u;
                    best_v = v;
                }
            }
        }
        if (found) {
            point = surface.Value(best_u, best_v);
            return true;
        }
    }
    return false;
}

/// The point of `edge` nearest `target` (distance in the plane across `skip`, when given) and the edge's tangent there, running with
/// the edge's own orientation.
void nearest_on_edge(const TopoDS_Edge &edge, bool reversed, const gp_Pnt &target, const gp_Vec *skip, gp_Vec &tangent) {
    BRepAdaptor_Curve curve(edge);
    const double first = curve.FirstParameter();
    const double last = curve.LastParameter();
    const auto measure = [&](double s) {
        gp_Vec offset(curve.Value(s), target);
        if (skip) {
            offset -= (*skip) * offset.Dot(*skip);
        }
        return offset.Magnitude();
    };
    constexpr int kSamples = 256;
    int best = 0;
    double best_distance = measure(first);
    for (int i = 1; i <= kSamples; ++i) {
        const double distance = measure(first + (last - first) * i / kSamples);
        if (distance < best_distance) {
            best_distance = distance;
            best = i;
        }
    }
    double lo = first + (last - first) * std::max(best - 1, 0) / kSamples;
    double hi = first + (last - first) * std::min(best + 1, kSamples) / kSamples;
    for (int i = 0; i < 60; ++i) {
        const double a = lo + (hi - lo) / 3;
        const double b = hi - (hi - lo) / 3;
        if (measure(a) < measure(b)) {
            hi = b;
        } else {
            lo = a;
        }
    }
    gp_Pnt point;
    curve.D1(0.5 * (lo + hi), point, tangent);
    if (reversed) {
        tangent.Reverse();
    }
}

} // namespace

void occt_split_result_free(occt_split_result *result) {
    if (!result) {
        return;
    }
    std::free(result->faces);
    std::free(result->pairs);
    std::free(result->edges);
    *result = occt_split_result{};
}

occt_shape *occt_split_sheet(const occt_shape *sheet, int kind, const occt_shape *const *curves, int curve_count,
                             const double direction[3], const occt_shape *body, const occt_cancel *cancel,
                             occt_split_result *out, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!sheet || sheet->shape.IsNull() || !out) {
            throw user_error("This surface can't be cut.");
        }
        *out = occt_split_result{};
        const TopoDS_Shape &input = sheet->shape;
        if (has_solid(input)) {
            throw user_error(kClosedSolid);
        }
        const TopTools_IndexedMapOfShape input_faces = map_of(input, TopAbs_FACE);
        const TopTools_IndexedMapOfShape input_edges = map_of(input, TopAbs_EDGE);
        if (input_faces.IsEmpty()) {
            throw user_error("This surface has no faces.");
        }
        const bool input_valid = BRepCheck_Analyzer(input).IsValid();
        poll(cancel);

        // The cutter's elements, its tools, and the loops of its curves.
        std::vector<Element> elements;
        std::vector<Loop> loops;
        TopTools_ListOfShape tools;
        gp_Vec along;
        bool body_closed = false;
        TopoDS_Shape body_shape;
        std::vector<TopoDS_Face> body_faces;
        if (kind == 2) {
            if (!body || body->shape.IsNull()) {
                throw user_error(kNoCut);
            }
            body_shape = body->shape;
            body_closed = has_solid(body_shape);
            const TopTools_IndexedMapOfShape faces = map_of(body_shape, TopAbs_FACE);
            for (int i = 1; i <= faces.Extent(); ++i) {
                Element element;
                element.id = i - 1;
                element.shape = faces(i);
                elements.push_back(element);
                body_faces.push_back(TopoDS::Face(faces(i)));
            }
            tools.Append(body_shape);
        } else {
            if (!curves || curve_count < 1) {
                throw user_error(kNoCut);
            }
            std::vector<TopoDS_Wire> wires;
            std::vector<std::vector<TopoDS_Edge>> per_curve;
            for (int c = 0; c < curve_count; ++c) {
                if (!curves[c] || curves[c]->shape.IsNull() || curves[c]->shape.ShapeType() != TopAbs_WIRE) {
                    throw user_error("This curve can't be used.");
                }
                wires.push_back(TopoDS::Wire(curves[c]->shape));
                per_curve.push_back(wire_edges(wires.back()));
                loops.push_back(loop_of(wires.back(), per_curve.back()));
            }
            if (kind == 0) {
                if (!direction) {
                    throw user_error("The direction can't be zero.");
                }
                along = gp_Vec(direction[0], direction[1], direction[2]);
                if (!(along.Magnitude() > 1e-12) || !std::isfinite(along.Magnitude())) {
                    throw user_error("The direction can't be zero.");
                }
                along.Normalize();
                const auto range = [&](const TopoDS_Shape &shape, double &lo, double &hi) {
                    Bnd_Box box;
                    shape_bounds(shape, box, false);
                    double x0 = 0;
                    double y0 = 0;
                    double z0 = 0;
                    double x1 = 0;
                    double y1 = 0;
                    double z1 = 0;
                    box.Get(x0, y0, z0, x1, y1, z1);
                    lo = 1e300;
                    hi = -1e300;
                    for (const double x : {x0, x1}) {
                        for (const double y : {y0, y1}) {
                            for (const double z : {z0, z1}) {
                                const double s = gp_Vec(x, y, z).Dot(along);
                                lo = std::min(lo, s);
                                hi = std::max(hi, s);
                            }
                        }
                    }
                };
                double s0 = 0;
                double s1 = 0;
                range(input, s0, s1);
                double c0 = 1e300;
                double c1 = -1e300;
                for (const TopoDS_Wire &wire : wires) {
                    double lo = 0;
                    double hi = 0;
                    range(wire, lo, hi);
                    c0 = std::min(c0, lo);
                    c1 = std::max(c1, hi);
                }
                const double margin = 1.0 + 0.01 * (std::max(s1, c1) - std::min(s0, c0));
                const double shift = s0 - margin - c1;
                const double length = (s1 + margin) - (c0 + shift);
                gp_Trsf move;
                move.SetTranslation(along * shift);
                int next = 0;
                for (int c = 0; c < curve_count; ++c) {
                    BRepBuilderAPI_Transform moved(wires[c], move, Standard_True);
                    if (!moved.IsDone()) {
                        throw user_error("The cutter couldn't be built.");
                    }
                    BRepPrimAPI_MakePrism prism(moved.Shape(), along * length);
                    if (!prism.IsDone()) {
                        throw user_error("The cutter couldn't be built.");
                    }
                    for (const TopoDS_Edge &edge : per_curve[c]) {
                        Element element;
                        element.id = next++;
                        element.curve = c;
                        element.wire_edge = edge;
                        element.reversed = edge.Orientation() == TopAbs_REVERSED;
                        const TopTools_ListOfShape &made = prism.Generated(moved.ModifiedShape(edge));
                        if (made.Extent() == 1) {
                            element.shape = made.First();
                        } else if (made.Extent() > 1) {
                            BRep_Builder builder;
                            TopoDS_Compound compound;
                            builder.MakeCompound(compound);
                            for (TopTools_ListOfShape::Iterator it(made); it.More(); it.Next()) {
                                builder.Add(compound, it.Value());
                            }
                            element.shape = compound;
                        }
                        elements.push_back(element);
                    }
                    tools.Append(prism.Shape());
                    poll(cancel);
                }
            } else {
                BRepOffsetAPI_NormalProjection projection(input);
                projection.SetParams(1e-5, 1e-5, GeomAbs_C1, 14, 16);
                std::vector<std::pair<TopoDS_Edge, std::pair<int, int>>> ancestors;
                int next = 0;
                for (int c = 0; c < curve_count; ++c) {
                    projection.Add(wires[c]);
                    for (const TopoDS_Edge &edge : per_curve[c]) {
                        ancestors.push_back({edge, {next++, c}});
                    }
                }
                projection.Build();
                if (!projection.IsDone()) {
                    throw user_error(kNoCut);
                }
                poll(cancel);
                for (TopExp_Explorer explorer(projection.Shape(), TopAbs_EDGE); explorer.More(); explorer.Next()) {
                    const TopoDS_Edge projected = TopoDS::Edge(explorer.Current());
                    Element element;
                    element.id = -1;
                    element.shape = projected;
                    try {
                        const TopoDS_Shape &ancestor = projection.Ancestor(projected);
                        for (const auto &candidate : ancestors) {
                            if (candidate.first.IsSame(ancestor)) {
                                element.id = candidate.second.first;
                                element.curve = candidate.second.second;
                                element.wire_edge = candidate.first;
                                element.reversed = candidate.first.Orientation() == TopAbs_REVERSED;
                                break;
                            }
                        }
                    } catch (...) {
                        element.id = -1;
                    }
                    elements.push_back(element);
                    tools.Append(projected);
                }
                if (tools.IsEmpty()) {
                    throw user_error(kNoCut);
                }
            }
        }

        // The first split; a cut edge with one face is a cut that ended inside it.
        SplitRun run = run_splitter(input, tools, cancel, kCutterFailure);
        TopTools_IndexedMapOfShape whole_edges = map_of(run.whole, TopAbs_EDGE);
        TopTools_IndexedDataMapOfShapeListOfShape whole_ancestors;
        TopExp::MapShapesAndAncestors(run.whole, TopAbs_EDGE, TopAbs_FACE, whole_ancestors);
        std::vector<int> whole_edge_source;
        source_map(*run.splitter, input_edges, whole_edges, whole_edge_source);
        TopTools_ListOfShape dividing;
        bool dangling = false;
        for (int i = 1; i <= whole_edges.Extent(); ++i) {
            if (whole_edge_source[i - 1] != 0) {
                continue;
            }
            const TopoDS_Edge edge = TopoDS::Edge(whole_edges(i));
            if (BRep_Tool::Degenerated(edge)) {
                continue;
            }
            if (distinct_faces(edge, whole_ancestors).size() >= 2) {
                dividing.Append(edge);
            } else {
                dangling = true;
            }
        }
        if (dividing.IsEmpty()) {
            throw user_error(kNoCut);
        }
        if (dangling) {
            run = run_splitter(input, dividing, cancel, kCutterFailure);
        }

        // The final faces as a sheet: a shell per connected set, so a loose-faced input stays valid.
        const TopTools_IndexedMapOfShape split_faces = map_of(run.whole, TopAbs_FACE);
        std::vector<TopoDS_Face> split_list;
        for (int i = 1; i <= split_faces.Extent(); ++i) {
            split_list.push_back(TopoDS::Face(split_faces(i)));
        }
        const TopoDS_Shape shell = assemble_sheet(split_list);
        if (input_valid && !BRepCheck_Analyzer(shell).IsValid()) {
            throw user_error("The cutter couldn't divide this surface cleanly.");
        }
        const TopTools_IndexedMapOfShape faces = map_of(shell, TopAbs_FACE);
        const TopTools_IndexedMapOfShape edges = map_of(shell, TopAbs_EDGE);
        TopTools_IndexedDataMapOfShapeListOfShape ancestors;
        TopExp::MapShapesAndAncestors(shell, TopAbs_EDGE, TopAbs_FACE, ancestors);
        std::vector<int> face_source;
        std::vector<int> edge_source;
        source_map(*run.splitter, input_faces, faces, face_source);
        source_map(*run.splitter, input_edges, edges, edge_source);

        // Pieces: faces joined across the edges the input already had.
        std::vector<int> parent(faces.Extent());
        std::iota(parent.begin(), parent.end(), 0);
        const auto root = [&](int x) {
            while (parent[x] != x) {
                parent[x] = parent[parent[x]];
                x = parent[x];
            }
            return x;
        };
        for (int i = 1; i <= edges.Extent(); ++i) {
            if (edge_source[i - 1] == 0) {
                continue;
            }
            const std::vector<TopoDS_Face> adjacent = distinct_faces(edges(i), ancestors);
            if (adjacent.size() == 2) {
                const int a = root(faces.FindIndex(adjacent[0]) - 1);
                const int b = root(faces.FindIndex(adjacent[1]) - 1);
                parent[std::max(a, b)] = std::min(a, b);
            }
        }
        std::vector<int> piece_of(faces.Extent(), -1);
        std::vector<int> labels;
        for (int f = 0; f < faces.Extent(); ++f) {
            const int r = root(f);
            auto found = std::find(labels.begin(), labels.end(), r);
            if (found == labels.end()) {
                labels.push_back(r);
                found = labels.end() - 1;
            }
            piece_of[f] = static_cast<int>(found - labels.begin());
        }

        // The cutter element each cut edge lies on, by distance from three points of the edge.
        std::vector<int> edge_element(edges.Extent(), -1);
        std::vector<int> edge_element_index(edges.Extent(), -1);
        for (int i = 1; i <= edges.Extent(); ++i) {
            if (edge_source[i - 1] != 0) {
                continue;
            }
            const TopoDS_Edge edge = TopoDS::Edge(edges(i));
            if (BRep_Tool::Degenerated(edge)) {
                continue;
            }
            BRepAdaptor_Curve curve(edge);
            const double first = curve.FirstParameter();
            const double last = curve.LastParameter();
            double best = kNameTolerance;
            for (size_t e = 0; e < elements.size(); ++e) {
                if (elements[e].shape.IsNull() || elements[e].id < 0) {
                    continue;
                }
                double worst = 0;
                for (const double fraction : {0.25, 0.5, 0.75}) {
                    const TopoDS_Vertex vertex = BRepBuilderAPI_MakeVertex(curve.Value(first + (last - first) * fraction));
                    BRepExtrema_DistShapeShape distance(vertex, elements[e].shape);
                    worst = std::max(worst, distance.IsDone() ? distance.Value() : 1e300);
                }
                if (worst <= best) {
                    best = worst;
                    edge_element[i - 1] = elements[e].id;
                    edge_element_index[i - 1] = static_cast<int>(e);
                }
            }
            poll(cancel);
        }

        // Inside flags and sides, from one point in each face.
        bool every_loop = kind != 2 && !loops.empty();
        for (const Loop &loop : loops) {
            every_loop = every_loop && loop.usable;
        }
        if (every_loop && kind == 0) {
            for (const Loop &loop : loops) {
                every_loop = every_loop && std::abs(along.Dot(gp_Vec(loop.normal))) > 1e-9;
            }
        }
        const bool has_inside = kind == 2 ? body_closed : every_loop;
        // The side a face lies on, by the cutting surface's normal at the middle of the cut edge it borders (R2); front when it can't say.
        const auto local_side = [&](const TopoDS_Edge &edge, const TopoDS_Face &face, const Element &element) -> int {
            BRepAdaptor_Curve curve(edge);
            const double middle = 0.5 * (curve.FirstParameter() + curve.LastParameter());
            gp_Pnt on_edge;
            gp_Vec tangent;
            curve.D1(middle, on_edge, tangent);
            if (edge.Orientation() == TopAbs_REVERSED) {
                tangent.Reverse();
            }
            double f0 = 0;
            double f1 = 0;
            const Handle(Geom2d_Curve) pcurve = BRep_Tool::CurveOnSurface(edge, face, f0, f1);
            if (pcurve.IsNull() || tangent.Magnitude() < 1e-12) {
                return kFront;
            }
            const gp_Pnt2d uv = pcurve->Value(0.5 * (f0 + f1));
            BRepGProp_Face properties(face);
            gp_Pnt surface_point;
            gp_Vec face_normal;
            properties.Normal(uv.X(), uv.Y(), surface_point, face_normal);
            if (face_normal.Magnitude() < 1e-12) {
                return kFront;
            }
            tangent.Normalize();
            face_normal.Normalize();
            const gp_Vec toward = face_normal.Crossed(tangent);
            gp_Vec cutting;
            if (kind == 2) {
                const TopoDS_Vertex vertex = BRepBuilderAPI_MakeVertex(on_edge);
                BRepExtrema_DistShapeShape distance(vertex, body_faces[element.id]);
                if (!distance.IsDone() || distance.NbSolution() < 1) {
                    return kFront;
                }
                double u = 0;
                double v = 0;
                if (distance.SupportTypeShape2(1) == BRepExtrema_IsInFace) {
                    distance.ParOnFaceS2(1, u, v);
                } else {
                    GeomAPI_ProjectPointOnSurf projector(on_edge, BRep_Tool::Surface(body_faces[element.id]));
                    if (!projector.IsDone() || projector.NbPoints() < 1) {
                        return kFront;
                    }
                    projector.LowerDistanceParameters(u, v);
                }
                BRepGProp_Face cutter_face(body_faces[element.id]);
                gp_Pnt unused;
                cutter_face.Normal(u, v, unused, cutting);
            } else {
                gp_Vec curve_tangent;
                nearest_on_edge(element.wire_edge, element.reversed, on_edge, kind == 0 ? &along : nullptr, curve_tangent);
                cutting = kind == 0 ? curve_tangent.Crossed(along) : curve_tangent.Crossed(face_normal);
            }
            return toward.Dot(cutting) >= 0 ? kFront : kBack;
        };
        std::vector<occt_split_face> face_table(faces.Extent());
        std::vector<occt_split_pair> pair_table;
        for (int f = 0; f < faces.Extent(); ++f) {
            poll(cancel);
            const TopoDS_Face face = TopoDS::Face(faces(f + 1));
            occt_split_face &entry = face_table[f];
            entry.source_face = face_source[f];
            entry.piece = piece_of[f];
            entry.inside = -1;
            entry.pair_start = static_cast<int>(pair_table.size());
            gp_Pnt point;
            if (!interior_point(face, point)) {
                continue;
            }
            bool in_body = false;
            if (kind == 2 && body_closed) {
                for (TopExp_Explorer solids(body_shape, TopAbs_SOLID); solids.More() && !in_body; solids.Next()) {
                    BRepClass3d_SolidClassifier classifier(solids.Current());
                    classifier.Perform(point, 1e-6);
                    in_body = classifier.State() == TopAbs_IN;
                }
            }
            if (has_inside) {
                if (kind == 2) {
                    entry.inside = in_body ? 1 : 0;
                } else {
                    int count = 0;
                    for (const Loop &loop : loops) {
                        bool ok = true;
                        count += loop_contains(loop, point, kind == 0 ? &along : nullptr, ok) ? 1 : 0;
                    }
                    entry.inside = count % 2;
                }
            }
            std::vector<int> seen;
            for (TopExp_Explorer walker(face, TopAbs_EDGE); walker.More(); walker.Next()) {
                const TopoDS_Edge edge = TopoDS::Edge(walker.Current());
                const int index = edges.FindIndex(edge);
                if (index < 1 || edge_source[index - 1] != 0 || edge_element[index - 1] < 0) {
                    continue;
                }
                if (edge.Orientation() != TopAbs_FORWARD && edge.Orientation() != TopAbs_REVERSED) {
                    continue;
                }
                const int element_id = edge_element[index - 1];
                if (std::find(seen.begin(), seen.end(), element_id) != seen.end()) {
                    continue;
                }
                seen.push_back(element_id);
                const Element &element = elements[edge_element_index[index - 1]];
                int side = kFront;
                bool decided = false;
                if (kind != 2 && element.curve >= 0 && loops[element.curve].usable) {
                    bool ok = true;
                    const bool contained = loop_contains(loops[element.curve], point, kind == 0 ? &along : nullptr, ok);
                    if (ok) {
                        side = contained ? kInsideSide : kOutsideSide;
                        decided = true;
                    }
                } else if (kind == 2 && body_closed) {
                    side = in_body ? kInsideSide : kOutsideSide;
                    decided = true;
                }
                if (!decided) {
                    side = local_side(edge, face, element);
                }
                pair_table.push_back(occt_split_pair{element_id, side});
            }
            entry.pair_count = static_cast<int>(pair_table.size()) - entry.pair_start;
        }
        std::vector<occt_split_edge> edge_table(edges.Extent());
        for (int i = 0; i < edges.Extent(); ++i) {
            edge_table[i] = occt_split_edge{edge_source[i], edge_source[i] != 0 ? -1 : edge_element[i]};
        }
        out->faces = copy_out(face_table);
        out->face_count = static_cast<int>(face_table.size());
        out->pairs = copy_out(pair_table);
        out->pair_count = static_cast<int>(pair_table.size());
        out->edges = copy_out(edge_table);
        out->edge_count = static_cast<int>(edge_table.size());
        out->piece_count = static_cast<int>(labels.size());
        bool classified = has_inside;
        for (const occt_split_face &entry : face_table) {
            classified = classified && entry.inside >= 0;
        }
        out->has_inside = classified ? 1 : 0;
        out->dangling = dangling ? 1 : 0;
        return new occt_shape{shell};
    });
}

occt_shape *occt_sub_sheet(const occt_shape *sheet, const int *face_indices, int count, occt_split_result *out, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!sheet || sheet->shape.IsNull() || !out) {
            throw user_error("This surface can't be used.");
        }
        *out = occt_split_result{};
        if (!face_indices || count < 1) {
            throw user_error("A sheet needs at least one face.");
        }
        const TopTools_IndexedMapOfShape input_faces = map_of(sheet->shape, TopAbs_FACE);
        const TopTools_IndexedMapOfShape input_edges = map_of(sheet->shape, TopAbs_EDGE);
        std::vector<TopoDS_Face> kept;
        std::vector<int> chosen;
        for (int k = 0; k < count; ++k) {
            const int index = face_indices[k];
            if (index < 1 || index > input_faces.Extent()) {
                throw user_error("That face isn't part of this sheet.");
            }
            if (std::find(chosen.begin(), chosen.end(), index) != chosen.end()) {
                continue;
            }
            chosen.push_back(index);
            kept.push_back(TopoDS::Face(input_faces(index)));
        }
        const TopoDS_Shape shell = assemble_sheet(kept);
        if (BRepCheck_Analyzer(sheet->shape).IsValid() && !BRepCheck_Analyzer(shell).IsValid()) {
            throw user_error("Those faces don't make a valid surface.");
        }
        const TopTools_IndexedMapOfShape faces = map_of(shell, TopAbs_FACE);
        const TopTools_IndexedMapOfShape edges = map_of(shell, TopAbs_EDGE);
        std::vector<occt_split_face> face_table(faces.Extent());
        for (int f = 0; f < faces.Extent(); ++f) {
            face_table[f] = occt_split_face{input_faces.FindIndex(faces(f + 1)), 0, -1, 0, 0};
        }
        std::vector<occt_split_edge> edge_table(edges.Extent());
        for (int e = 0; e < edges.Extent(); ++e) {
            edge_table[e] = occt_split_edge{input_edges.FindIndex(edges(e + 1)), -1};
        }
        out->faces = copy_out(face_table);
        out->face_count = static_cast<int>(face_table.size());
        out->edges = copy_out(edge_table);
        out->edge_count = static_cast<int>(edge_table.size());
        out->pairs = copy_out(std::vector<occt_split_pair>());
        return new occt_shape{shell};
    });
}
