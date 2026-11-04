import Foundation

/// The zip's entries by name, built once so that finding a part is a dictionary lookup, however many entries the file lists and however
/// many ways the root spells a name (mesh import spec, Errata (3MF parts)). Names are Open Packaging part names: exact, else
/// percent-decoded, else ignoring case. When two entries share a key the first in the zip's order wins, so the answer never depends on
/// the platform. An entry whose name is not UTF-8 reads as "" (`ZipReader`) and is never found.
struct PartNames {
    /// Lookups between asks about cancellation.
    static let lookupInterval = 256
    private static let buildInterval = 1 << 16

    private var exact: [String: Int] = [:]
    private var folded: [String: Int] = [:]
    private let entries: [ZipReader.Entry]

    init(_ zip: ZipReader, isCancelled: () -> Bool) throws {
        entries = zip.entries
        for (index, entry) in entries.enumerated() {
            if index % Self.buildInterval == 0, isCancelled() { throw CancellationError() }
            guard !entry.name.isEmpty else { continue }
            if exact[entry.name] == nil { exact[entry.name] = index }
            let key = entry.name.lowercased()
            if folded[key] == nil { folded[key] = index }
        }
    }

    /// The entry named `name`: exactly, else percent-decoded, else ignoring case, the decoded form first.
    func entry(named name: String) -> ZipReader.Entry? {
        let decoded = name.removingPercentEncoding
        let candidates = [name] + (decoded.map { $0 == name ? [] : [$0] } ?? [])
        for candidate in candidates {
            if let index = exact[candidate] { return entries[index] }
        }
        for candidate in candidates {
            if let index = folded[candidate.lowercased()] { return entries[index] }
        }
        return nil
    }
}
