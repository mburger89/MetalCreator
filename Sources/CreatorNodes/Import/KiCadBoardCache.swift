import CreatorGraph
import CreatorPCB

/// A board file read, keyed, and its outline chained: what the Import KiCad Board node keeps between evaluations.
struct ParsedBoard: Sendable {
    var board: KiCadBoard
    var outline: BoardOutline
}

/// Parsed boards kept by what they were read from (`ImageStamp`: a linked file's path, modification date and size), so moving or
/// turning the board never reads the file again. Least recently used boards go first past `maxBoards`. A file whose contents are
/// wrong is remembered under its stamp and fails at once until the stamp changes (at most `maxProblems`); a file that could not be
/// reached (missing, unreadable) is tried again every time, since fixing that changes no stamp.
actor KiCadBoardCache {
    static let maxBoards = 8
    static let maxProblems = 256
    static let shared = KiCadBoardCache()

    private var entries: [ImageStamp: (parsed: ParsedBoard, lastUsed: Int)] = [:]
    private var problems: [ImageStamp: (problem: KiCadProblem, lastUsed: Int)] = [:]
    private var clock = 0

    init() {}

    /// The board for `stamp`: the kept one, else what `read` makes (and keeps, when the stamp names a definite thing). The parse runs
    /// outside the actor, so one slow board never holds up another; two evaluations of one new board may both parse it.
    nonisolated func board(for stamp: ImageStamp, read: @Sendable () throws -> ParsedBoard) async throws -> ParsedBoard {
        if let kept = try await lookup(stamp) { return kept }
        let outcome = Self.attempt(read)
        await record(outcome, for: stamp)
        return try outcome.get()
    }

    /// Reads synchronously (no locals held across an `await`); only a board's own problem is kept as a result.
    private static func attempt(_ read: () throws -> ParsedBoard) -> Result<ParsedBoard, any Error> {
        Result { try read() }
    }

    private func lookup(_ stamp: ImageStamp) throws -> ParsedBoard? {
        clock += 1
        if let kept = entries[stamp] {
            entries[stamp] = (kept.parsed, clock)
            return kept.parsed
        }
        if let known = problems[stamp] {
            problems[stamp] = (known.problem, clock)
            throw known.problem
        }
        return nil
    }

    private func record(_ outcome: Result<ParsedBoard, any Error>, for stamp: ImageStamp) {
        guard stamp.isKeepable else { return }
        switch outcome {
        case .success(let made): keep(made, for: stamp)
        case .failure(let error): if let problem = error as? KiCadProblem { keepProblem(problem, for: stamp) }
        }
    }

    private func keep(_ made: ParsedBoard, for stamp: ImageStamp) {
        clock += 1
        entries[stamp] = (made, clock)
        while entries.count > Self.maxBoards, let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            entries[oldest.key] = nil
        }
    }

    private func keepProblem(_ problem: KiCadProblem, for stamp: ImageStamp) {
        clock += 1
        problems[stamp] = (problem, clock)
        while problems.count > Self.maxProblems, let oldest = problems.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            problems[oldest.key] = nil
        }
    }

    var count: Int { entries.count }
    var problemCount: Int { problems.count }
}
