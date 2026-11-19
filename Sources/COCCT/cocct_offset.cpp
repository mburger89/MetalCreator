// Offsetting a sheet along its normals (NS-5, Task 4; R7 build and pairing, R8 curvature, R11 touching pieces, R15 cancellation).

#include "cocct_offset.hpp"

#include "cocct_progress.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepOffsetAPI_MakeOffsetShape.hxx>
#include <BRepOffset_Mode.hxx>
#include <BRepTools.hxx>
#include <GeomAbs_JoinType.hxx>
#include <GeomAbs_Shape.hxx>
#include <Geom_BSplineSurface.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TopTools_ListOfShape.hxx>
#include <BRep_Builder.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Vertex.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <limits>
#include <numeric>

namespace cocct {

namespace {

constexpr double kMaxTolerance = 0.01;

/// The free edges of `shape`: edges with one distinct face that are neither seams nor degenerate.
std::vector<int> free_edge_indices(const TopoDS_Shape &shape, const TopTools_IndexedMapOfShape &edges) {
    TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
    TopExp::MapShapesAndAncestors(shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);
    std::vector<int> free;
    for (int i = 1; i <= edges.Extent(); ++i) {
        const TopoDS_Edge edge = TopoDS::Edge(edges(i));
        if (is_boundary_edge(edge, distinct_faces(edge, edge_faces))) {
            free.push_back(i);
        }
    }
    return free;
}

struct edge_points {
    gp_Pnt first, last, middle;
};

edge_points points_of(const TopoDS_Edge &edge) {
    BRepAdaptor_Curve curve(edge);
    const double a = curve.FirstParameter();
    const double b = curve.LastParameter();
    return {curve.Value(a), curve.Value(b), curve.Value(0.5 * (a + b))};
}

double pairing_cost(const edge_points &a, const edge_points &b) {
    const double forward = a.first.Distance(b.first) + a.last.Distance(b.last);
    const double backward = a.first.Distance(b.last) + a.last.Distance(b.first);
    return std::min(forward, backward) + a.middle.Distance(b.middle);
}

} // namespace

offset_result offset_shell(const TopoDS_Shape &sheet, double distance, const occt_cancel *cancel) {
    if (!std::isfinite(distance) || distance == 0) {
        throw user_error("The distance can't be 0.");
    }
    poll(cancel);
    const TopTools_IndexedMapOfShape source_faces = map_of(sheet, TopAbs_FACE);
    const TopTools_IndexedMapOfShape source_edges = map_of(sheet, TopAbs_EDGE);
    // OCCT offsets a connected shape; a value of several loose pieces is offset piece by piece (R11 keeps touching pieces out).
    // A piece is faces connected by shared edges, made a shell (a lone face is offset as it is).
    TopTools_IndexedDataMapOfShapeListOfShape source_edge_faces;
    TopExp::MapShapesAndAncestors(sheet, TopAbs_EDGE, TopAbs_FACE, source_edge_faces);
    std::vector<int> parent(source_faces.Extent() + 1);
    std::iota(parent.begin(), parent.end(), 0);
    auto root = [&](int x) {
        while (parent[x] != x) {
            parent[x] = parent[parent[x]];
            x = parent[x];
        }
        return x;
    };
    for (int i = 1; i <= source_edges.Extent(); ++i) {
        const std::vector<TopoDS_Face> adjacent = distinct_faces(source_edges(i), source_edge_faces);
        for (size_t k = 1; k < adjacent.size(); ++k) {
            parent[root(source_faces.FindIndex(adjacent[k]))] = root(source_faces.FindIndex(adjacent[0]));
        }
    }
    std::vector<int> roots;
    for (int f = 1; f <= source_faces.Extent(); ++f) {
        if (std::find(roots.begin(), roots.end(), root(f)) == roots.end()) {
            roots.push_back(root(f));
        }
    }
    offset_result result;
    result.images.assign(size_t(source_faces.Extent()), TopoDS_Shape());
    std::vector<TopoDS_Shape> shells;
    for (int piece_root : roots) {
        std::vector<int> members;
        for (int f = 1; f <= source_faces.Extent(); ++f) {
            if (root(f) == piece_root) {
                members.push_back(f);
            }
        }
        TopoDS_Shape piece;
        if (roots.size() == 1 && sheet.ShapeType() == TopAbs_SHELL) {
            piece = sheet;
        } else if (members.size() == 1) {
            piece = source_faces(members[0]);
        } else {
            BRep_Builder builder;
            TopoDS_Shell shell;
            builder.MakeShell(shell);
            for (int f : members) {
                builder.Add(shell, source_faces(f));
            }
            piece = shell;
        }
        BRepOffsetAPI_MakeOffsetShape maker;
        maker.PerformByJoin(piece, distance, 1e-7, BRepOffset_Skin, Standard_False, Standard_False, GeomAbs_Intersection,
                            Standard_False, progress_range(cancel));
        poll(cancel);
        if (!maker.IsDone() || maker.Shape().IsNull()) {
            throw user_error(kOffsetFailed);
        }
        if (!BRepCheck_Analyzer(maker.Shape()).IsValid()) {
            throw user_error(kOffsetFailed);
        }
        shells.push_back(maker.Shape());
        const TopTools_IndexedMapOfShape piece_result_faces = map_of(maker.Shape(), TopAbs_FACE);
        for (int f : members) {
            for (TopTools_ListOfShape::Iterator it(maker.Generated(source_faces(f))); it.More() && result.images[f - 1].IsNull();
                 it.Next()) {
                if (it.Value().ShapeType() == TopAbs_FACE && piece_result_faces.Contains(it.Value())) {
                    result.images[f - 1] = it.Value();
                }
            }
            if (result.images[f - 1].IsNull()) {
                throw user_error(kOffsetFailed);
            }
        }
    }
    if (shells.size() == 1) {
        result.shell = shells[0];
    } else {
        BRep_Builder builder;
        TopoDS_Compound compound;
        builder.MakeCompound(compound);
        for (const TopoDS_Shape &shell : shells) {
            builder.Add(compound, shell);
        }
        result.shell = compound;
    }
    for (TopExp_Explorer it(result.shell, TopAbs_EDGE); it.More(); it.Next()) {
        if (BRep_Tool::Tolerance(TopoDS::Edge(it.Current())) > kMaxTolerance) {
            throw user_error(kOffsetFailed);
        }
    }
    for (TopExp_Explorer it(result.shell, TopAbs_VERTEX); it.More(); it.Next()) {
        if (BRep_Tool::Tolerance(TopoDS::Vertex(it.Current())) > kMaxTolerance) {
            throw user_error(kOffsetFailed);
        }
    }
    const TopTools_IndexedMapOfShape result_edges = map_of(result.shell, TopAbs_EDGE);
    const std::vector<int> source_free = free_edge_indices(sheet, source_edges);
    const std::vector<int> result_free = free_edge_indices(result.shell, result_edges);
    for (int f = 1; f <= source_faces.Extent(); ++f) {
        const TopoDS_Shape image = result.images[f - 1];
        // R7: each free edge of the source face is paired with a free edge of its image, one to one, cheapest pairs first.
        const TopTools_IndexedMapOfShape face_edges = map_of(source_faces(f), TopAbs_EDGE);
        const TopTools_IndexedMapOfShape image_edges = map_of(image, TopAbs_EDGE);
        std::vector<int> sources, images;
        for (int index : source_free) {
            if (face_edges.Contains(source_edges(index))) {
                sources.push_back(index);
            }
        }
        for (int index : result_free) {
            if (image_edges.Contains(result_edges(index))) {
                images.push_back(index);
            }
        }
        if (sources.size() != images.size()) {
            throw user_error(kOffsetOpenEdges);
        }
        struct candidate {
            double cost;
            size_t a, b;
        };
        std::vector<candidate> candidates;
        std::vector<edge_points> source_points, image_points;
        for (int index : sources) {
            source_points.push_back(points_of(TopoDS::Edge(source_edges(index))));
        }
        for (int index : images) {
            image_points.push_back(points_of(TopoDS::Edge(result_edges(index))));
        }
        for (size_t a = 0; a < sources.size(); ++a) {
            for (size_t b = 0; b < images.size(); ++b) {
                candidates.push_back({pairing_cost(source_points[a], image_points[b]), a, b});
            }
        }
        std::stable_sort(candidates.begin(), candidates.end(),
                         [](const candidate &x, const candidate &y) { return x.cost < y.cost; });
        std::vector<bool> source_used(sources.size(), false), image_used(images.size(), false);
        for (const candidate &c : candidates) {
            if (source_used[c.a] || image_used[c.b]) {
                continue;
            }
            source_used[c.a] = image_used[c.b] = true;
            offset_edge_pair pair;
            pair.source_index = sources[c.a];
            pair.image_index = images[c.b];
            pair.source = TopoDS::Edge(source_edges(sources[c.a]));
            pair.image = TopoDS::Edge(result_edges(images[c.b]));
            result.pairs.push_back(pair);
        }
    }
    return result;
}

double curvature_limit(const TopoDS_Shape &sheet, int sign) {
    double limit = std::numeric_limits<double>::infinity();
    const TopTools_IndexedMapOfShape faces = map_of(sheet, TopAbs_FACE);
    for (int f = 1; f <= faces.Extent(); ++f) {
        const TopoDS_Face face = TopoDS::Face(faces(f));
        const BRepAdaptor_Surface surface(face, Standard_True);
        const double orientation = face.Orientation() == TopAbs_REVERSED ? -1.0 : 1.0;
        auto cuts_of = [&](bool is_u) {
            const int count = is_u ? surface.NbUIntervals(GeomAbs_C2) : surface.NbVIntervals(GeomAbs_C2);
            TColStd_Array1OfReal knots(1, count + 1);
            if (is_u) {
                surface.UIntervals(knots, GeomAbs_C2);
            } else {
                surface.VIntervals(knots, GeomAbs_C2);
            }
            std::vector<double> cuts;
            for (int i = 1; i <= count + 1; ++i) {
                cuts.push_back(knots(i));
            }
            return cuts;
        };
        const std::vector<double> cuts_u = cuts_of(true);
        const std::vector<double> cuts_v = cuts_of(false);
        const double span_count = double(cuts_u.size() - 1) * double(cuts_v.size() - 1);
        int per_span = 8;
        while (per_span > 1 && span_count * per_span * per_span > 1.0e6) {
            --per_span;
        }
        for (size_t i = 0; i + 1 < cuts_u.size(); ++i) {
            for (size_t j = 0; j + 1 < cuts_v.size(); ++j) {
                for (int a = 0; a < per_span; ++a) {
                    for (int b = 0; b < per_span; ++b) {
                        const double u = cuts_u[i] + (cuts_u[i + 1] - cuts_u[i]) * (a + 0.5) / per_span;
                        const double v = cuts_v[j] + (cuts_v[j + 1] - cuts_v[j]) * (b + 0.5) / per_span;
                        gp_Pnt point;
                        gp_Vec su, sv, suu, svv, suv;
                        surface.D2(u, v, point, su, sv, suu, svv, suv);
                        gp_Vec normal = su.Crossed(sv);
                        const double length = normal.Magnitude();
                        if (length < 1e-12) {
                            continue;
                        }
                        normal.Divide(length);
                        const double e = su.Dot(su), g = sv.Dot(sv), ff = su.Dot(sv);
                        const double l = suu.Dot(normal), m = suv.Dot(normal), n = svv.Dot(normal);
                        const double qa = e * g - ff * ff;
                        if (qa < 1e-18) {
                            continue;
                        }
                        const double qb = e * n + g * l - 2 * ff * m;
                        const double qc = l * n - m * m;
                        const double disc = std::sqrt(std::max(qb * qb - 4 * qa * qc, 0.0));
                        for (double k : {(qb + disc) / (2 * qa), (qb - disc) / (2 * qa)}) {
                            const double kappa = orientation * k;
                            // Moving d along the normal reaches the centre when d x kappa = 1 (kappa > 0 on the +normal side).
                            if (sign > 0 && kappa > 1e-12) {
                                limit = std::min(limit, 1.0 / kappa);
                            } else if (sign < 0 && kappa < -1e-12) {
                                limit = std::min(limit, -1.0 / kappa);
                            }
                        }
                    }
                }
            }
        }
    }
    return limit;
}

bool touching_pieces(const TopoDS_Shape &sheet) {
    // Work on a copy so sewing can't touch the input.
    const TopoDS_Shape work = BRepBuilderAPI_Copy(sheet, Standard_False, Standard_False).Shape();
    const TopTools_IndexedMapOfShape faces = map_of(work, TopAbs_FACE);
    const TopTools_IndexedMapOfShape edges = map_of(work, TopAbs_EDGE);
    TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
    TopExp::MapShapesAndAncestors(work, TopAbs_EDGE, TopAbs_FACE, edge_faces);
    // Pieces: faces that share an edge are one piece.
    std::vector<int> parent(faces.Extent() + 1);
    std::iota(parent.begin(), parent.end(), 0);
    auto root = [&](int x) {
        while (parent[x] != x) {
            parent[x] = parent[parent[x]];
            x = parent[x];
        }
        return x;
    };
    for (int i = 1; i <= edges.Extent(); ++i) {
        const std::vector<TopoDS_Face> adjacent = distinct_faces(edges(i), edge_faces);
        for (size_t k = 1; k < adjacent.size(); ++k) {
            parent[root(faces.FindIndex(adjacent[k]))] = root(faces.FindIndex(adjacent[0]));
        }
    }
    struct free_edge {
        TopoDS_Edge edge;
        int piece;
    };
    std::vector<free_edge> free_edges;
    for (int i = 1; i <= edges.Extent(); ++i) {
        const TopoDS_Edge edge = TopoDS::Edge(edges(i));
        const std::vector<TopoDS_Face> adjacent = distinct_faces(edge, edge_faces);
        if (is_boundary_edge(edge, adjacent)) {
            free_edges.push_back({edge, root(faces.FindIndex(adjacent[0]))});
        }
    }
    bool several = false;
    for (const free_edge &e : free_edges) {
        several = several || e.piece != free_edges.front().piece;
    }
    if (!several) {
        return false;
    }
    constexpr double kSewTolerance = 0.01;
    try {
        BRepBuilderAPI_Sewing sewing(kSewTolerance, Standard_True, Standard_True, Standard_True, Standard_False);
        sewing.Add(work);
        sewing.Perform();
        for (int i = 1; i <= sewing.NbContigousEdges(); ++i) {
            const TopoDS_Edge contiguous = sewing.ContigousEdge(i);
            const gp_Pnt middle = points_of(contiguous).middle;
            std::vector<int> pieces;
            for (const free_edge &e : free_edges) {
                BRepExtrema_DistShapeShape distance(BRepBuilderAPI_MakeVertex(middle).Vertex(), e.edge);
                if (distance.IsDone() && distance.Value() <= 2 * kSewTolerance &&
                    std::find(pieces.begin(), pieces.end(), e.piece) == pieces.end()) {
                    pieces.push_back(e.piece);
                }
            }
            if (pieces.size() > 1) {
                return true;
            }
        }
    } catch (const Standard_Failure &) {
        return false;
    }
    return false;
}

} // namespace cocct

occt_shape *occt_offset_surface(const occt_shape *sheet, double distance, const occt_cancel *cancel, occt_history *history,
                                occt_edge_history *edges, occt_status *status) {
    return cocct::guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!sheet || sheet->shape.IsNull()) {
            throw cocct::user_error("This surface can't be used.");
        }
        const cocct::offset_result result = cocct::offset_shell(sheet->shape, distance, cancel);
        cocct::history_builder faces(result.shell);
        for (size_t f = 0; f < result.images.size(); ++f) {
            faces.add(result.images[f], OCCT_FROM_FACE, 0, static_cast<int>(f) + 1);
        }
        std::vector<occt_edge_record> records;
        for (const cocct::offset_edge_pair &pair : result.pairs) {
            records.push_back(occt_edge_record{pair.image_index, 0, pair.source_index});
        }
        faces.move_into(history);
        edges->records = cocct::copy_out(records);
        edges->count = static_cast<int>(records.size());
        return new occt_shape{result.shell};
    });
}

int occt_offset_limit(const occt_shape *sheet, int sign, double *limit, occt_status *status) {
    return cocct::guarded(status, [&]() -> int {
        occt_initialize();
        if (!sheet || sheet->shape.IsNull()) {
            throw cocct::user_error("This surface can't be used.");
        }
        *limit = cocct::curvature_limit(sheet->shape, sign < 0 ? -1 : 1);
        return 1;
    });
}

int occt_touching_pieces(const occt_shape *sheet, int *touching, occt_status *status) {
    return cocct::guarded(status, [&]() -> int {
        occt_initialize();
        if (!sheet || sheet->shape.IsNull()) {
            throw cocct::user_error("This surface can't be used.");
        }
        *touching = cocct::touching_pieces(sheet->shape) ? 1 : 0;
        return 1;
    });
}

occt_shape *occt_test_wrapped_sheet(double radius, double height, occt_status *status) {
    return cocct::guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        constexpr int kColumns = 8;
        TColgp_Array2OfPnt poles(1, kColumns, 1, 2);
        for (int i = 0; i < kColumns; ++i) {
            // The last column is the first again (the sheet wraps without being periodic).
            const double angle = 2 * cocct::kPi * (i % (kColumns - 1)) / (kColumns - 1);
            for (int j = 0; j < 2; ++j) {
                poles(i + 1, j + 1) = gp_Pnt(radius * std::cos(angle), radius * std::sin(angle), height * j);
            }
        }
        constexpr int kKnots = kColumns - 3 + 1; // poles - degree + 1
        TColStd_Array1OfReal knots_u(1, kKnots);
        TColStd_Array1OfInteger mult_u(1, kKnots);
        for (int i = 1; i <= kKnots; ++i) {
            knots_u(i) = i - 1;
            mult_u(i) = (i == 1 || i == kKnots) ? 4 : 1;
        }
        TColStd_Array1OfReal knots_v(1, 2);
        TColStd_Array1OfInteger mult_v(1, 2);
        knots_v(1) = 0;
        knots_v(2) = 1;
        mult_v(1) = mult_v(2) = 2;
        Handle(Geom_BSplineSurface) surface = new Geom_BSplineSurface(poles, knots_u, knots_v, mult_u, mult_v, 3, 1);
        BRepBuilderAPI_MakeFace face(surface, 1e-7);
        if (!face.IsDone()) {
            throw cocct::user_error("The sheet couldn't be made.");
        }
        return new occt_shape{face.Face()};
    });
}
