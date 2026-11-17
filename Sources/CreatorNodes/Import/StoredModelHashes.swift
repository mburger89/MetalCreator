import CreatorGraph
import CreatorPCB
import Foundation
import Synchronization

/// The SHA-256 of each stored model's base64 text (ruling R3), computed when a model is first used and kept with the parsed board,
/// so an evaluation that reads the cached board never hashes a stored model again, and a board whose components are off never does.
final class StoredModelHashes: Sendable {
    private struct Key: Hashable {
        /// The footprint's index, or -1 for the board's own table.
        var owner: Int
        var name: String
    }

    private struct State {
        var hashes: [Key: ImageHash] = [:]
        var made = 0
    }

    private let state = Mutex(State())

    init() {}

    /// The hash of `file`, a stored model of footprint `owner` (nil: the board's table). Hashed outside the lock, so two
    /// evaluations of one new model may both hash it; the first result is kept.
    func hash(of file: EmbeddedFile, owner: Int?) -> ImageHash {
        let key = Key(owner: owner ?? -1, name: file.name)
        if let kept = state.withLock({ $0.hashes[key] }) { return kept }
        let hash = ImageHash(ofUTF8: file.base64)
        return state.withLock { state in
            if let kept = state.hashes[key] { return kept }
            state.hashes[key] = hash
            state.made += 1
            return hash
        }
    }

    /// How many hashes were computed and kept (not served from memory): what the tests count.
    var computed: Int { state.withLock { $0.made } }
}
