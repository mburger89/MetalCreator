#include "cocct_internal.hpp"

#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepClass3d_SolidClassifier.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRep_Builder.hxx>
#include <Bnd_Box.hxx>
#include <OSD_Parallel.hxx>
#include <TopAbs_State.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Vertex.hxx>
#include <gp_Pnt.hxx>

#include <algorithm>
#include <atomic>
#include <mutex>
#include <string>

using namespace cocct;

namespace {

/// The distances from a run of points to one target, in blocks that OCCT's own thread pool shares out (`OSD_Parallel`). Each
/// block builds its own extrema and classifier objects, so the threads share only the shapes, which they read and never
/// change; the process-wide lock the caller holds keeps every other OCCT call out meanwhile. No exception leaves a worker: a
/// block that throws records its message and the rest stop.
struct DistanceBlocks {
    static constexpr int block = 64;

    const TopoDS_Shape &target;
    const TopoDS_Shape &solid;
    const double *points;
    double *out;
    int count;
    bool signed_solid;
    Bnd_Box bounds;
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
            distance.LoadS2(target);
            BRepClass3d_SolidClassifier classifier;
            bool loaded = false;
            const int end = std::min(count, (index + 1) * block);
            for (int i = index * block; i < end; ++i) {
                const gp_Pnt point(points[3 * i], points[3 * i + 1], points[3 * i + 2]);
                distance.LoadS1(BRepBuilderAPI_MakeVertex(point).Vertex());
                if (!distance.Perform() || !distance.IsDone()) {
                    throw user_error("OCCT could not measure the distance from a point");
                }
                double value = distance.Value();
                // Only a point inside the solid's bounds can be inside the solid; the others skip the classifier.
                if (signed_solid && !bounds.IsOut(point)) {
                    if (!loaded) {
                        classifier.Load(solid);
                        loaded = true;
                    }
                    classifier.Perform(point, 1e-7);
                    if (classifier.State() == TopAbs_IN) {
                        value = -value;
                    }
                }
                out[i] = value;
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

int occt_distances(const occt_shape *shape, int kind, const int *indices, int index_count, const double *points,
                   int point_count, int signed_distance, double *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        if (!shape || !points || !out || point_count < 0) {
            set_error(status, "there are no points to measure from");
            return 0;
        }
        // The target: every face of the shape, or the picked faces or edges (1-based, in the indexed maps).
        const bool edges = kind == 2;
        const TopTools_IndexedMapOfShape all = map_of(shape->shape, edges ? TopAbs_EDGE : TopAbs_FACE);
        TopoDS_Compound target;
        BRep_Builder builder;
        builder.MakeCompound(target);
        if (kind == 0) {
            for (int i = 1; i <= all.Extent(); ++i) {
                builder.Add(target, all(i));
            }
        } else {
            if (!indices || index_count <= 0) {
                throw user_error("nothing to measure to");
            }
            for (int i = 0; i < index_count; ++i) {
                if (indices[i] < 1 || indices[i] > all.Extent()) {
                    throw user_error(edges ? "edge index out of range" : "face index out of range");
                }
                builder.Add(target, all(indices[i]));
            }
        }
        // The sign of a solid's distance: inside is negative. Faces and edges are never signed.
        const bool signed_solid = signed_distance != 0 && kind == 0;
        DistanceBlocks job{target, shape->shape, points, out, point_count, signed_solid, Bnd_Box()};
        if (signed_solid) {
            BRepBndLib::AddOptimal(shape->shape, job.bounds, Standard_False, Standard_False);
            job.bounds.Enlarge(1e-6);
        }
        OSD_Parallel::For(0, job.blocks(), job, job.blocks() < 2);
        if (job.failed.load()) {
            throw user_error(job.message.c_str());
        }
        return 1;
    });
}

} // extern "C"
