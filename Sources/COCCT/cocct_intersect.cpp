// Where two bodies meet (NURBS spec, NS-4 Task 6; ruling R14).
//
// `BRepAlgoAPI_Section` gives the exact common edges of the two shapes (no approximation). They are chained into wires within 1e-6 mm,
// each wire is turned and started so that it begins at its lexicographically smaller end (an open one) or its lexicographically
// smallest vertex (a closed one), and the wires are ordered by that start point. Points compare by x, then y, then z, a coordinate
// counting as equal within 1e-6 mm, so the order survives a common move of both bodies.

#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAlgoAPI_Section.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <BRep_Builder.hxx>
#include <ShapeAnalysis_FreeBounds.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopExp_Explorer.hxx>
#include <TopTools_HSequenceOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Pnt.hxx>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace cocct;

namespace {

constexpr double kJoinTolerance = 1e-6;

/// True when `a` comes before `b`: by x, then y, then z, a coordinate within the tolerance of the other counting as equal.
bool precedes(const gp_Pnt &a, const gp_Pnt &b) {
    const double da[3] = {a.X(), a.Y(), a.Z()};
    const double db[3] = {b.X(), b.Y(), b.Z()};
    for (int i = 0; i < 3; ++i) {
        if (std::abs(da[i] - db[i]) > kJoinTolerance) {
            return da[i] < db[i];
        }
    }
    return false;
}

struct Oriented {
    TopoDS_Edge edge;
    gp_Pnt start;
    gp_Pnt end;
};

gp_Pnt edge_point(const TopoDS_Edge &edge, bool at_start) {
    BRepAdaptor_Curve curve(edge);
    const bool reversed = edge.Orientation() == TopAbs_REVERSED;
    return curve.Value(at_start != reversed ? curve.FirstParameter() : curve.LastParameter());
}

/// The wire's edges in wire order, each with its start and end as the wire runs through it.
std::vector<Oriented> oriented_edges(const TopoDS_Wire &wire) {
    std::vector<Oriented> edges;
    for (BRepTools_WireExplorer explorer(wire); explorer.More(); explorer.Next()) {
        const TopoDS_Edge edge = explorer.Current();
        edges.push_back({edge, edge_point(edge, true), edge_point(edge, false)});
    }
    return edges;
}

TopoDS_Wire rebuilt(const std::vector<Oriented> &edges) {
    BRepBuilderAPI_MakeWire maker;
    for (const Oriented &entry : edges) {
        maker.Add(entry.edge);
        if (!maker.IsDone()) {
            throw user_error("An intersection curve couldn't be made from its pieces.");
        }
    }
    return maker.Wire();
}

struct Curve {
    TopoDS_Wire wire;
    gp_Pnt start;
};

Curve normalized(const TopoDS_Wire &wire) {
    std::vector<Oriented> edges = oriented_edges(wire);
    if (edges.empty()) {
        throw user_error("An intersection curve couldn't be made from its pieces.");
    }
    const bool closed = edges.front().start.Distance(edges.back().end) <= kJoinTolerance;
    if (closed) {
        // Start at the edge whose start is the lexicographically smallest vertex (the first one on a tie).
        size_t best = 0;
        for (size_t i = 1; i < edges.size(); ++i) {
            if (precedes(edges[i].start, edges[best].start)) {
                best = i;
            }
        }
        if (best == 0) {
            return {wire, edges.front().start};
        }
        std::rotate(edges.begin(), edges.begin() + static_cast<std::ptrdiff_t>(best), edges.end());
    } else if (precedes(edges.back().end, edges.front().start)) {
        std::reverse(edges.begin(), edges.end());
        for (Oriented &entry : edges) {
            entry.edge.Reverse();
            std::swap(entry.start, entry.end);
        }
    } else {
        return {wire, edges.front().start};
    }
    return {rebuilt(edges), edges.front().start};
}

}  // namespace

occt_shape *occt_intersection_curves(const occt_shape *a, const occt_shape *b, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (a->shape.IsSame(b->shape)) {
            throw user_error("Intersection Curves needs two different bodies.");
        }
        BRepAlgoAPI_Section section(a->shape, b->shape, Standard_False);
        section.Approximation(Standard_False);
        section.Build();
        if (!section.IsDone()) {
            throw user_error("The bodies' intersection couldn't be found.");
        }
        Handle(TopTools_HSequenceOfShape) input = new TopTools_HSequenceOfShape();
        for (TopExp_Explorer it(section.Shape(), TopAbs_EDGE); it.More(); it.Next()) {
            input->Append(it.Current());
        }
        std::vector<Curve> curves;
        if (input->Length() > 0) {
            Handle(TopTools_HSequenceOfShape) wires;
            ShapeAnalysis_FreeBounds::ConnectEdgesToWires(input, kJoinTolerance, Standard_False, wires);
            if (!wires.IsNull()) {
                for (int i = 1; i <= wires->Length(); ++i) {
                    curves.push_back(normalized(TopoDS::Wire(wires->Value(i))));
                }
            }
        }
        std::stable_sort(curves.begin(), curves.end(), [](const Curve &x, const Curve &y) { return precedes(x.start, y.start); });
        TopoDS_Compound compound;
        BRep_Builder builder;
        builder.MakeCompound(compound);
        for (const Curve &curve : curves) {
            if (!BRepCheck_Analyzer(curve.wire).IsValid()) {
                throw user_error("An intersection curve couldn't be made from its pieces.");
            }
            builder.Add(compound, curve.wire);
        }
        return new occt_shape{compound};
    });
}
