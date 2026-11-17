import CreatorGraph
import CreatorPCB
import Foundation

/// The SHA-256 of each stored model's base64 text (ruling R3), computed when a model is first used and kept with the parsed board,
/// so an evaluation that reads the cached board never hashes a stored model again, and a board whose components are off never does.
final class StoredModelHashes: @unchecked Sendable {  // Every access to the mutable state is under `lock`.
    private let lock = NSLock()
    private var hashes: [Key: ImageHash] = [:]
    private var made = 0

    private struct Key: Hashable {
        /// The footprint's index, or -1 for the board's own table.
        var owner: Int
        var name: String
    }

    init() {}

    /// The hash of `file`, a stored model of footprint `owner` (nil: the board's table).
    func hash(of file: EmbeddedFile, owner: Int?) -> ImageHash {
        let key = Key(owner: owner ?? -1, name: file.name)
        lock.lock()
        if let kept = hashes[key] {
            lock.unlock()
            return kept
        }
        lock.unlock()
        let hash = ImageHash(ofUTF8: file.base64)
        lock.lock()
        hashes[key] = hash
        made += 1
        lock.unlock()
        return hash
    }

    /// How many hashes were computed (not served from memory): what the tests count.
    var computed: Int {
        lock.lock()
        defer { lock.unlock() }
        return made
    }
}
