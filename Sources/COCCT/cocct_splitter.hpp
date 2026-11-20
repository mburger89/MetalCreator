// The splitter run shared by Trim Surface and Split Solid (NS-4, NS-5 R13 and R15). Not part of the public C API.
#ifndef COCCT_SPLITTER_HPP
#define COCCT_SPLITTER_HPP

#include "cocct_progress.hpp"

#include <BRepAlgoAPI_Splitter.hxx>
#include <BRepClass_FaceClassifier.hxx>
#include <BRepTools.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <gp_Pnt2d.hxx>
#include <TopTools_ListOfShape.hxx>

#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>

namespace cocct {

struct SplitRun {
    std::unique_ptr<BRepAlgoAPI_Splitter> splitter;
    TopoDS_Shape whole;
};

/// `shape` divided by `tools`, never changing the arguments. Stops with `kCancelled` when `cancel` is set (polled before, inside
/// the algorithm through `progress_range`, and after); `failure` is the sentence it refuses with when the splitter fails.
inline SplitRun run_splitter(const TopoDS_Shape &shape, const TopTools_ListOfShape &tools, const occt_cancel *cancel,
                             const char *failure) {
    poll(cancel);
    SplitRun run;
    run.splitter = std::make_unique<BRepAlgoAPI_Splitter>();
    TopTools_ListOfShape arguments;
    arguments.Append(shape);
    run.splitter->SetArguments(arguments);
    run.splitter->SetTools(tools);
    run.splitter->SetRunParallel(Standard_False);
    run.splitter->SetNonDestructive(Standard_True);
    run.splitter->Build(progress_range(cancel));
    poll(cancel);
    if (!run.splitter->IsDone() || run.splitter->HasErrors()) {
        throw user_error(failure);
    }
    run.whole = run.splitter->Shape();
    return run;
}

/// For each shape of `sources` (the sheet's faces or edges), the shapes of the result it became, as the splitter's history says.
inline void source_map(BRepAlgoAPI_Splitter &splitter, const TopTools_IndexedMapOfShape &sources, const TopTools_IndexedMapOfShape &result,
                std::vector<int> &out) {
    out.assign(result.Extent(), 0);
    for (int i = 1; i <= sources.Extent(); ++i) {
        const TopoDS_Shape &source = sources(i);
        const TopTools_ListOfShape &modified = splitter.Modified(source);
        if (modified.IsEmpty()) {
            if (!splitter.IsDeleted(source)) {
                const int index = result.FindIndex(source);
                if (index > 0) {
                    out[index - 1] = i;
                }
            }
            continue;
        }
        for (TopTools_ListOfShape::Iterator it(modified); it.More(); it.Next()) {
            const int index = result.FindIndex(it.Value());
            if (index > 0) {
                out[index - 1] = i;
            }
        }
    }
}

/// A parameter pair strictly inside `face`: the UV box sampled 8 x 8, then 32 x 32, then 128 x 128, the inside sample nearest the box's middle.
inline bool interior_uv(const TopoDS_Face &face, double &best_u, double &best_v) {
    double u0 = 0;
    double u1 = 0;
    double v0 = 0;
    double v1 = 0;
    BRepTools::UVBounds(face, u0, u1, v0, v1);
    for (const int n : {8, 32, 128}) {
        bool found = false;
        double best = 0;
        for (int i = 0; i < n; ++i) {
            for (int j = 0; j < n; ++j) {
                const double u = u0 + (i + 0.5) / n * (u1 - u0);
                const double v = v0 + (j + 0.5) / n * (v1 - v0);
                BRepClass_FaceClassifier classifier;
                classifier.Perform(face, gp_Pnt2d(u, v), 1e-7);
                if (classifier.State() != TopAbs_IN) {
                    continue;
                }
                const double d = std::hypot((u - 0.5 * (u0 + u1)) / std::max(u1 - u0, 1e-12),
                                            (v - 0.5 * (v0 + v1)) / std::max(v1 - v0, 1e-12));
                if (!found || d < best) {
                    found = true;
                    best = d;
                    best_u = u;
                    best_v = v;
                }
            }
        }
        if (found) {
            return true;
        }
    }
    return false;
}

} // namespace cocct

#endif
