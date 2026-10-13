import CreatorGraph
import Synchronization

/// Decoded pictures kept by what they were read from (fields spec §5): an embedded image by its content hash, a linked file by
/// path, modification date and size (`ImageStamp`), so editing a linked file misses the cache and a node that is edited
/// downstream never decodes again. Least recently used pictures go first when the pictures kept pass `budgetBytes`.
///
/// A picture that could not be decoded is remembered too (`problem(for:)`), under the same stamp, so a damaged file that is
/// unchanged fails at once at every evaluation instead of being read and decoded again each time; it is retried as soon as
/// its stamp changes. At most `maxProblems` are kept, least recently used first. Shared by every document in the process,
/// because what it stores is a pure function of its key.
final class GreyImageCache: Sendable {
    /// How many failed pictures are remembered.
    static let maxProblems = 256

    /// The cache the Image Field node uses: 256 MB, room for two of the largest legal pictures.
    static let shared = GreyImageCache(budgetBytes: 256 * 1024 * 1024)

    private struct State {
        var entries: [ImageStamp: (image: GreyImage, lastUsed: Int)] = [:]
        var problems: [ImageStamp: (problem: ImageProblem, lastUsed: Int)] = [:]
        var clock = 0
    }

    let budgetBytes: Int
    private let state = Mutex(State())

    init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    /// The kept picture for `stamp`, marked as just used.
    func image(for stamp: ImageStamp) -> GreyImage? {
        state.withLock { state in
            guard let entry = state.entries[stamp] else { return nil }
            state.clock += 1
            state.entries[stamp] = (entry.image, state.clock)
            return entry.image
        }
    }

    /// Keeps `image` for `stamp`, dropping the least recently used pictures while the total is over budget. A picture bigger
    /// than the whole budget is not kept.
    func store(_ image: GreyImage, for stamp: ImageStamp) {
        guard image.byteCount <= budgetBytes else { return }
        state.withLock { state in
            state.clock += 1
            state.entries[stamp] = (image, state.clock)
            var total = state.entries.values.reduce(0) { $0 + $1.image.byteCount }
            while total > budgetBytes, let oldest = state.entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
                total -= oldest.value.image.byteCount
                state.entries[oldest.key] = nil
            }
        }
    }

    /// Why the picture for `stamp` could not be decoded, if that was found out before; marked as just used.
    func problem(for stamp: ImageStamp) -> ImageProblem? {
        state.withLock { state in
            guard let entry = state.problems[stamp] else { return nil }
            state.clock += 1
            state.problems[stamp] = (entry.problem, state.clock)
            return entry.problem
        }
    }

    /// Remembers that the picture for `stamp` is unusable, dropping the least recently used problems past `maxProblems`.
    func storeProblem(_ problem: ImageProblem, for stamp: ImageStamp) {
        state.withLock { state in
            state.clock += 1
            state.problems[stamp] = (problem, state.clock)
            while state.problems.count > Self.maxProblems,
                  let oldest = state.problems.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
                state.problems[oldest.key] = nil
            }
        }
    }

    /// How many failed pictures are remembered.
    var problemCount: Int { state.withLock { $0.problems.count } }

    /// How many pictures are kept.
    var count: Int { state.withLock { $0.entries.count } }
}
