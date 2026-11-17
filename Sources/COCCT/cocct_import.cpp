#include "cocct_internal.hpp"

#include <BRepBuilderAPI_GTransform.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <IGESControl_Reader.hxx>
#include <IGESControl_Writer.hxx>
#include <STEPControl_Reader.hxx>
#include <XSControl_Reader.hxx>
#include <gp_GTrsf.hxx>
#include <gp_Pnt.hxx>
#include <gp_Trsf.hxx>

#include <cmath>
#include <cstring>
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
