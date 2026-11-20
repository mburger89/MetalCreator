// A progress indicator that stops OpenCascade's long algorithms on a caller's cancel flag (NS-5, R15). Not part of the public C API.
#ifndef COCCT_PROGRESS_HPP
#define COCCT_PROGRESS_HPP

#include "cocct_sheet.hpp"

#include <Message_ProgressIndicator.hxx>
#include <Message_ProgressRange.hxx>
#include <Message_ProgressScope.hxx>

namespace cocct {

/// An indicator whose `UserBreak()` is true once the `occt_cancel` flag is set. Sewing, the splitter and the offset take its range
/// and stop between their steps; the caller then `poll`s the flag and throws `kCancelled`.
class cancel_progress : public Message_ProgressIndicator {
public:
    explicit cancel_progress(const occt_cancel *cancel) : cancel_(cancel) {}

    Standard_Boolean UserBreak() override {
        return cancel_ != nullptr && cancel_->flag.load() != 0;
    }

    void Show(const Message_ProgressScope &, const Standard_Boolean) override {}

private:
    const occt_cancel *cancel_;
};

/// The range of an indicator that watches `cancel`; an empty range (no watching) when `cancel` is null. The indicator is kept in
/// a thread-local handle, so the range stays valid until the next call on the same thread; every caller runs under
/// `OCCTKernel.serialized` and uses the range before making another.
inline Message_ProgressRange progress_range(const occt_cancel *cancel) {
    static thread_local opencascade::handle<cancel_progress> indicator;
    if (cancel == nullptr) {
        return Message_ProgressRange();
    }
    indicator = new cancel_progress(cancel);
    return Message_ProgressIndicator::Start(indicator);
}

} // namespace cocct

#endif
