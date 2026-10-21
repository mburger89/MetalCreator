#include "cocct_internal.hpp"

#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepExtrema_SupportType.hxx>
#include <BRepGProp_Face.hxx>
#include <BRepTools.hxx>
#include <BRep_Tool.hxx>
#include <Geom_Surface.hxx>
#include <OSD_Parallel.hxx>
#include <ShapeAnalysis_Surface.hxx>
#include <TopoDS_Edge.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <mutex>
#include <string>

using namespace cocct;

namespace {

TopoDS_Face face_at(const occt_shape *shape, int index) {
    if (!shape) {
        throw user_error("there is no shape to take a face from");
    }
    const TopTools_IndexedMapOfShape all = map_of(shape->shape, TopAbs_FACE);
    if (index < 1 || index > all.Extent()) {
        throw user_error("face index out of range");
    }
    return TopoDS::Face(all(index));
}

/// `value` moved by whole periods to lie within half a period of `middle`.
double wrapped(double value, double middle, double period) {
    return middle + (value - middle) - period * std::round((value - middle) / period);
}

/// The nearest point of a face to each point of a run, in blocks that OCCT's own thread pool shares out. Each block builds its own
/// extrema, surface-analysis and normal objects, so the threads share only the face, which they read and never change.
struct FaceCoordinatesJob {
    static constexpr int block = 32;

    const TopoDS_Face &face;
    Handle(Geom_Surface) surface;
    bool u_periodic, v_periodic;
    double u_period, v_period, u_middle, v_middle;
    const double *points;
    double *out;
    int count;
    mutable std::atomic<bool> failed{false};
    mutable std::mutex lock;
    mutable std::string message;

    int blocks() const { return (count + block - 1) / block; }

    void fail(const std::string &text) const {
        std::lock_guard<std::mutex> guard(lock);
        if (!failed.exchange(true)) {
            message = text;
        }
    }

    void operator()(int index) const {
        if (failed.load()) {
            return;
        }
        try {
            BRepExtrema_DistShapeShape distance;
            distance.LoadS2(face);
            ShapeAnalysis_Surface analysis(surface);
            BRepGProp_Face properties(face);
            const int end = std::min(count, (index + 1) * block);
            for (int i = index * block; i < end; ++i) {
                const gp_Pnt point(points[3 * i], points[3 * i + 1], points[3 * i + 2]);
                distance.LoadS1(BRepBuilderAPI_MakeVertex(point).Vertex());
                if (!distance.Perform() || !distance.IsDone() || distance.NbSolution() < 1) {
                    throw user_error("OCCT could not project a point onto the face");
                }
                const gp_Pnt nearest = distance.PointOnShape2(1);
                double u = 0, v = 0;
                if (distance.SupportTypeShape2(1) == BRepExtrema_IsInFace) {
                    distance.ParOnFaceS2(1, u, v);
                } else {
                    const gp_Pnt2d found = analysis.ValueOfUV(nearest, 1e-7);
                    u = found.X();
                    v = found.Y();
                }
                if (u_periodic) {
                    u = wrapped(u, u_middle, u_period);
                }
                if (v_periodic) {
                    v = wrapped(v, v_middle, v_period);
                }
                gp_Pnt on;
                gp_Vec normal;
                properties.Normal(u, v, on, normal);
                double depth = 0;
                if (normal.Magnitude() > 1e-12) {
                    depth = gp_Vec(nearest, point).Dot(normal) / normal.Magnitude();
                }
                out[3 * i] = u;
                out[3 * i + 1] = v;
                out[3 * i + 2] = depth;
            }
        } catch (const user_error &error) {
            fail(error.what());
        } catch (const Standard_Failure &failure) {
            const char *text = failure.GetMessageString();
            fail(std::string("occt: ") + ((text && *text) ? text : "unknown exception"));
        } catch (const std::exception &error) {
            fail(std::string("occt: ") + error.what());
        } catch (...) {
            fail("occt: unknown exception");
        }
    }
};

} // namespace

extern "C" {

int occt_face_chart_info_of(const occt_shape *shape, int face_index, occt_face_chart_info *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        if (!out) {
            throw user_error("there is nowhere to put the face's parametrization");
        }
        const TopoDS_Face face = face_at(shape, face_index);
        const BRepAdaptor_Surface surface(face);
        double u0 = 0, u1 = 0, v0 = 0, v1 = 0;
        BRepTools::UVBounds(face, u0, u1, v0, v1);
        out->u_min = u0;
        out->u_max = u1;
        out->v_min = v0;
        out->v_max = v1;
        out->u_period = (surface.IsUPeriodic() && (u1 - u0) >= surface.UPeriod() * (1 - 1e-6)) ? surface.UPeriod() : 0;
        out->v_period = (surface.IsVPeriodic() && (v1 - v0) >= surface.VPeriod() * (1 - 1e-6)) ? surface.VPeriod() : 0;
        constexpr int steps = 12;
        double along_u = 0, along_v = 0;
        for (int i = 0; i < steps; ++i) {
            for (int j = 0; j < steps; ++j) {
                gp_Pnt on;
                gp_Vec du, dv;
                surface.D1(u0 + (u1 - u0) * (i + 0.5) / steps, v0 + (v1 - v0) * (j + 0.5) / steps, on, du, dv);
                along_u += du.Magnitude();
                along_v += dv.Magnitude();
            }
        }
        out->u_scale = along_u / (steps * steps) > 1e-9 ? along_u / (steps * steps) : 1;
        out->v_scale = along_v / (steps * steps) > 1e-9 ? along_v / (steps * steps) : 1;
        out->degenerate = 0;
        for (TopExp_Explorer edges(face, TopAbs_EDGE); edges.More(); edges.Next()) {
            if (BRep_Tool::Degenerated(TopoDS::Edge(edges.Current()))) {
                out->degenerate = 1;
            }
        }
        return 1;
    });
}

int occt_face_coordinates(const occt_shape *shape, int face_index, const double *points, int point_count, double *out,
                          occt_status *status) {
    return guarded(status, [&]() -> int {
        if (!points || !out || point_count < 0) {
            throw user_error("there are no points to project");
        }
        const TopoDS_Face face = face_at(shape, face_index);
        const BRepAdaptor_Surface adaptor(face);
        double u0 = 0, u1 = 0, v0 = 0, v1 = 0;
        BRepTools::UVBounds(face, u0, u1, v0, v1);
        FaceCoordinatesJob job{face,
                               BRep_Tool::Surface(face),
                               adaptor.IsUPeriodic(),
                               adaptor.IsVPeriodic(),
                               adaptor.IsUPeriodic() ? adaptor.UPeriod() : 0,
                               adaptor.IsVPeriodic() ? adaptor.VPeriod() : 0,
                               (u0 + u1) / 2,
                               (v0 + v1) / 2,
                               points,
                               out,
                               point_count};
        OSD_Parallel::For(0, job.blocks(), job, job.blocks() < 2);
        if (job.failed.load()) {
            throw user_error(job.message.c_str());
        }
        return 1;
    });
}

} // extern "C"
