import CreatorGraph
import Foundation

extension NodeInputs {
    /// The option index stored in the integer socket behind a segmented control (spec §6.4).
    func choice(_ name: SocketName, options: [String]) throws -> Int {
        let index = try integer(name)
        guard options.indices.contains(index) else {
            throw NodeError.invalidValue("Choose \(options.formatted(.list(type: .or).locale(.messages))) for “\(name)”.")
        }
        return index
    }
}
