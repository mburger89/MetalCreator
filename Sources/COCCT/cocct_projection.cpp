// Hidden-line projection through HLRBRep_Algo (drawings DR-1, R9 and R10). The shim reads HLRBRep_Data per edge, and the source of
// every line is found by shape identity (IsSame) only, never by index order.
#include "cocct_internal.hpp"
#include "cocct_sheet.hpp"

#include <BRepGProp_Face.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <Geom2d_Curve.hxx>
#include <BRep_Builder.hxx>
#include <GeomAbs_CurveType.hxx>
#include <HLRAlgo_EdgeIterator.hxx>
#include <HLRAlgo_EdgeStatus.hxx>
#include <HLRAlgo_Projector.hxx>
#include <HLRBRep_Algo.hxx>
#include <HLRBRep_Curve.hxx>
#include <HLRBRep_Data.hxx>
#include <HLRBRep_EdgeData.hxx>
#include <HLRBRep_ShapeBounds.hxx>
#include <HLRTopoBRep_Data.hxx>
#include <HLRTopoBRep_OutLiner.hxx>
#include <TopTools_DataMapOfShapeInteger.hxx>
#include <TopTools_DataMapOfShapeShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopTools_MapOfShape.hxx>
#include <gp_Ax2.hxx>
#include <gp_Circ2d.hxx>
#include <gp_Dir.hxx>
#include <gp_Elips2d.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace cocct;

namespace {

constexpr double kTwoPi = 2 * kPi;

bool finite3(const double v[3]) {
    return std::isfinite(v[0]) && std::isfinite(v[1]) && std::isfinite(v[2]);
}

/// The angle in [0, 2 pi) counter-clockwise from `from` to `to`.
double ccw(double from, double to) {
    double d = std::fmod(to - from, kTwoPi);
    if (d < 0) {
        d += kTwoPi;
    }
    return d;
}

/// What a line of the result is sourced from and how it is classified (before the geometry is read).
struct Source {
    int kind = -1; // 0 edge, 1 face, 2 curve
    int index = -1;
    int piece = 0;
    int line_class = 0;
};

/// One shape given to HLR with the maps that resolve its edges.
struct Input {
    bool is_solid = false;
    int curve_index = -1;
    TopoDS_Shape shape;
    TopTools_IndexedMapOfShape edges;   // the input's own edges (solid: the kernel's order; curve: the wire's pieces)
    TopTools_IndexedMapOfShape faces;
    TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
    TopTools_DataMapOfShapeShape piece_owner;       // split piece -> the edge it came from
    TopTools_DataMapOfShapeInteger outline_face;    // outline edge -> 0-based face
    TopTools_MapOfShape dropped;                    // internal and iso lines
    TopTools_DataMapOfShapeInteger piece_of_curve;  // curve edge -> place in its wire (curves)
};

/// Step 1 of R10: a piece the outliner cut out of an edge resolves to that edge.
void record_pieces(HLRTopoBRep_Data &data, const TopoDS_Shape &owner, TopTools_DataMapOfShapeShape &piece_owner) {
    if (owner.ShapeType() != TopAbs_EDGE) {
        return;
    }
    const TopoDS_Edge edge = TopoDS::Edge(owner);
    if (!data.EdgeHasSplE(edge)) {
        return;
    }
    for (TopTools_ListOfShape::Iterator it(data.EdgeSplE(edge)); it.More(); it.Next()) {
        if (!piece_owner.IsBound(it.Value())) {
            piece_owner.Bind(it.Value(), owner);
        }
    }
}

void index_input(Input &input, HLRTopoBRep_Data &data) {
    // Input edges that were split.
    for (int i = 1; i <= input.edges.Extent(); ++i) {
        record_pieces(data, input.edges(i), input.piece_owner);
    }
    // Outlines, internal lines and iso lines per face; their own split pieces resolve to them.
    for (int i = 1; i <= input.faces.Extent(); ++i) {
        const TopoDS_Face face = TopoDS::Face(input.faces(i));
        if (data.FaceHasOutL(face)) {
            for (TopTools_ListOfShape::Iterator it(data.FaceOutL(face)); it.More(); it.Next()) {
                if (!input.outline_face.IsBound(it.Value())) {
                    input.outline_face.Bind(it.Value(), i - 1);
                }
                record_pieces(data, it.Value(), input.piece_owner);
            }
        }
        // The spike's finding (R10 erratum): FaceIntL holds the silhouette lines that run across a face's interior, such as a
        // cylinder's two sides, so it is an outline like FaceOutL; only the iso lines are dropped.
        if (data.FaceHasIntL(face)) {
            for (TopTools_ListOfShape::Iterator it(data.FaceIntL(face)); it.More(); it.Next()) {
                if (!input.outline_face.IsBound(it.Value())) {
                    input.outline_face.Bind(it.Value(), i - 1);
                }
                record_pieces(data, it.Value(), input.piece_owner);
            }
        }
        if (data.FaceHasIsoL(face)) {
            for (TopTools_ListOfShape::Iterator it(data.FaceIsoL(face)); it.More(); it.Next()) {
                input.dropped.Add(it.Value());
                record_pieces(data, it.Value(), input.piece_owner);
            }
        }
    }
}

/// Whether the seam `edge` of `face` lies on the face's silhouette: the face's normal is square to the way the viewer looks all along it.
/// HLR draws such a seam as the silhouette itself, so it is the face's outline and not a seam to drop.
bool seam_is_silhouette(const TopoDS_Edge &edge, const TopoDS_Face &face, const gp_Vec &view) {
    Standard_Real first = 0, last = 0;
    const Handle(Geom2d_Curve) pcurve = BRep_Tool::CurveOnSurface(edge, face, first, last);
    if (pcurve.IsNull()) {
        return false;
    }
    const BRepGProp_Face properties(face);
    for (const double t : {0.1, 0.3, 0.5, 0.7, 0.9}) {
        gp_Pnt2d uv;
        pcurve->D0(first + t * (last - first), uv);
        gp_Pnt point;
        gp_Vec normal;
        properties.Normal(uv.X(), uv.Y(), point, normal);
        if (normal.Magnitude() < 1e-12 || std::abs(normal.Normalized().Dot(view)) > 1e-7) {
            return false;
        }
    }
    return true;
}

/// R10's five steps. Returns false when the line is dropped (a seam, an internal or iso line, a degenerate edge).
bool resolve(const Input &input, HLRTopoBRep_Data &data, const TopoDS_Shape &shape, const HLRBRep_EdgeData &ed, const gp_Vec &view,
             Source &out) {
    TopoDS_Shape resolved = shape;
    if (input.piece_owner.IsBound(shape)) {
        resolved = input.piece_owner.Find(shape);
    } else {
        const TopoDS_Shape old = data.NewSOldS(shape);
        if (!old.IsNull() && (input.edges.Contains(old) || input.outline_face.IsBound(old))) {
            resolved = old;
        }
    }
    if (!input.is_solid) {
        out.kind = 2;
        out.index = input.curve_index;
        out.line_class = 4;
        if (input.piece_of_curve.IsBound(resolved)) {
            out.piece = input.piece_of_curve.Find(resolved);
        }
        return true;
    }
    if (input.edges.Contains(resolved)) {
        const TopoDS_Edge edge = TopoDS::Edge(resolved);
        if (BRep_Tool::Degenerated(edge)) {
            return false;
        }
        const std::vector<TopoDS_Face> adjacent = distinct_faces(edge, input.edge_faces);
        if (adjacent.size() == 1 && BRep_Tool::IsClosed(edge, adjacent[0])) {
            // A seam is dropped, unless it lies on the silhouette, where HLR draws it as the face's outline.
            if (!seam_is_silhouette(edge, adjacent[0], view)) {
                return false;
            }
            out.kind = 1;
            out.index = input.faces.FindIndex(adjacent[0]) - 1;
            out.line_class = 2;
            return true;
        }
        out.kind = 0;
        out.index = input.edges.FindIndex(resolved) - 1;
        out.line_class = (ed.Rg1Line() || ed.RgNLine()) ? 1 : 0;
        return true;
    }
    if (input.outline_face.IsBound(resolved)) {
        out.kind = 1;
        out.index = input.outline_face.Find(resolved);
        out.line_class = 2;
        return true;
    }
    if (input.dropped.Contains(resolved)) {
        return false;
    }
    out.kind = -1;
    out.index = -1;
    out.line_class = ed.OutLVSta() ? 2 : ((ed.Rg1Line() || ed.RgNLine()) ? 1 : 0);
    return true;
}

struct Builder {
    std::vector<occt_projected_line> lines;
    std::vector<double> points;
    double tolerance = 0.01;
};

void set_source(occt_projected_line &line, const Source &source, int visibility) {
    line.visibility = visibility;
    line.line_class = source.line_class;
    line.source_kind = source.kind;
    line.source_index = source.index;
    line.source_piece = source.piece;
}

gp_Pnt2d at(const HLRBRep_Curve &curve, double u) {
    gp_Pnt2d p;
    curve.D0(u, p);
    return p;
}

/// Points of the curve between `a` and `b`, bisected until the chord misses the curve by less than `tolerance` at its middle and
/// its quarter points (never fewer than 8 pieces, so a curve that returns to the chord is caught).
void sample(const HLRBRep_Curve &curve, double a, double b, double tolerance, int depth, const gp_Pnt2d &pa, const gp_Pnt2d &pb,
            std::vector<gp_Pnt2d> &out) {
    const double m = 0.5 * (a + b);
    const gp_Pnt2d pm = at(curve, m);
    bool split = depth < 3;
    if (!split && depth < 16) {
        const gp_Pnt2d p1 = at(curve, 0.5 * (a + m));
        const gp_Pnt2d p3 = at(curve, 0.5 * (m + b));
        const gp_Vec2d chord(pa, pb);
        const double length = chord.Magnitude();
        auto miss = [&](const gp_Pnt2d &p) {
            if (length < 1e-12) {
                return pa.Distance(p);
            }
            return std::abs(chord.Crossed(gp_Vec2d(pa, p))) / length;
        };
        split = miss(pm) > tolerance || miss(p1) > tolerance || miss(p3) > tolerance;
    }
    if (split) {
        sample(curve, a, m, tolerance, depth + 1, pa, pm, out);
        sample(curve, m, b, tolerance, depth + 1, pm, pb, out);
    } else {
        out.push_back(pb);
    }
}

void emit_polyline(Builder &builder, const HLRBRep_Curve &curve, double a, double b, const Source &source, int visibility) {
    std::vector<gp_Pnt2d> pts;
    const gp_Pnt2d pa = at(curve, a);
    const gp_Pnt2d pb = at(curve, b);
    pts.push_back(pa);
    sample(curve, a, b, builder.tolerance, 0, pa, pb, pts);
    double extent = 0;
    for (const gp_Pnt2d &p : pts) {
        extent = std::max(extent, pa.Distance(p));
    }
    if (extent < 1e-9) {
        return;
    }
    occt_projected_line line{};
    set_source(line, source, visibility);
    line.geometry = 3;
    line.point_offset = static_cast<int>(builder.points.size() / 2);
    line.point_count = static_cast<int>(pts.size());
    for (const gp_Pnt2d &p : pts) {
        builder.points.push_back(p.X());
        builder.points.push_back(p.Y());
    }
    builder.lines.push_back(line);
}

/// A conic's sweep: the direction is read at a quarter of the interval (a sample is never ambiguous there) and the size at its end.
template <typename Angle>
double conic_sweep(const HLRBRep_Curve &curve, double a, double b, Angle angle_of) {
    const double ts = angle_of(at(curve, a));
    const double tq = angle_of(at(curve, a + 0.25 * (b - a)));
    const double te = angle_of(at(curve, b));
    const bool closed = at(curve, a).Distance(at(curve, b)) < 1e-9;
    const double to_end = ccw(ts, te);
    const double to_quarter = ccw(ts, tq);
    if (closed) {
        return to_quarter < kPi ? kTwoPi : -kTwoPi;
    }
    return to_quarter < to_end ? to_end : to_end - kTwoPi;
}

void emit_interval(Builder &builder, const HLRBRep_Curve &curve, double a, double b, const Source &source, int visibility) {
    if (!(b - a > 1e-12)) {
        return;
    }
    const GeomAbs_CurveType type = curve.GetType();
    if (type == GeomAbs_Line) {
        const gp_Pnt2d pa = at(curve, a);
        const gp_Pnt2d pb = at(curve, b);
        if (pa.Distance(pb) < 1e-9) {
            return;
        }
        occt_projected_line line{};
        set_source(line, source, visibility);
        line.geometry = 0;
        line.numbers[0] = pa.X();
        line.numbers[1] = pa.Y();
        line.numbers[2] = pb.X();
        line.numbers[3] = pb.Y();
        builder.lines.push_back(line);
        return;
    }
    if (type == GeomAbs_Circle) {
        const gp_Circ2d circle = curve.Circle();
        const gp_Pnt2d c = circle.Location();
        const double r = circle.Radius();
        if (r < 1e-9) {
            return;
        }
        auto angle_of = [&](const gp_Pnt2d &p) { return std::atan2(p.Y() - c.Y(), p.X() - c.X()); };
        occt_projected_line line{};
        set_source(line, source, visibility);
        line.geometry = 1;
        line.numbers[0] = c.X();
        line.numbers[1] = c.Y();
        line.numbers[2] = r;
        line.numbers[3] = angle_of(at(curve, a));
        line.numbers[4] = conic_sweep(curve, a, b, angle_of);
        builder.lines.push_back(line);
        return;
    }
    if (type == GeomAbs_Ellipse) {
        const gp_Elips2d ellipse = curve.Ellipse();
        const double major = ellipse.MajorRadius();
        const double minor = ellipse.MinorRadius();
        if (minor > 1e-9 * std::max(1.0, major)) {
            const gp_Pnt2d c = ellipse.Location();
            const gp_Dir2d x = ellipse.XAxis().Direction();
            // The minor axis is the major turned a quarter counter-clockwise, as the Swift side reads it: OCCT's own YAxis
            // is reversed when the circle's axis points away from the viewer.
            const gp_Dir2d y(-x.Y(), x.X());
            auto angle_of = [&](const gp_Pnt2d &p) {
                const gp_Vec2d d(c, p);
                return std::atan2(d.Dot(gp_Vec2d(y)) / minor, d.Dot(gp_Vec2d(x)) / major);
            };
            occt_projected_line line{};
            set_source(line, source, visibility);
            line.geometry = 2;
            line.numbers[0] = c.X();
            line.numbers[1] = c.Y();
            line.numbers[2] = x.X();
            line.numbers[3] = x.Y();
            line.numbers[4] = major;
            line.numbers[5] = minor;
            line.numbers[6] = angle_of(at(curve, a));
            line.numbers[7] = conic_sweep(curve, a, b, angle_of);
            builder.lines.push_back(line);
            return;
        }
        // An ellipse seen edge on is a segment run twice over: a polyline holds it exactly.
    }
    emit_polyline(builder, curve, a, b, source, visibility);
}

} // namespace

extern "C" {

int occt_projection(const occt_shape *solid, const occt_shape *const *curves, int curve_count, const double direction[3],
                    const double up[3], double tolerance, const occt_cancel *cancel, occt_projection_result *out,
                    occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_projection_result{};
        if (!finite3(direction) || !finite3(up) || !std::isfinite(tolerance) || tolerance <= 0) {
            throw user_error("The projection direction and tolerance must be finite and positive.");
        }
        const gp_Vec view(direction[0], direction[1], direction[2]);
        const gp_Vec upward(up[0], up[1], up[2]);
        if (view.Magnitude() < 1e-12 || upward.Magnitude() < 1e-12) {
            throw user_error("The projection direction can't be zero.");
        }
        const gp_Dir d(view);
        const gp_Dir u(upward);
        const gp_Vec right = gp_Vec(d).Crossed(gp_Vec(u));
        if (right.Magnitude() < 1e-9) {
            throw user_error("The view direction and its up direction can't be parallel.");
        }
        // The main direction of the system points at the viewer, so it is minus the way the viewer looks.
        const HLRAlgo_Projector projector(gp_Ax2(gp_Pnt(0, 0, 0), gp_Dir(-d.X(), -d.Y(), -d.Z()), gp_Dir(right)));
        {
            gp_Pnt2d p;
            projector.Project(gp_Pnt(right.X() / right.Magnitude(), right.Y() / right.Magnitude(), right.Z() / right.Magnitude()), p);
            gp_Pnt2d q;
            projector.Project(gp_Pnt(u.X(), u.Y(), u.Z()), q);
            if (p.X() < 0.99 || std::abs(p.Y()) > 1e-6 || q.Y() < 0.99 || std::abs(q.X()) > 1e-6) {
                throw user_error("The projector's axes disagree with the requested frame.");
            }
        }

        const bool has_solid = solid != nullptr && !solid->shape.IsNull();
        std::vector<Input> inputs;
        if (has_solid) {
            Input input;
            input.is_solid = true;
            input.shape = solid->shape;
            TopExp::MapShapes(input.shape, TopAbs_EDGE, input.edges);
            TopExp::MapShapes(input.shape, TopAbs_FACE, input.faces);
            TopExp::MapShapesAndAncestors(input.shape, TopAbs_EDGE, TopAbs_FACE, input.edge_faces);
            inputs.push_back(std::move(input));
        }
        for (int k = 0; k < curve_count; ++k) {
            if (curves[k] == nullptr || curves[k]->shape.IsNull()) {
                continue;
            }
            Input input;
            input.curve_index = k;
            input.shape = curves[k]->shape;
            int piece = 0;
            if (input.shape.ShapeType() == TopAbs_WIRE) {
                for (BRepTools_WireExplorer explorer(TopoDS::Wire(input.shape)); explorer.More(); explorer.Next()) {
                    input.piece_of_curve.Bind(explorer.Current(), piece++);
                }
            } else if (input.shape.ShapeType() == TopAbs_EDGE) {
                input.piece_of_curve.Bind(input.shape, 0);
            }
            inputs.push_back(std::move(input));
        }
        if (inputs.empty()) {
            return 1;
        }

        Handle(HLRBRep_Algo) algo = new HLRBRep_Algo();
        for (const Input &input : inputs) {
            algo->Add(input.shape);
        }
        algo->Projector(projector);
        poll(cancel);
        algo->Update();
        poll(cancel);
        algo->Hide();
        poll(cancel);

        Handle(HLRBRep_Data) data = algo->DataStructure();
        if (data.IsNull() || algo->NbShapes() != static_cast<int>(inputs.size())) {
            throw user_error("The hidden-line algorithm gave no result.");
        }
        Builder builder;
        builder.tolerance = tolerance;
        int edges_read = 0;
        for (int s = 0; s < static_cast<int>(inputs.size()); ++s) {
            HLRBRep_ShapeBounds &bounds = algo->ShapeBounds(s + 1);
            HLRTopoBRep_Data &topo = bounds.Shape()->DataStructure();
            index_input(inputs[s], topo);
            int v1, v2, e1, e2, f1, f2;
            bounds.Bounds(v1, v2, e1, e2, f1, f2);
            for (int e = e1; e <= e2; ++e) {
                if ((++edges_read & 63) == 0) {
                    poll(cancel);
                }
                HLRBRep_EdgeData &ed = data->EDataArray().ChangeValue(e);
                Source source;
                if (!resolve(inputs[s], topo, data->EdgeMap()(e), ed, gp_Vec(d), source)) {
                    continue;
                }
                const HLRBRep_Curve &curve = ed.Geometry();
                double start = 0, end = 0;
                Standard_ShortReal tol_start = 0, tol_end = 0;
                HLRAlgo_EdgeIterator it;
                for (it.InitVisible(ed.Status()); it.MoreVisible(); it.NextVisible()) {
                    it.Visible(start, tol_start, end, tol_end);
                    emit_interval(builder, curve, start, end, source, 0);
                }
                for (it.InitHidden(ed.Status()); it.MoreHidden(); it.NextHidden()) {
                    it.Hidden(start, tol_start, end, tol_end);
                    emit_interval(builder, curve, start, end, source, 1);
                }
            }
        }
        out->line_count = static_cast<int>(builder.lines.size());
        out->lines = copy_out(builder.lines);
        out->point_count = static_cast<int>(builder.points.size() / 2);
        out->points = copy_out(builder.points);
        return 1;
    });
}

void occt_projection_free(occt_projection_result *result) {
    if (result == nullptr) {
        return;
    }
    std::free(result->lines);
    std::free(result->points);
    *result = occt_projection_result{};
}

} // extern "C"
