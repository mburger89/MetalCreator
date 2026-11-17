#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepBndLib.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepBuilderAPI_FindPlane.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <TopExp_Explorer.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <GCPnts_AbscissaPoint.hxx>
#include <GCPnts_TangentialDeflection.hxx>
#include <GeomAPI_Interpolate.hxx>
#include <GeomAPI_PointsToBSpline.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_Circle.hxx>
#include <Geom_Line.hxx>
#include <Geom_Plane.hxx>
#include <ShapeAnalysis_FreeBounds.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColStd_HArray1OfBoolean.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array1OfVec.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopExp.hxx>
#include <TopTools_HSequenceOfShape.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopoDS_Vertex.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Ax2.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <vector>

using namespace cocct;

namespace {

constexpr double kJoin = 1e-6;
constexpr double kVertexTolerance = 2e-6;

gp_Pnt point_of(const double (&v)[3]) { return gp_Pnt(v[0], v[1], v[2]); }

/// A piece's geometry: the curve, its parameter range and its two ends.
struct PieceCurve {
    Handle(Geom_Curve) curve;
    double first = 0;
    double last = 0;
    gp_Pnt start;
    gp_Pnt end;
};

PieceCurve build_piece(const occt_curve_piece &piece) {
    PieceCurve out;
    switch (piece.kind) {
    case 0: {
        const gp_Pnt a = point_of(piece.a);
        const gp_Pnt b = point_of(piece.b);
        const double length = a.Distance(b);
        if (!(length > kJoin)) {
            throw user_error("A line in the curve has no length.");
        }
        out.curve = new Geom_Line(a, gp_Dir(gp_Vec(a, b)));
        out.first = 0;
        out.last = length;
        out.start = a;
        out.end = b;
        break;
    }
    case 1: {
        const gp_Pnt centre = point_of(piece.a);
        const gp_Pnt start = point_of(piece.c);
        if (!(piece.radius > kJoin) || !std::isfinite(piece.sweep) || std::abs(piece.sweep) <= 1e-12 ||
            std::abs(piece.sweep) > 2 * kPi + 1e-9) {
            throw user_error("An arc in the curve is not valid.");
        }
        if (std::abs(centre.Distance(start) - piece.radius) > kJoin) {
            throw user_error("The arc's start isn't on its circle.");
        }
        gp_Vec normal(piece.b[0], piece.b[1], piece.b[2]);
        if (normal.Magnitude() < 1e-12) {
            throw user_error("An arc in the curve is not valid.");
        }
        if (std::abs(gp_Vec(centre, start).Dot(normal) / normal.Magnitude()) > kJoin) {
            throw user_error("The arc's start isn't on its circle.");
        }
        if (piece.sweep < 0) {
            normal.Reverse();
        }
        const gp_Ax2 frame(centre, gp_Dir(normal), gp_Dir(gp_Vec(centre, start)));
        out.curve = new Geom_Circle(frame, piece.radius);
        out.first = 0;
        out.last = std::min(std::abs(piece.sweep), 2 * kPi);
        out.start = start;
        out.end = out.curve->Value(out.last);
        break;
    }
    default: {
        const int n = piece.pole_count;
        int sum = 0;
        for (int i = 0; i < piece.knot_count; ++i) {
            sum += piece.multiplicities[i];
        }
        if (piece.degree < 1 || n < 2 || piece.knot_count < 2 || sum != n + piece.degree + 1 ||
            piece.multiplicities[0] != piece.degree + 1 || piece.multiplicities[piece.knot_count - 1] != piece.degree + 1) {
            throw user_error("The curve's spline is malformed.");
        }
        for (int i = 1; i + 1 < piece.knot_count; ++i) {
            if (piece.multiplicities[i] > piece.degree) {
                throw user_error("The curve's spline is malformed.");
            }
        }
        TColgp_Array1OfPnt poles(1, n);
        for (int i = 0; i < n; ++i) {
            poles(i + 1) = gp_Pnt(piece.poles[3 * i], piece.poles[3 * i + 1], piece.poles[3 * i + 2]);
        }
        TColStd_Array1OfReal knots(1, piece.knot_count);
        TColStd_Array1OfInteger mults(1, piece.knot_count);
        for (int i = 0; i < piece.knot_count; ++i) {
            knots(i + 1) = piece.knots[i];
            mults(i + 1) = piece.multiplicities[i];
        }
        Handle(Geom_BSplineCurve) spline;
        if (piece.weights) {
            TColStd_Array1OfReal weights(1, n);
            for (int i = 0; i < n; ++i) {
                weights(i + 1) = piece.weights[i];
            }
            spline = new Geom_BSplineCurve(poles, weights, knots, mults, piece.degree);
        } else {
            spline = new Geom_BSplineCurve(poles, knots, mults, piece.degree);
        }
        out.curve = spline;
        out.first = spline->FirstParameter();
        out.last = spline->LastParameter();
        out.start = spline->StartPoint();
        out.end = spline->EndPoint();
        break;
    }
    }
    return out;
}

TopoDS_Vertex vertex_at(const gp_Pnt &p) {
    TopoDS_Vertex v = BRepBuilderAPI_MakeVertex(p);
    BRep_Builder().UpdateVertex(v, kVertexTolerance);
    return v;
}

void require_valid(const TopoDS_Shape &shape) {
    if (!BRepCheck_Analyzer(shape).IsValid()) {
        throw user_error("The curve couldn't be made from these pieces.");
    }
}

TopoDS_Wire wire_of_edge(const TopoDS_Edge &edge) {
    BRepBuilderAPI_MakeWire wire(edge);
    if (!wire.IsDone()) {
        throw user_error("The curve couldn't be built.");
    }
    return wire.Wire();
}

TopoDS_Wire wire_of_curve(const Handle(Geom_Curve) &curve) {
    BRepBuilderAPI_MakeEdge edge(curve);
    if (!edge.IsDone()) {
        throw user_error("The curve couldn't be built.");
    }
    return wire_of_edge(edge.Edge());
}

} // namespace

extern "C" {

occt_shape *occt_make_curve(const occt_curve_piece *pieces, int count, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!pieces || count < 1) {
            throw user_error("A curve needs at least one piece.");
        }
        std::vector<PieceCurve> built;
        built.reserve(count);
        for (int i = 0; i < count; ++i) {
            built.push_back(build_piece(pieces[i]));
        }
        for (int i = 0; i + 1 < count; ++i) {
            if (built[i].end.Distance(built[i + 1].start) > kJoin) {
                throw user_error("The curve's pieces don't join end to end.");
            }
        }
        const bool closed = built.back().end.Distance(built.front().start) <= kJoin;
        std::vector<TopoDS_Vertex> vertices;
        for (int i = 0; i < count; ++i) {
            vertices.push_back(vertex_at(built[i].start));
        }
        vertices.push_back(closed ? vertices.front() : vertex_at(built.back().end));
        BRepBuilderAPI_MakeWire wire;
        for (int i = 0; i < count; ++i) {
            BRepBuilderAPI_MakeEdge edge(built[i].curve, vertices[i], vertices[i + 1], built[i].first, built[i].last);
            if (!edge.IsDone()) {
                throw user_error("The curve couldn't be built.");
            }
            wire.Add(edge.Edge());
            if (!wire.IsDone()) {
                throw user_error("The curve's pieces don't join end to end.");
            }
        }
        require_valid(wire.Wire());
        return new occt_shape{wire.Wire()};
    });
}

occt_shape *occt_interpolate_curve(const double *points, int count, int degree, int closed, const double *start_tangent,
                                   const double *end_tangent, double max_deviation, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!points || count < 2) {
            throw user_error("A curve needs at least two points.");
        }
        Handle(Geom_BSplineCurve) curve;
        if (degree == 3) {
            Handle(TColgp_HArray1OfPnt) array = new TColgp_HArray1OfPnt(1, count);
            for (int i = 0; i < count; ++i) {
                array->SetValue(i + 1, gp_Pnt(points[3 * i], points[3 * i + 1], points[3 * i + 2]));
            }
            GeomAPI_Interpolate interpolation(array, closed != 0, 1e-7);
            if ((start_tangent || end_tangent) && closed) {
                throw user_error("A closed curve can't have end tangents.");
            }
            if (start_tangent || end_tangent) {
                TColgp_Array1OfVec tangents(1, count);
                Handle(TColStd_HArray1OfBoolean) flags = new TColStd_HArray1OfBoolean(1, count);
                flags->Init(Standard_False);
                tangents.Init(gp_Vec(0, 0, 0));
                const auto load = [&](const double *t, int slot) {
                    if (!t) {
                        return;
                    }
                    const gp_Vec v(t[0], t[1], t[2]);
                    if (!(v.Magnitude() > 1e-12)) {
                        throw user_error("A tangent can't be zero.");
                    }
                    tangents(slot) = v;
                    flags->SetValue(slot, Standard_True);
                };
                load(start_tangent, 1);
                load(end_tangent, count);
                interpolation.Load(tangents, flags, Standard_True);
            }
            interpolation.Perform();
            if (!interpolation.IsDone()) {
                throw user_error("The curve can't pass through these points.");
            }
            curve = interpolation.Curve();
        } else if (degree == 5) {
            if (closed || start_tangent || end_tangent) {
                throw user_error("A degree-5 curve can't be closed or have end tangents.");
            }
            TColgp_Array1OfPnt array(1, count);
            for (int i = 0; i < count; ++i) {
                array(i + 1) = gp_Pnt(points[3 * i], points[3 * i + 1], points[3 * i + 2]);
            }
            GeomAPI_PointsToBSpline fit(array, 5, 5, GeomAbs_C2, 1e-7);
            if (!fit.IsDone()) {
                throw user_error("The curve can't pass through these points at degree 5; try degree 3.");
            }
            curve = fit.Curve();
            for (int i = 0; i < count; ++i) {
                GeomAPI_ProjectPointOnCurve projection(array(i + 1), curve);
                const double gap = projection.NbPoints() > 0 ? projection.LowerDistance() : 1e300;
                if (!(gap <= max_deviation)) {
                    throw user_error("The curve can't pass through these points at degree 5; try degree 3.");
                }
            }
        } else {
            throw user_error("The curve's degree must be 3 or 5.");
        }
        return new occt_shape{wire_of_curve(curve)};
    });
}

int occt_curve_info_of(const occt_shape *wire, occt_curve_info *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_curve_info{};
        const TopoDS_Shape &shape = wire->shape;
        if (shape.IsNull() || shape.ShapeType() != TopAbs_WIRE) {
            throw user_error("This isn't a curve.");
        }
        std::vector<gp_Pnt> points;
        double length = 0;
        int pieces = 0;
        gp_Pnt first_point;
        gp_Pnt last_point;
        for (BRepTools_WireExplorer explorer(TopoDS::Wire(shape)); explorer.More(); explorer.Next()) {
            const TopoDS_Edge edge = explorer.Current();
            BRepAdaptor_Curve adaptor(edge);
            const double a = adaptor.FirstParameter();
            const double b = adaptor.LastParameter();
            length += GCPnts_AbscissaPoint::Length(adaptor, a, b);
            GCPnts_TangentialDeflection sampler(adaptor, a, b, 0.5, 0.01, 2);
            std::vector<gp_Pnt> edge_points;
            for (int i = 1; i <= sampler.NbPoints(); ++i) {
                edge_points.push_back(sampler.Value(i));
            }
            if (edge.Orientation() == TopAbs_REVERSED) {
                std::reverse(edge_points.begin(), edge_points.end());
            }
            if (pieces == 0) {
                first_point = edge_points.front();
                points.push_back(edge_points.front());
            }
            points.insert(points.end(), edge_points.begin() + 1, edge_points.end());
            last_point = edge_points.back();
            ++pieces;
        }
        if (pieces == 0) {
            throw user_error("The curve is empty.");
        }
        out->piece_count = pieces;
        out->length = length;
        out->is_closed = first_point.Distance(last_point) <= kJoin ? 1 : 0;
        Bnd_Box box;
        BRepBndLib::AddOptimal(shape, box, Standard_False, Standard_False);
        box.Get(out->min[0], out->min[1], out->min[2], out->max[0], out->max[1], out->max[2]);
        BRepBuilderAPI_FindPlane finder(shape, 1e-7);
        if (finder.Found()) {
            const gp_Pln plane = finder.Plane()->Pln();
            out->planar = 1;
            const gp_Pnt o = plane.Location();
            const gp_Dir n = plane.Axis().Direction();
            const gp_Dir x = plane.XAxis().Direction();
            out->plane_origin[0] = o.X(); out->plane_origin[1] = o.Y(); out->plane_origin[2] = o.Z();
            out->plane_normal[0] = n.X(); out->plane_normal[1] = n.Y(); out->plane_normal[2] = n.Z();
            out->plane_x[0] = x.X(); out->plane_x[1] = x.Y(); out->plane_x[2] = x.Z();
        }
        out->polyline_count = static_cast<int>(points.size());
        out->polyline = static_cast<double *>(std::malloc(sizeof(double) * 3 * points.size()));
        if (!out->polyline) {
            throw std::bad_alloc();
        }
        for (size_t i = 0; i < points.size(); ++i) {
            out->polyline[3 * i] = points[i].X();
            out->polyline[3 * i + 1] = points[i].Y();
            out->polyline[3 * i + 2] = points[i].Z();
        }
        return 1;
    });
}

void occt_curve_info_free(occt_curve_info *info) {
    if (info) {
        std::free(info->polyline);
        info->polyline = nullptr;
        info->polyline_count = 0;
    }
}

occt_shape *occt_curves_from_edges(const occt_shape *shape, const int *edge_indices, int count, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        const TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        Handle(TopTools_HSequenceOfShape) input = new TopTools_HSequenceOfShape();
        for (int i = 0; i < count; ++i) {
            if (edge_indices[i] < 1 || edge_indices[i] > edges.Extent()) {
                throw user_error("That edge no longer exists.");
            }
            input->Append(edges(edge_indices[i]));
        }
        Handle(TopTools_HSequenceOfShape) wires;
        ShapeAnalysis_FreeBounds::ConnectEdgesToWires(input, kJoin, Standard_True, wires);
        if (wires.IsNull() || wires->Length() == 0) {
            throw user_error("These edges don't make a curve.");
        }
        // Order by each wire's lowest edge index in the solid's edge map.
        std::vector<std::pair<int, TopoDS_Shape>> ordered;
        for (int w = 1; w <= wires->Length(); ++w) {
            const TopoDS_Shape &wire = wires->Value(w);
            int lowest = edges.Extent() + 1;
            for (TopExp_Explorer it(wire, TopAbs_EDGE); it.More(); it.Next()) {
                const int index = edges.FindIndex(it.Current());
                if (index < 1) {
                    throw user_error("The curve couldn't be made from these pieces.");
                }
                lowest = std::min(lowest, index);
            }
            ordered.emplace_back(lowest, wire);
        }
        std::stable_sort(ordered.begin(), ordered.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
        TopoDS_Compound compound;
        BRep_Builder builder;
        builder.MakeCompound(compound);
        for (const auto &entry : ordered) {
            require_valid(entry.second);
            builder.Add(compound, entry.second);
        }
        return new occt_shape{compound};
    });
}

int occt_compound_child_count(const occt_shape *compound) {
    return queried([&]() -> int {
        int n = 0;
        for (TopoDS_Iterator it(compound->shape); it.More(); it.Next()) {
            ++n;
        }
        return n;
    });
}

occt_shape *occt_compound_child(const occt_shape *compound, int index, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        int n = 0;
        for (TopoDS_Iterator it(compound->shape); it.More(); it.Next(), ++n) {
            if (n == index) {
                return new occt_shape{it.Value()};
            }
        }
        throw user_error("That piece doesn't exist.");
    });
}

int occt_test_curve_spline_info(const occt_shape *wire, int *degree, int *pole_count, occt_status *status) {
    return guarded(status, [&]() -> int {
        TopExp_Explorer it(wire->shape, TopAbs_EDGE);
        if (!it.More()) {
            throw user_error("The curve is empty.");
        }
        BRepAdaptor_Curve adaptor(TopoDS::Edge(it.Current()));
        if (adaptor.GetType() != GeomAbs_BSplineCurve) {
            throw user_error("The first piece isn't a spline.");
        }
        const Handle(Geom_BSplineCurve) spline = adaptor.BSpline();
        *degree = spline->Degree();
        *pole_count = spline->NbPoles();
        return 1;
    });
}

double occt_test_curve_distance(const occt_shape *wire, double x, double y, double z, occt_status *status) {
    return guarded(status, [&]() -> double {
        const TopoDS_Vertex vertex = BRepBuilderAPI_MakeVertex(gp_Pnt(x, y, z));
        BRepExtrema_DistShapeShape distance(wire->shape, vertex);
        if (!distance.IsDone()) {
            throw user_error("The distance couldn't be measured.");
        }
        return distance.Value();
    });
}

} // extern "C"
