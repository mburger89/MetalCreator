import CreatorGraph
import CreatorPCB
import Foundation
import Synchronization
import Testing
@testable import CreatorNodes

/// The board cache parses outside its actor: one slow board never holds up another.
struct KiCadBoardCacheTests {
    private func stamp(_ name: String) -> ImageStamp { .file(path: "/\(name)", modified: Date(timeIntervalSince1970: 0), size: 1) }

    private func parsed() -> ParsedBoard {
        ParsedBoard(board: KiCadBoard(), outline: BoardOutline(outer: [], holes: [], outerKeys: [], holeKeys: []))
    }

    /// Blocks the calling thread (a synchronous helper: the compiler refuses `wait` where `async` shows). Generous, because the
    /// slow read holds one of the shared pool's threads while it waits, and a loaded machine (Windows CI ran it at 148 s) may take
    /// long to give the fast board another; nothing else here blocks a pool thread.
    private static func arrived(_ semaphore: DispatchSemaphore) -> Bool { semaphore.wait(timeout: .now() + 300) == .success }

    @Test func aSlowParseDoesNotBlockAnotherBoard() async throws {
        let cache = KiCadBoardCache()
        let (slowStarted, started) = AsyncStream.makeStream(of: Void.self)
        let fastDone = DispatchSemaphore(value: 0)
        let board = parsed()
        async let slow: ParsedBoard = cache.board(for: stamp("slow")) {
            started.yield()
            started.finish()
            // Waits for the other board to finish; with the parse inside the actor that would never come.
            #expect(Self.arrived(fastDone))
            return board
        }
        // Waits without holding a thread, so the slow read's blocked thread is the only one taken from the pool.
        for await _ in slowStarted { break }
        _ = try await cache.board(for: stamp("fast")) { board }
        fastDone.signal()
        _ = try await slow
        #expect(await cache.count == 2)
    }

    private func board(_ size: Int) -> ParsedBoard {
        var made = parsed()
        made.board.embeddedModels = [EmbeddedFile(name: "m", base64: String(repeating: "A", count: size))]
        return made
    }

    @Test func theByteBudgetEvictsTheLeastRecentlyUsedAndKeepsTheNewest() async throws {
        let cache = KiCadBoardCache(budget: 2_500)
        for name in ["a", "b", "c"] { _ = try await cache.board(for: stamp(name)) { [small = board(1_000)] in small } }
        #expect(await cache.count == 2)
        let reads = Mutex(0)
        _ = try await cache.board(for: stamp("a")) { [small = board(1_000)] in reads.withLock { $0 += 1 }; return small }
        #expect(reads.withLock { $0 } == 1)
        // One board over the budget on its own is still kept.
        _ = try await cache.board(for: stamp("huge")) { [big = board(10_000)] in big }
        #expect(await cache.count == 1)
    }

    @Test func aBoardProblemIsRememberedAndTheSecondReadIsNotRun() async throws {
        let cache = KiCadBoardCache()
        let problem = KiCadProblem("nope")
        for attempt in 0..<2 {
            do {
                _ = try await cache.board(for: stamp("bad")) {
                    #expect(attempt == 0)
                    throw problem
                }
                Issue.record("should throw")
            } catch let thrown as KiCadProblem {
                #expect(thrown == problem)
            }
        }
        #expect(await cache.problemCount == 1)
    }
}
