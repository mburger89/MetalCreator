// Shared, header-only C++ helpers for the shim. Not part of the public C API.
#ifndef COCCT_INTERNAL_HPP
#define COCCT_INTERNAL_HPP

#include <string>
#include "cocct.h"

#include <Bnd_Box.hxx>
#include <Standard_Failure.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>

#include <cstdlib>
#include <cstring>
#include <exception>
#include <new>
#include <stdexcept>
#include <vector>

struct occt_shape {
    TopoDS_Shape shape;
};

namespace cocct {

/// The shape's bounding box, tight to the part. `BRepBndLib::AddOptimal` without a triangulation bounds a high-degree
/// Bezier face (a G2 corner patch, degree 17) by its poles, which stand thousands of mm off the surface; such a face is
/// bounded by a dense sample of its surface and its edges instead. Every other shape costs `AddOptimal` plus one pass over
/// its faces.
void shape_bounds(const TopoDS_Shape &shape, Bnd_Box &box);

/// pi. Not `M_PI`: MSVC's <cmath> defines it only under _USE_MATH_DEFINES, and C++17 has no std::numbers.
inline constexpr double kPi = 3.14159265358979323846;

inline void set_ok(occt_status *status) {
    if (status) {
        status->ok = 1;
        status->message[0] = '\0';
    }
}

inline void set_error(occt_status *status, const char *message) {
    if (status) {
        status->ok = 0;
        std::strncpy(status->message, message ? message : "unknown OCCT error", sizeof(status->message) - 1);
        status->message[sizeof(status->message) - 1] = '\0';
    }
}

/// A problem the shim itself diagnosed (bad input), worded for people. Reported without the "occt: " prefix.
struct user_error : std::runtime_error {
    using std::runtime_error::runtime_error;
};

/// Reports a caught exception, marking the text as raw OCCT output with an "occt: " prefix.
inline void set_caught_error(occt_status *status, const char *message) {
    std::string text = "occt: ";
    text += (message && *message) ? message : "unknown exception";
    set_error(status, text.c_str());
}

/// Runs `body`, converting every C++ exception into an error status. No exception may
/// cross into Swift.
template <typename Body>
auto guarded(occt_status *status, Body body) -> decltype(body()) {
    try {
        set_ok(status);
        return body();
    } catch (const user_error &error) {
        set_error(status, error.what());
    } catch (const Standard_Failure &failure) {
        const char *message = failure.GetMessageString();
        set_caught_error(status, (message && *message) ? message : failure.DynamicType()->Name());
    } catch (const std::exception &error) {
        set_caught_error(status, error.what());
    } catch (...) {
        set_caught_error(status, nullptr);
    }
    return decltype(body()){};
}

/// Runs a query, returning -1 if anything throws.
template <typename Body>
auto queried(Body body) -> decltype(body()) {
    try {
        return body();
    } catch (...) {
        return static_cast<decltype(body())>(-1);
    }
}

inline TopTools_IndexedMapOfShape map_of(const TopoDS_Shape &shape, TopAbs_ShapeEnum kind) {
    TopTools_IndexedMapOfShape map;
    TopExp::MapShapes(shape, kind, map);
    return map;
}

/// The distinct faces (by `IsSame`) adjacent to `edge`. One face means a seam.
inline std::vector<TopoDS_Face> distinct_faces(const TopoDS_Shape &edge,
                                              const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces) {
    std::vector<TopoDS_Face> faces;
    if (!edge_faces.Contains(edge)) {
        return faces;
    }
    for (TopTools_ListOfShape::Iterator it(edge_faces.FindFromKey(edge)); it.More(); it.Next()) {
        bool seen = false;
        for (const TopoDS_Face &face : faces) {
            seen = seen || face.IsSame(it.Value());
        }
        if (!seen) {
            faces.push_back(TopoDS::Face(it.Value()));
        }
    }
    return faces;
}

/// How smoothly `face_a` and `face_b` meet along `edge` over `samples` parameters (see `occt_edge_continuity_of`). Throws
/// `user_error` when no sample can be compared. Reads only; the caller holds `OCCTKernel.serialized`.
occt_edge_continuity edge_continuity(const TopoDS_Edge &edge, const TopoDS_Face &face_a, const TopoDS_Face &face_b, int samples);

template <typename T>
T *copy_out(const std::vector<T> &values) {
    T *out = static_cast<T *>(std::calloc(values.empty() ? 1 : values.size(), sizeof(T)));
    if (!out) {
        throw std::bad_alloc();
    }
    if (!values.empty()) {
        std::memcpy(out, values.data(), values.size() * sizeof(T));
    }
    return out;
}

/// Collects history records against the output's face map.
class history_builder {
public:
    explicit history_builder(const TopoDS_Shape &output) : out_(map_of(output, TopAbs_FACE)) {}

    /// Records every face in `piece` (a face, shell or compound) that exists in the output.
    void add(const TopoDS_Shape &piece, int kind, int operand, int index) {
        if (piece.IsNull()) {
            return;
        }
        for (TopExp_Explorer it(piece, TopAbs_FACE); it.More(); it.Next()) {
            const int found = out_.FindIndex(it.Current());
            if (found > 0) {
                records_.push_back(occt_history_record{found, kind, operand, index});
            }
        }
    }

    void add_all(const TopTools_ListOfShape &pieces, int kind, int operand, int index) {
        for (TopTools_ListOfShape::Iterator it(pieces); it.More(); it.Next()) {
            add(it.Value(), kind, operand, index);
        }
    }

    /// The records as made, against the output the builder was made for.
    const std::vector<occt_history_record> &records() const { return records_; }

    /// Replaces the records (a caller that renumbers them against a different output).
    void set_records(std::vector<occt_history_record> records) { records_ = std::move(records); }

    void move_into(occt_history *history) {
        history->records = copy_out(records_);
        history->count = static_cast<int>(records_.size());
    }

private:
    TopTools_IndexedMapOfShape out_;
    std::vector<occt_history_record> records_;
};

} // namespace cocct

#endif
