#include "cocct_internal.hpp"

#include <BRepBuilderAPI_GTransform.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRep_Tool.hxx>
#include <IGESData_GlobalSection.hxx>
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
        const TopoDS_Shape shape = reader.OneShape();
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
        const TopoDS_Shape shape = reader.OneShape();
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
void classify(const TopoDS_Shape &shape, std::vector<found_shape> &found) {
    switch (shape.ShapeType()) {
    case TopAbs_COMPOUND:
    case TopAbs_COMPSOLID:
        for (TopoDS_Iterator it(shape); it.More(); it.Next()) {
            classify(it.Value(), found);
        }
        break;
    case TopAbs_SOLID:
        found.push_back({shape, 0});
        break;
    case TopAbs_SHELL:
    case TopAbs_FACE:
        found.push_back({shape, 1});
        break;
    case TopAbs_WIRE:
        found.push_back({shape, 2});
        break;
    case TopAbs_EDGE: {
        const TopoDS_Edge edge = TopoDS::Edge(shape);
        if (!BRep_Tool::Degenerated(edge)) {
            BRepBuilderAPI_MakeWire wire(edge);
            if (wire.IsDone()) {
                found.push_back(found_shape{TopoDS_Shape(wire.Wire()), 2});
            }
        }
        break;
    }
    default:
        break; // a free vertex is no shape of ours
    }
}

/// Millimetres in the unit a STEP file calls `name` (the names OpenCascade reports for a length unit), or 0 when it is not known.
double step_unit_millimetres(const char *name) {
    std::string upper;
    for (const char *c = name; *c; ++c) {
        upper.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(*c))));
    }
    struct entry {
        const char *name;
        double millimetres;
    };
    static const entry table[] = {
        {"MM", 1}, {"MILLIMETRE", 1}, {"MILLIMETER", 1}, {"CM", 10}, {"CENTIMETRE", 10}, {"CENTIMETER", 10},
        {"M", 1000}, {"METRE", 1000}, {"METER", 1000}, {"KM", 1e6}, {"KILOMETRE", 1e6}, {"KILOMETER", 1e6},
        {"UM", 1e-3}, {"MICROMETRE", 1e-3}, {"MICROMETER", 1e-3}, {"MICRON", 1e-3},
        {"INCH", 25.4}, {"IN", 25.4}, {"FOOT", 304.8}, {"FT", 304.8}, {"MIL", 0.0254}, {"MILE", 1609344},
    };
    for (const entry &candidate : table) {
        if (upper == candidate.name) {
            return candidate.millimetres;
        }
    }
    return 0;
}

/// Millimetres in the length unit an IGES file's global section names (its unit flag), 1 when unknown.
double iges_unit_millimetres(const IGESData_GlobalSection &section) {
    switch (section.UnitFlag()) {
    case 1: return 25.4;
    case 2: return 1;
    case 4: return 304.8;
    case 5: return 1609344;
    case 6: return 1000;
    case 7: return 1e6;
    case 8: return 0.0254;
    case 9: return 1e-3;
    case 10: return 10;
    case 11: return 2.54e-5;
    default: break;
    }
    const Handle(TCollection_HAsciiString) name = section.UnitName();
    if (!name.IsNull()) {
        const double known = step_unit_millimetres(name->ToCString());
        if (known > 0) {
            return known;
        }
    }
    return 1;
}

/// Transfers the roots of `reader` (already read) and sorts the result into `out`, which the caller frees.
int sort_into(XSControl_Reader &reader, double file_unit_millimetres, occt_model_shapes *out, occt_status *status) {
    reader.TransferRoots();
    const TopoDS_Shape root = reader.OneShape();
    if (root.IsNull()) {
        set_error(status, "The model contains no shapes.");
        return 0;
    }
    std::vector<found_shape> found;
    classify(root, found);
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
                return sort_into(reader, unit, out, status);
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
            double unit = 1;
            TColStd_SequenceOfAsciiString lengths, angles, solid_angles;
            reader.FileUnits(lengths, angles, solid_angles);
            if (lengths.Length() > 0) {
                const double known = step_unit_millimetres(lengths.First().ToCString());
                if (known > 0) {
                    unit = known;
                }
            }
            return sort_into(reader, unit, out, status);
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
        const TCollection_AsciiString previous = Interface_Static::CVal("write.step.unit");
        Interface_Static::SetCVal("write.step.unit", unit ? unit : "MM");
        STEPControl_Writer writer;
        const bool ok = writer.Transfer(shape->shape, STEPControl_AsIs) == IFSelect_RetDone
            && writer.Write(path) == IFSelect_RetDone;
        Interface_Static::SetCVal("write.step.unit", previous.ToCString());
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
