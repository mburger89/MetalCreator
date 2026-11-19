// The splitter run shared by Trim Surface and Split Solid (NS-4, NS-5 R13 and R15). Not part of the public C API.
#ifndef COCCT_SPLITTER_HPP
#define COCCT_SPLITTER_HPP

#include "cocct_progress.hpp"

#include <BRepAlgoAPI_Splitter.hxx>
#include <TopTools_ListOfShape.hxx>

#include <memory>

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

} // namespace cocct

#endif
