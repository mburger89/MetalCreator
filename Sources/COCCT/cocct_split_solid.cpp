// Dividing a closed solid with surfaces or other solids (NURBS spec, NS-5 Task 7; rulings R13 and R15).
//
// `BRepAlgoAPI_Splitter` divides the solid by every face of every tool. A tool face that doesn't cross the solid from side to side is left
// inside one piece (an internal face) or ends on it, so the solid is divided a second time by the cut faces that do separate two pieces
// (the same way Trim drops a cut that ends inside a face). Each piece then reports, for each of its faces, the face it came from and the
// (element, side) pairs of the tool faces it borders or is made from. A side is decided locally, by the oriented normal of the tool face
// against the direction the piece lies in, so a face of a piece that is shared with its neighbour is named once per piece.

#include "cocct_sheet.hpp"
#include "cocct_splitter.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepGProp.hxx>
#include <BRepGProp_Face.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <GProp_GProps.hxx>
#include <Geom2d_Curve.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopoDS_Vertex.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cstdlib>
#include <vector>

using namespace cocct;

namespace {

constexpr const char *kFailure = "The tools couldn't divide this solid.";
constexpr const char *kNoCut = "The tools don't cut the solid into pieces.";
constexpr double kNameTolerance = 1e-3;

enum split_side { kFront = 0, kBack = 1, kInsideSide = 2, kOutsideSide = 3 };

/// One face of a tool: an element of the cut.
struct ToolFace {
    TopoDS_Face face;
    int operand = 0;
    int index = 0;
    bool closed = false;
};

/// What a run of the splitter made, face by face (the faces of `run.whole` in its map order).
struct Cuts {
    TopTools_IndexedMapOfShape faces;
    /// The 1-based face of the divided solid each face came from, 0 for a cut face.
    std::vector<int> source;
    /// The tool face (element) each cut face lies on, -1 when none.
    std::vector<int> element;
    /// The cut faces that separate two solids.
    TopTools_ListOfShape dividing;
    /// Whether some cut face doesn't.
    bool dangling = false;
};

int side_of(bool closed, bool on_normal_side) {
    if (closed) {
        return on_normal_side ? kOutsideSide : kInsideSide;
    }
    return on_normal_side ? kFront : kBack;
}

/// The oriented normal of `tool` at the point of it nearest `point`.
bool tool_normal(const gp_Pnt &point, const TopoDS_Face &tool, gp_Vec &normal) {
    const TopoDS_Vertex vertex = BRepBuilderAPI_MakeVertex(point);
    BRepExtrema_DistShapeShape distance(vertex, tool);
    if (!distance.IsDone() || distance.NbSolution() < 1) {
        return false;
    }
    double u = 0;
    double v = 0;
    if (distance.SupportTypeShape2(1) == BRepExtrema_IsInFace) {
        distance.ParOnFaceS2(1, u, v);
    } else {
        GeomAPI_ProjectPointOnSurf projector(point, BRep_Tool::Surface(tool));
        if (!projector.IsDone() || projector.NbPoints() < 1) {
            return false;
        }
        projector.LowerDistanceParameters(u, v);
    }
    BRepGProp_Face properties(tool);
    gp_Pnt unused;
    properties.Normal(u, v, unused, normal);
    return normal.Magnitude() > 1e-12;
}

/// `shape`'s solids, shells and faces, each its own tool (compounds opened, a solid or shell kept whole).
void append_members(const TopoDS_Shape &shape, TopTools_ListOfShape &list) {
    if (shape.ShapeType() != TopAbs_COMPOUND) {
        list.Append(shape);
        return;
    }
    for (TopoDS_Iterator it(shape); it.More(); it.Next()) {
        append_members(it.Value(), list);
    }
}

Cuts analyse(const SplitRun &run, const TopTools_IndexedMapOfShape &input_faces, const std::vector<ToolFace> &elements,
             const occt_cancel *cancel) {
    Cuts cuts;
    cuts.faces = map_of(run.whole, TopAbs_FACE);
    source_map(*run.splitter, input_faces, cuts.faces, cuts.source);
    cuts.element.assign(cuts.faces.Extent(), -1);
    TopTools_IndexedDataMapOfShapeListOfShape owners;
    TopExp::MapShapesAndAncestors(run.whole, TopAbs_FACE, TopAbs_SOLID, owners);
    for (int g = 1; g <= cuts.faces.Extent(); ++g) {
        if (cuts.source[g - 1] != 0) {
            continue;
        }
        poll(cancel);
        std::vector<TopoDS_Shape> distinct;
        if (owners.Contains(cuts.faces(g))) {
            for (TopTools_ListOfShape::Iterator it(owners.FindFromKey(cuts.faces(g))); it.More(); it.Next()) {
                const bool seen = std::any_of(distinct.begin(), distinct.end(), [&](const TopoDS_Shape &s) { return s.IsSame(it.Value()); });
                if (!seen) {
                    distinct.push_back(it.Value());
                }
            }
        }
        if (distinct.size() >= 2) {
            cuts.dividing.Append(cuts.faces(g));
        } else {
            cuts.dangling = true;
        }
        const TopoDS_Face face = TopoDS::Face(cuts.faces(g));
        double u = 0;
        double v = 0;
        if (!interior_uv(face, u, v)) {
            continue;
        }
        const gp_Pnt point = BRep_Tool::Surface(face)->Value(u, v);
        const TopoDS_Vertex vertex = BRepBuilderAPI_MakeVertex(point);
        double best = kNameTolerance;
        for (size_t e = 0; e < elements.size(); ++e) {
            BRepExtrema_DistShapeShape distance(vertex, elements[e].face);
            if (distance.IsDone() && distance.Value() <= best) {
                best = distance.Value();
                cuts.element[g - 1] = static_cast<int>(e);
            }
        }
    }
    return cuts;
}

} // namespace

void occt_split_solid_result_free(occt_split_solid_result *result) {
    if (!result) {
        return;
    }
    std::free(result->faces);
    std::free(result->pairs);
    *result = occt_split_solid_result{};
}

occt_shape *occt_split_solid(const occt_shape *solid, const occt_shape *const *tools, int tool_count, const occt_cancel *cancel,
                             occt_split_solid_result *out, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!solid || solid->shape.IsNull() || !out) {
            throw user_error("This solid can't be divided.");
        }
        *out = occt_split_solid_result{};
        const TopoDS_Shape &input = solid->shape;
        if (!TopExp_Explorer(input, TopAbs_SOLID).More()) {
            throw user_error("Split Solid takes a closed solid.");
        }
        if (!tools || tool_count < 1) {
            throw user_error(kNoCut);
        }
        std::vector<ToolFace> elements;
        TopTools_ListOfShape tool_list;
        for (int t = 0; t < tool_count; ++t) {
            if (!tools[t] || tools[t]->shape.IsNull()) {
                throw user_error("This tool can't be used.");
            }
            const TopoDS_Shape &tool = tools[t]->shape;
            // The splitter refuses a tool compound whose members meet each other, so each solid and each loose face goes in on its own.
            append_members(tool, tool_list);
            TopTools_IndexedMapOfShape closed_faces;
            for (TopExp_Explorer solids(tool, TopAbs_SOLID); solids.More(); solids.Next()) {
                for (TopExp_Explorer walker(solids.Current(), TopAbs_FACE); walker.More(); walker.Next()) {
                    closed_faces.Add(walker.Current());
                }
            }
            const TopTools_IndexedMapOfShape tool_faces = map_of(tool, TopAbs_FACE);
            for (int i = 1; i <= tool_faces.Extent(); ++i) {
                ToolFace element;
                element.face = TopoDS::Face(tool_faces(i));
                element.operand = t + 1;
                element.index = i;
                element.closed = closed_faces.Contains(tool_faces(i));
                elements.push_back(element);
            }
        }
        const TopTools_IndexedMapOfShape input_faces = map_of(input, TopAbs_FACE);

        SplitRun run = run_splitter(input, tool_list, cancel, kFailure);
        Cuts cuts = analyse(run, input_faces, elements, cancel);
        if (cuts.dividing.IsEmpty()) {
            throw user_error(kNoCut);
        }
        const bool dangling = cuts.dangling;
        if (dangling) {
            run = run_splitter(input, cuts.dividing, cancel, kFailure);
            cuts = analyse(run, input_faces, elements, cancel);
            if (cuts.dividing.IsEmpty()) {
                throw user_error(kNoCut);
            }
        }

        // The pieces, each a valid solid with a positive volume.
        BRep_Builder builder;
        TopoDS_Compound pieces;
        builder.MakeCompound(pieces);
        std::vector<TopoDS_Shape> piece_list;
        const TopTools_IndexedMapOfShape solids = map_of(run.whole, TopAbs_SOLID);
        for (int i = 1; i <= solids.Extent(); ++i) {
            TopoDS_Shape piece = solids(i);
            if (!BRepCheck_Analyzer(piece).IsValid()) {
                throw user_error(kFailure);
            }
            GProp_GProps properties;
            BRepGProp::VolumeProperties(piece, properties);
            if (properties.Mass() < 0) {
                piece.Reverse();
            }
            builder.Add(pieces, piece);
            piece_list.push_back(piece);
        }
        if (piece_list.size() < 2) {
            throw user_error(kNoCut);
        }
        poll(cancel);

        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(pieces, TopAbs_EDGE, TopAbs_FACE, edge_faces);
        std::vector<occt_split_solid_face> face_table;
        std::vector<occt_split_pair> pair_table;
        for (size_t p = 0; p < piece_list.size(); ++p) {
            const TopTools_IndexedMapOfShape piece_faces = map_of(piece_list[p], TopAbs_FACE);
            for (int fi = 1; fi <= piece_faces.Extent(); ++fi) {
                poll(cancel);
                const TopoDS_Face face = TopoDS::Face(piece_faces(fi));
                const int whole_index = cuts.faces.FindIndex(face);
                occt_split_solid_face entry{static_cast<int>(p), -1, 0, static_cast<int>(pair_table.size()), 0};
                const int own = whole_index > 0 ? cuts.element[whole_index - 1] : -1;
                if (whole_index > 0 && cuts.source[whole_index - 1] > 0) {
                    entry.source_operand = 0;
                    entry.source_face = cuts.source[whole_index - 1];
                } else if (own >= 0) {
                    entry.source_operand = elements[own].operand;
                    entry.source_face = elements[own].index;
                }
                std::vector<int> seen;
                if (own >= 0) {
                    // A cut face: the piece lies against the face's outward normal, so it is on the tool's normal side
                    // when that normal points the way the piece does.
                    bool on_normal_side = true;
                    double u = 0;
                    double v = 0;
                    gp_Vec outward;
                    gp_Vec normal;
                    if (interior_uv(face, u, v)) {
                        gp_Pnt point;
                        BRepGProp_Face properties(face);
                        properties.Normal(u, v, point, outward);
                        if (outward.Magnitude() > 1e-12 && tool_normal(point, elements[own].face, normal)) {
                            on_normal_side = outward.Reversed().Dot(normal) >= 0;
                        }
                    }
                    seen.push_back(own);
                    pair_table.push_back(occt_split_pair{own, side_of(elements[own].closed, on_normal_side)});
                }
                for (TopExp_Explorer walker(face, TopAbs_EDGE); walker.More(); walker.Next()) {
                    const TopoDS_Edge edge = TopoDS::Edge(walker.Current());
                    if (BRep_Tool::Degenerated(edge)) {
                        continue;
                    }
                    for (const TopoDS_Face &neighbour : distinct_faces(edge, edge_faces)) {
                        if (neighbour.IsSame(face)) {
                            continue;
                        }
                        const int index = cuts.faces.FindIndex(neighbour);
                        const int element = index > 0 ? cuts.element[index - 1] : -1;
                        if (element < 0 || std::find(seen.begin(), seen.end(), element) != seen.end()) {
                            continue;
                        }
                        seen.push_back(element);
                        // The direction into this face from the cut edge, against the tool's normal at the middle of the edge.
                        bool on_normal_side = true;
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
                        gp_Vec normal;
                        if (!pcurve.IsNull() && tangent.Magnitude() > 1e-12 && tool_normal(on_edge, elements[element].face, normal)) {
                            const gp_Pnt2d uv = pcurve->Value(0.5 * (f0 + f1));
                            BRepGProp_Face properties(face);
                            gp_Pnt surface_point;
                            gp_Vec face_normal;
                            properties.Normal(uv.X(), uv.Y(), surface_point, face_normal);
                            if (face_normal.Magnitude() > 1e-12) {
                                tangent.Normalize();
                                face_normal.Normalize();
                                on_normal_side = face_normal.Crossed(tangent).Dot(normal) >= 0;
                            }
                        }
                        pair_table.push_back(occt_split_pair{element, side_of(elements[element].closed, on_normal_side)});
                    }
                }
                entry.pair_count = static_cast<int>(pair_table.size()) - entry.pair_start;
                face_table.push_back(entry);
            }
        }
        out->faces = copy_out(face_table);
        out->face_count = static_cast<int>(face_table.size());
        out->pairs = copy_out(pair_table);
        out->pair_count = static_cast<int>(pair_table.size());
        out->piece_count = static_cast<int>(piece_list.size());
        out->dangling = dangling ? 1 : 0;
        return new occt_shape{pieces};
    });
}
