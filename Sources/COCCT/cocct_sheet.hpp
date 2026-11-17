// The boundary-role table every sheet builder fills (NURBS spec, Task 3). Not part of the public C API.
#ifndef COCCT_SHEET_HPP
#define COCCT_SHEET_HPP

#include "cocct_internal.hpp"

#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS_Shape.hxx>

#include <vector>

namespace cocct {

/// `occt_boundary_role.kind` codes.
enum boundary_kind {
    kBoundaryNone = 0,
    kBoundaryStart = 1,
    kBoundaryEnd = 2,
    kBoundaryRail = 3,
    kBoundaryPiece = 4,
    kBoundaryImported = 5,
};

/// One role per edge of `shape` in its TopExp::MapShapes(TopAbs_EDGE) order, all "none" until `set`.
class boundary_table {
public:
    explicit boundary_table(const TopoDS_Shape &shape) : edges_(map_of(shape, TopAbs_EDGE)), roles_(edges_.Extent()) {}

    /// Names `edge` (found by IsSame, whatever its orientation). An edge the shape doesn't have is ignored; one named
    /// twice keeps its first name, so a builder gives the more specific name first.
    void set(const TopoDS_Shape &edge, int kind, int a = 0, int b = 0) {
        const int index = edges_.FindIndex(edge);
        if (index > 0 && roles_[index - 1].kind == kBoundaryNone) {
            roles_[index - 1] = occt_boundary_role{kind, a, b};
        }
    }

    void move_into(occt_boundary_roles *out) const {
        out->roles = copy_out(roles_);
        out->count = static_cast<int>(roles_.size());
    }

private:
    TopTools_IndexedMapOfShape edges_;
    std::vector<occt_boundary_role> roles_;
};

} // namespace cocct

#endif
