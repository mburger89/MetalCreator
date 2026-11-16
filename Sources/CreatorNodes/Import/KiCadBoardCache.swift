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

    /// The board for `stamp`: the kept one, else what `read` makes (and keeps, when the stamp names a definite thing).
    func board(for stamp: ImageStamp, read: @Sendable () throws -> ParsedBoard) throws -> ParsedBoard {
        clock += 1
        if let kept = entries[stamp] {
            entries[stamp] = (kept.parsed, clock)
            return kept.parsed
        }
        if let known = problems[stamp] {
            problems[stamp] = (known.problem, clock)
            throw known.problem
        }
        do {
            let made = try read()
            if stamp.isKeepable { keep(made, for: stamp) }
            return made
        } catch let problem as KiCadProblem {
            if stamp.isKeepable { keepProblem(problem, for: stamp) }
            throw problem
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
