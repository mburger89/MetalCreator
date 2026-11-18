#include "cocct_internal.hpp"

#include <BRepBuilderAPI_GTransform.hxx>
#include <ShapeAnalysis_FreeBounds.hxx>
#include <TopTools_HSequenceOfShape.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <Standard_OutOfMemory.hxx>
#include <TopoDS_Compound.hxx>
#include <IGESData_BasicEditor.hxx>
#include <IGESData_GlobalSection.hxx>
#include <STEPConstruct_UnitContext.hxx>
#include <StepData_StepModel.hxx>
#include <StepGeom_GeomRepContextAndGlobUnitAssCtxAndGlobUncertaintyAssCtx.hxx>
#include <StepGeom_GeometricRepresentationContextAndGlobalUnitAssignedContext.hxx>
#include <StepRepr_GlobalUnitAssignedContext.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
#include <IGESData_IGESModel.hxx>
#include <Interface_Static.hxx>
#include <TColStd_SequenceOfAsciiString.hxx>
#include <TCollection_AsciiString.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopoDS_Wire.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <IGESControl_Reader.hxx>
#include <IGESControl_Writer.hxx>
#include <STEPControl_Reader.hxx>
#include <STEPControl_Writer.hxx>
#include <XSControl_Reader.hxx>
#include <gp_GTrsf.hxx>
#include <gp_Pnt.hxx>
#include <gp_Trsf.hxx>

#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <istream>
#include <streambuf>

using namespace cocct;

namespace {

/// A read-only stream buffer over the caller's bytes: nothing is copied.
class BorrowedBuffer : public std::streambuf {
public:
    BorrowedBuffer(const char *data, size_t size) {
        char *begin = const_cast<char *>(data);
        setg(begin, begin, begin + size);
    }
};

/// The valid, outward-oriented solid a closed free shell makes, or a null shape when `shell` is open or makes no valid solid.
TopoDS_Shape solidify_closed_shell(const TopoDS_Shape &shell) {
    if (!BRep_Tool::IsClosed(shell)) {
        return TopoDS_Shape();
    }
    BRepBuilderAPI_MakeSolid maker(TopoDS::Shell(shell));
    if (!maker.IsDone()) {
        return TopoDS_Shape();
    }
    TopoDS_Shape solid = maker.Solid();
    GProp_GProps volume;
    BRepGProp::VolumeProperties(solid, volume);
    if (volume.Mass() < 0) {
        solid.Reverse();
    }
    BRepCheck_Analyzer check(solid);
    return check.IsValid() ? solid : TopoDS_Shape();
}

/// `shape` with every closed free shell made a solid (through compounds; solids, open shells and loose faces stay as they are).
/// Returns `shape` itself, untouched, when nothing changes, so a model that was already solids keeps its faces in their order.
TopoDS_Shape solidify_free_shells(const TopoDS_Shape &shape) {
    if (shape.IsNull()) {
        return shape; // a model with no shapes: the caller says so
    }
    if (shape.ShapeType() == TopAbs_SHELL) {
        const TopoDS_Shape solid = solidify_closed_shell(shape);
        return solid.IsNull() ? shape : solid;
    }
    if (shape.ShapeType() != TopAbs_COMPOUND) {
        return shape;
    }
    std::vector<TopoDS_Shape> parts;
    bool changed = false;
    for (TopoDS_Iterator it(shape); it.More(); it.Next()) {
        parts.push_back(solidify_free_shells(it.Value()));
        changed = changed || !parts.back().IsSame(it.Value()) || parts.back().Orientation() != it.Value().Orientation();
    }
    if (!changed) {
        return shape;
    }
    BRep_Builder builder;
    TopoDS_Compound compound;
    builder.MakeCompound(compound);
    for (const TopoDS_Shape &part : parts) {
        builder.Add(compound, part);
    }
    return compound;
}

/// Reads `data` through `reader` and transfers its roots. Returns null (and sets `status`) when the bytes aren't a model of
/// that format or hold no shapes. Any OpenCascade exception while reading is the same "couldn't be read" to the person.
occt_shape *read_with(XSControl_Reader &reader, const char *data, size_t size, const char *unreadable, occt_status *status) {
    try {
        BorrowedBuffer buffer(data, size);
        std::istream stream(&buffer);
        if (reader.ReadStream("model", stream) != IFSelect_RetDone) {
            set_error(status, unreadable);
            return nullptr;
        }
        reader.TransferRoots();
        const TopoDS_Shape shape = solidify_free_shells(reader.OneShape());
        if (shape.IsNull()) {
            set_error(status, "The model contains no shapes.");
            return nullptr;
        }
        return new occt_shape{shape};
    } catch (const Standard_Failure &) {
        set_error(status, unreadable);
    }
    return nullptr;
}

/// Reads the IGES file at `path` (the Swift side has already checked that it looks like IGES).
occt_shape *read_iges_file(const char *path, occt_status *status) {
    static const char *const unreadable = "The IGES model couldn't be read.";
    try {
        IGESControl_Reader reader;
        if (reader.ReadFile(path) != IFSelect_RetDone) {
            set_error(status, unreadable);
            return nullptr;
        }
        reader.TransferRoots();
        const TopoDS_Shape shape = solidify_free_shells(reader.OneShape());
        if (shape.IsNull()) {
            set_error(status, "The model contains no shapes.");
            return nullptr;
        }
        return new occt_shape{shape};
    } catch (const Standard_Failure &) {
        set_error(status, unreadable);
    }
    return nullptr;
}


/// One shape of a model file and what it is: 0 a solid, 1 a sheet (a free shell or face), 2 a curve (a free wire or edge).
struct found_shape {
    TopoDS_Shape shape;
    int kind;
};

/// Walks `shape` through its compounds (the locations and orientations accumulate) and sorts what is free in it.
void classify(const TopoDS_Shape &shape, std::vector<found_shape> &found, std::vector<TopoDS_Edge> &loose,
              std::vector<TopoDS_Shape> &loose_faces) {
    switch (shape.ShapeType()) {
    case TopAbs_COMPOUND:
    case TopAbs_COMPSOLID:
        for (TopoDS_Iterator it(shape); it.More(); it.Next()) {
            classify(it.Value(), found, loose, loose_faces);
        }
        break;
    case TopAbs_SOLID:
        found.push_back({shape, 0});
        break;
    case TopAbs_SHELL: {
        // A closed free shell is a solid when it makes a valid one; otherwise (or when open) it joins the file's one sheet.
        const TopoDS_Shape solid = solidify_closed_shell(shape);
        if (!solid.IsNull()) {
            found.push_back(found_shape{solid, 0});
            break;
        }
        loose_faces.push_back(shape);
        break;
    }
    case TopAbs_FACE:
        loose_faces.push_back(shape);
        break;
    case TopAbs_WIRE: {
        // A STEP curve set can come back as a wire per edge: those chain with the loose edges, whole wires stay as they are.
        TopoDS_Iterator it(shape);
        const TopoDS_Shape first = it.More() ? it.Value() : TopoDS_Shape();
        if (it.More()) {
            it.Next();
        }
        if (!first.IsNull() && !it.More() && first.ShapeType() == TopAbs_EDGE) {
            const TopoDS_Edge edge = TopoDS::Edge(first);
            if (!BRep_Tool::Degenerated(edge)) {
                loose.push_back(edge);
            }
        } else {
            found.push_back({shape, 2});
        }
        break;
    }
    case TopAbs_EDGE: {
        const TopoDS_Edge edge = TopoDS::Edge(shape);
        if (!BRep_Tool::Degenerated(edge)) {
            loose.push_back(edge); // chained with the others after the walk
        }
        break;
    }
    default:
        break; // a free vertex is no shape of ours
    }
}

/// Chains the free edges of a read into wires (a STEP curve set comes back as loose edges): one curve per connected chain,
/// in the order of each chain's lowest edge.
void chain_loose_edges(const std::vector<TopoDS_Edge> &loose, std::vector<found_shape> &found) {
    if (loose.empty()) {
        return;
    }
    Handle(TopTools_HSequenceOfShape) edges = new TopTools_HSequenceOfShape();
    for (const TopoDS_Edge &edge : loose) {
        edges->Append(edge);
    }
    Handle(TopTools_HSequenceOfShape) wires;
    ShapeAnalysis_FreeBounds::ConnectEdgesToWires(edges, 1e-6, Standard_False, wires);
    TopTools_IndexedMapOfShape positions;
    for (const TopoDS_Edge &edge : loose) {
        positions.Add(edge);
    }
    std::vector<std::pair<size_t, TopoDS_Shape>> chains;
    if (!wires.IsNull()) {
        for (Standard_Integer i = 1; i <= wires->Length(); ++i) {
            const TopoDS_Shape wire = wires->Value(i);
            size_t lowest = loose.size();
            for (TopoDS_Iterator it(wire); it.More(); it.Next()) {
                // The first loose edge that is the same as this one (the map holds each distinct edge once, by position of first add).
                if (const int at = positions.FindIndex(it.Value()); at > 0) {
                    lowest = std::min(lowest, static_cast<size_t>(at - 1));
                }
            }
            chains.emplace_back(lowest, wire);
        }
    }
    std::stable_sort(chains.begin(), chains.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
    for (const auto &chain : chains) {
        found.push_back(found_shape{chain.second, 2});
    }
}

/// Millimetres in the length unit an IGES file's global section names, from OpenCascade's own table of unit flags; 0 when the
/// flag is one it has no length for (a named unit).
double iges_unit_millimetres(const IGESData_GlobalSection &section) {
    // `UnitFlagValue` is the unit in millimetres (its header says metres; the values are 1 for flag 2 and 25.4 for flag 1).
    const double millimetres = IGESData_BasicEditor::UnitFlagValue(section.UnitFlag());
    return (std::isfinite(millimetres) && millimetres > 0) ? millimetres : 0.0;
}

/// Transfers the roots of `reader` (already read) and sorts the result into `out`, which the caller frees.
int sort_into(XSControl_Reader &reader, double file_unit_millimetres, bool transfer, occt_model_shapes *out, occt_status *status) {
    if (transfer) {
        reader.TransferRoots();
    }
    const TopoDS_Shape root = reader.OneShape();
    if (root.IsNull()) {
        set_error(status, "The model contains no shapes.");
        return 0;
    }
    std::vector<found_shape> found;
    std::vector<TopoDS_Edge> loose;
    std::vector<TopoDS_Shape> loose_faces;
    classify(root, found, loose, loose_faces);
    if (!loose_faces.empty()) {
        // Every loose face and free open shell of the file is one sheet (an unsewn compound), so its faces are numbered file-wide.
        BRep_Builder builder;
        TopoDS_Compound sheet;
        builder.MakeCompound(sheet);
        for (const TopoDS_Shape &part : loose_faces) {
            builder.Add(sheet, part);
        }
        found.push_back({sheet, 1});
    }
    chain_loose_edges(loose, found);
    if (found.empty()) {
        set_error(status, "The model contains no shapes.");
        return 0;
    }
    out->count = static_cast<int>(found.size());
    out->shapes = static_cast<occt_shape **>(std::calloc(found.size(), sizeof(occt_shape *)));
    out->kinds = static_cast<int *>(std::calloc(found.size(), sizeof(int)));
    if (!out->shapes || !out->kinds) {
        throw std::bad_alloc();
    }
    for (size_t i = 0; i < found.size(); ++i) {
        out->shapes[i] = new occt_shape{found[i].shape};
        out->kinds[i] = found[i].kind;
    }
    out->file_unit_mm = file_unit_millimetres;
    return 1;
}

} // namespace

extern "C" {

occt_shape *occt_read_model(const char *data, size_t size, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!data || size == 0) {
            set_error(status, "The STEP model couldn't be read.");
            return nullptr;
        }
        occt_initialize();
        STEPControl_Reader reader;
        return read_with(reader, data, size, "The STEP model couldn't be read.", status);
    });
}

occt_shape *occt_read_iges_file(const char *path, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!path) {
            set_error(status, "no file path given");
            return nullptr;
        }
        occt_initialize();
        return read_iges_file(path, status);
    });
}

occt_shape *occt_scale(const occt_shape *shape, double sx, double sy, double sz, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!(std::isfinite(sx) && std::isfinite(sy) && std::isfinite(sz) && sx > 0 && sy > 0 && sz > 0)) {
            throw user_error("The scale must be greater than 0.");
        }
        if (sx == sy && sy == sz) {
            gp_Trsf scale;
            scale.SetScale(gp_Pnt(0, 0, 0), sx);
            BRepBuilderAPI_Transform builder(shape->shape, scale, Standard_True);
            if (!builder.IsDone()) {
                throw user_error("The model couldn't be scaled.");
            }
            return new occt_shape{builder.Shape()};
        }
        gp_GTrsf scale;
        scale.SetVectorialPart(gp_Mat(sx, 0, 0, 0, sy, 0, 0, 0, sz));
        BRepBuilderAPI_GTransform builder(shape->shape, scale, Standard_True);
        if (!builder.IsDone()) {
            throw user_error("The model couldn't be scaled.");
        }
        return new occt_shape{builder.Shape()};
    });
}

void occt_model_shapes_free(occt_model_shapes *models) {
    if (!models) {
        return;
    }
    if (models->shapes) {
        for (int i = 0; i < models->count; ++i) {
            delete models->shapes[i];
        }
    }
    std::free(models->shapes);
    std::free(models->kinds);
    *models = occt_model_shapes{};
}

int occt_read_shapes(const char *data, size_t size, const char *iges_path, occt_model_shapes *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_model_shapes{};
        occt_initialize();
        try {
            if (iges_path) {
                static const char *const unreadable = "The IGES model couldn't be read.";
                IGESControl_Reader reader;
                if (reader.ReadFile(iges_path) != IFSelect_RetDone) {
                    set_error(status, unreadable);
                    return 0;
                }
                double unit = 1;
                Handle(IGESData_IGESModel) model = Handle(IGESData_IGESModel)::DownCast(reader.Model());
                if (!model.IsNull()) {
                    unit = iges_unit_millimetres(model->GlobalSection());
                }
                return sort_into(reader, unit, true, out, status);
            }
            static const char *const unreadable = "The STEP model couldn't be read.";
            if (!data || size == 0) {
                set_error(status, unreadable);
                return 0;
            }
            STEPControl_Reader reader;
            BorrowedBuffer buffer(data, size);
            std::istream stream(&buffer);
            if (reader.ReadStream("model", stream) != IFSelect_RetDone) {
                set_error(status, unreadable);
                return 0;
            }
            // The file's own length unit, in millimetres, as OpenCascade computes it from the file's unit context (0: it names none).
            // `ComputeFactors` is the transfer's own reading of the unit entities (prefix and conversion factor included).
            double unit = 0;
            Handle(StepData_StepModel) model = Handle(StepData_StepModel)::DownCast(reader.Model());
            if (!model.IsNull()) {
                for (Standard_Integer i = 1; i <= model->NbEntities() && unit == 0; ++i) {
                    Handle(StepRepr_GlobalUnitAssignedContext) context;
                    if (auto both = Handle(StepGeom_GeomRepContextAndGlobUnitAssCtxAndGlobUncertaintyAssCtx)::DownCast(model->Value(i));
                        !both.IsNull()) {
                        context = both->GlobalUnitAssignedContext();
                    } else if (auto plain = Handle(StepGeom_GeometricRepresentationContextAndGlobalUnitAssignedContext)::DownCast(
                                   model->Value(i));
                               !plain.IsNull()) {
                        context = plain->GlobalUnitAssignedContext();
                    }
                    if (context.IsNull()) {
                        continue;
                    }
                    STEPConstruct_UnitContext units;
                    units.ComputeFactors(context);
                    const double factor = units.LengthFactor();
                    if (units.LengthDone() && std::isfinite(factor) && factor > 0) {
                        unit = factor;
                    }
                }
            }
            reader.TransferRoots();
            return sort_into(reader, unit, false, out, status);
        } catch (const Standard_OutOfMemory &) {
            occt_model_shapes_free(out);
            throw; // `guarded` turns it into an "occt:" failure, which no cache remembers
        } catch (const Standard_Failure &) {
            occt_model_shapes_free(out);
            set_error(status, iges_path ? "The IGES model couldn't be read." : "The STEP model couldn't be read.");
            return 0;
        } catch (...) {
            occt_model_shapes_free(out);
            throw;
        }
    });
}

int occt_test_write_step_units(const occt_shape *shape, const char *path, const char *unit, occt_status *status) {
    return guarded(status, [&]() -> int {
        occt_initialize();
        // Restores the global unit on every path, including an exception.
        struct unit_restorer {
            TCollection_AsciiString previous = Interface_Static::CVal("write.step.unit");
            ~unit_restorer() { Interface_Static::SetCVal("write.step.unit", previous.ToCString()); }
        } restore;
        Interface_Static::SetCVal("write.step.unit", unit ? unit : "MM");
        STEPControl_Writer writer;
        const bool ok = writer.Transfer(shape->shape, STEPControl_AsIs) == IFSelect_RetDone
            && writer.Write(path) == IFSelect_RetDone;
        if (!ok) {
            set_error(status, "STEP file could not be written");
            return 0;
        }
        return 1;
    });
}

int occt_test_write_iges(const occt_shape *shape, const char *path, const char *unit, occt_status *status) {
    return guarded(status, [&]() -> int {
        if (!path) {
            set_error(status, "no output path");
            return 0;
        }
        occt_initialize();
        IGESControl_Writer writer(unit ? unit : "MM", 0);
        if (!writer.AddShape(shape->shape)) {
            set_error(status, "IGES transfer failed");
            return 0;
        }
        writer.ComputeModel();
        if (!writer.Write(path)) {
            set_error(status, "IGES file could not be written");
            return 0;
        }
        return 1;
    });
}

} // extern "C"
