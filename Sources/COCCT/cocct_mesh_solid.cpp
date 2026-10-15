#include "cocct_internal.hpp"

#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRep_Builder.hxx>
#include <Bnd_Box.hxx>
#include <ShapeUpgrade_UnifySameDomain.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
#include <TopoDS_Vertex.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <numeric>
#include <string>
#include <unordered_map>
#include <vector>

using namespace cocct;

namespace {

/// One undirected edge of the mesh: the shared OCCT edge, and how the triangles use it.
struct mesh_edge {
    TopoDS_Edge edge;
    int uses = 0;
    int forward_uses = 0;
    int first_triangle = -1;
};

/// A set of triangles joined by shared edges: one closed surface of the mesh.
struct component {
    TopoDS_Shell shell;
    Bnd_Box box;
    double volume = 0;
};

/// Union-find over triangle numbers.
struct triangle_groups {
    std::vector<int> parent;

    explicit triangle_groups(int count) : parent(static_cast<size_t>(count)) { std::iota(parent.begin(), parent.end(), 0); }

    int find(int i) {
        while (parent[i] != i) {
            parent[i] = parent[parent[i]];
            i = parent[i];
        }
        return i;
    }

    void join(int a, int b) { parent[find(a)] = find(b); }
};

bool box_contains(const Bnd_Box &outer, const Bnd_Box &inner) {
    double ox0, oy0, oz0, ox1, oy1, oz1, ix0, iy0, iz0, ix1, iy1, iz1;
    outer.Get(ox0, oy0, oz0, ox1, oy1, oz1);
    inner.Get(ix0, iy0, iz0, ix1, iy1, iz1);
    return ox0 <= ix0 && oy0 <= iy0 && oz0 <= iz0 && ox1 >= ix1 && oy1 >= iy1 && oz1 >= iz1;
}

/// Whether the triangle `other` lies in the plane of the triangle `base` (unit normal `normal`), as exactly as UnifySameDomain, whose
/// default tolerances are 1e-7 mm and 1e-12 rad, can tell: a mesh stored in single precision is rarely that flat, and then there is
/// nothing for the merge to do.
bool is_coplanar(const std::vector<gp_Pnt> &points, const unsigned int *base, const gp_Vec &normal, const unsigned int *other) {
    for (int k = 0; k < 3; ++k) {
        if (std::abs(normal.Dot(gp_Vec(points[base[0]], points[other[k]]))) > 1e-9) {
            return false;
        }
    }
    return true;
}

uint64_t edge_key(unsigned a, unsigned b) { return static_cast<uint64_t>(std::min(a, b)) << 32 | std::max(a, b); }

/// One solid per outward-facing surface, with each inward-facing one (a void) given to the smallest solid whose box holds it.
TopoDS_Shape solids_from(std::vector<component> &surfaces) {
    BRep_Builder builder;
    std::vector<TopoDS_Solid> solids;
    std::vector<size_t> outer;
    for (size_t i = 0; i < surfaces.size(); ++i) {
        if (surfaces[i].volume > 0) {
            BRepBuilderAPI_MakeSolid maker(surfaces[i].shell);
            solids.push_back(maker.Solid());
            outer.push_back(i);
        }
    }
    if (solids.empty()) {
        throw user_error("the mesh is wound inside out: its triangles must run counter-clockwise seen from outside");
    }
    for (const component &hollow : surfaces) {
        if (hollow.volume > 0) {
            continue;
        }
        int best = -1;
        for (size_t k = 0; k < outer.size(); ++k) {
            const component &candidate = surfaces[outer[k]];
            if (box_contains(candidate.box, hollow.box) && (best < 0 || candidate.volume < surfaces[outer[best]].volume)) {
                best = static_cast<int>(k);
            }
        }
        if (best < 0) {
            throw user_error("the mesh has a cavity that no outer surface contains");
        }
        builder.Add(solids[best], hollow.shell);
    }
    if (solids.size() == 1) {
        return solids[0];
    }
    TopoDS_Compound compound;
    builder.MakeCompound(compound);
    for (const TopoDS_Solid &solid : solids) {
        builder.Add(compound, solid);
    }
    return compound;
}

} // namespace

extern "C" {

occt_shape *occt_mesh_to_solid(const double *positions, int vertex_count, const unsigned int *triangles, int triangle_count,
                               occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!positions || !triangles || vertex_count < 4 || triangle_count < 4) {
            throw user_error("a mesh needs at least four triangles to make a solid");
        }
        // The vertices, made once: a triangle that names a vertex uses that vertex, so the surface is sewn by construction.
        BRep_Builder builder;
        std::vector<gp_Pnt> points;
        points.reserve(static_cast<size_t>(vertex_count));
        std::vector<TopoDS_Vertex> vertices(static_cast<size_t>(vertex_count));
        for (int i = 0; i < vertex_count; ++i) {
            const double *p = positions + 3 * i;
            if (!(std::isfinite(p[0]) && std::isfinite(p[1]) && std::isfinite(p[2]))) {
                throw user_error("the mesh has a vertex that is not a finite position");
            }
            points.emplace_back(p[0], p[1], p[2]);
            builder.MakeVertex(vertices[static_cast<size_t>(i)], points.back(), 1e-7);
        }

        // The edges, made once each, and the faces on them; the shell of a surface is its faces.
        std::unordered_map<uint64_t, mesh_edge> edges;
        edges.reserve(static_cast<size_t>(triangle_count) * 3 / 2 + 16);
        std::vector<TopoDS_Face> faces(static_cast<size_t>(triangle_count));
        std::vector<gp_Vec> normals(static_cast<size_t>(triangle_count));
        triangle_groups groups(triangle_count);
        bool has_coplanar_neighbours = false;
        for (int t = 0; t < triangle_count; ++t) {
            const unsigned int *corner = triangles + 3 * t;
            for (int k = 0; k < 3; ++k) {
                if (corner[k] >= static_cast<unsigned>(vertex_count)) {
                    throw user_error("the mesh has a triangle that names a vertex it does not have");
                }
            }
            if (corner[0] == corner[1] || corner[1] == corner[2] || corner[0] == corner[2]) {
                throw user_error("the mesh has a triangle with a repeated vertex (" + std::to_string(t) + ")");
            }
            const gp_Vec normal = gp_Vec(points[corner[0]], points[corner[1]]).Crossed(gp_Vec(points[corner[0]], points[corner[2]]));
            if (normal.Magnitude() < 1e-14) {
                throw user_error("the mesh has a triangle with no area (" + std::to_string(t) + ")");
            }
            normals[static_cast<size_t>(t)] = normal.Normalized();
            TopoDS_Wire wire;
            builder.MakeWire(wire);
            for (int side = 0; side < 3; ++side) {
                const unsigned from = corner[side], to = corner[(side + 1) % 3];
                mesh_edge &record = edges[edge_key(from, to)];
                if (record.uses == 0) {
                    BRepBuilderAPI_MakeEdge maker(vertices[std::min(from, to)], vertices[std::max(from, to)]);
                    if (!maker.IsDone()) {
                        throw user_error("the mesh has an edge too short for OpenCascade (triangle " + std::to_string(t) + ")");
                    }
                    record.edge = maker.Edge();
                    record.first_triangle = t;
                } else {
                    groups.join(record.first_triangle, t);
                    if (!has_coplanar_neighbours) {
                        has_coplanar_neighbours = is_coplanar(points, triangles + 3 * record.first_triangle, normals[static_cast<size_t>(record.first_triangle)], corner);
                    }
                }
                ++record.uses;
                const bool forward = from < to;
                if (forward) {
                    ++record.forward_uses;
                }
                builder.Add(wire, forward ? record.edge : TopoDS::Edge(record.edge.Reversed()));
            }
            wire.Closed(Standard_True);
            BRepBuilderAPI_MakeFace maker(wire, Standard_True);
            if (!maker.IsDone()) {
                throw user_error("the mesh has a triangle OpenCascade cannot make a face of (" + std::to_string(t) + ")");
            }
            faces[static_cast<size_t>(t)] = maker.Face();
        }
        int open = 0, shared_too_much = 0, mismatched = 0;
        for (const auto &entry : edges) {
            const mesh_edge &record = entry.second;
            if (record.uses == 1) {
                ++open;
            } else if (record.uses > 2) {
                ++shared_too_much;
            } else if (record.forward_uses != 1) {
                ++mismatched;
            }
        }
        if (open > 0) {
            throw user_error("the mesh is not closed: " + std::to_string(open) + " edges belong to a single triangle");
        }
        if (shared_too_much > 0) {
            throw user_error("the mesh is not a manifold: " + std::to_string(shared_too_much) +
                             " edges are shared by more than two triangles");
        }
        if (mismatched > 0) {
            throw user_error("the mesh is not consistently wound: " + std::to_string(mismatched) +
                             " edges are run the same way by both triangles that share them");
        }

        // The surfaces: the triangles joined by edges, each a shell with its volume (positive when it faces outwards).
        std::unordered_map<int, size_t> index_of;
        std::vector<component> surfaces;
        for (int t = 0; t < triangle_count; ++t) {
            const int root = groups.find(t);
            auto found = index_of.find(root);
            if (found == index_of.end()) {
                found = index_of.emplace(root, surfaces.size()).first;
                surfaces.emplace_back();
                builder.MakeShell(surfaces.back().shell);
            }
            component &surface = surfaces[found->second];
            builder.Add(surface.shell, faces[static_cast<size_t>(t)]);
            const unsigned int *corner = triangles + 3 * t;
            const gp_Pnt &a = points[corner[0]], &b = points[corner[1]], &c = points[corner[2]];
            surface.volume += gp_Vec(a.XYZ()).Dot(gp_Vec(b.XYZ()).Crossed(gp_Vec(c.XYZ()))) / 6;
            surface.box.Add(a);
            surface.box.Add(b);
            surface.box.Add(c);
        }
        for (component &surface : surfaces) {
            surface.shell.Closed(Standard_True);
        }
        TopoDS_Shape result = solids_from(surfaces);
        // Faces that lie in one plane become one face; with none beside each other there is nothing to merge.
        if (has_coplanar_neighbours) {
            ShapeUpgrade_UnifySameDomain unify(result, Standard_True, Standard_True, Standard_True);
            unify.Build();
            result = unify.Shape();
        }
        // The faces are checked in parallel: on 100,000 faces that is the larger half of what is left.
        BRepCheck_Analyzer analyzer(result, Standard_True, Standard_True);
        if (!analyzer.IsValid()) {
            throw user_error("OpenCascade rejected the solid: the mesh may cross itself or have a bad edge");
        }
        return new occt_shape{result};
    });
}

} // extern "C"
