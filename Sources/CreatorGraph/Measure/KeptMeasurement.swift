import Foundation

/// A measurement the person kept, saved with the document's view state: one or two anchors and an identity.
/// Reading a file drops a measurement that does not decode or does not have one or two anchors.
public struct KeptMeasurement: Hashable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var anchors: [MeasureAnchor]

    public init(id: UUID = UUID(), anchors: [MeasureAnchor]) {
        self.id = id
        self.anchors = anchors
    }

    private enum CodingKeys: String, CodingKey { case id, anchors }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        anchors = try container.decode([MeasureAnchor].self, forKey: .anchors)
        guard (1...2).contains(anchors.count) else {
            throw DecodingError.dataCorruptedError(forKey: .anchors, in: container,
                                                   debugDescription: "A measurement has one or two anchors.")
        }
    }
}

/// Decodes an element or, when it is damaged, nothing, so one bad entry does not lose the rest of an array.
struct LossyElement<Element: Decodable>: Decodable {
    var value: Element?

    init(from decoder: any Decoder) throws {
        value = try? Element(from: decoder)
    }
}
