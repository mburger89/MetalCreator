/// Where an Image Field's picture lives (fields spec §5), stored as the node's `NodeSetting.image`.
public enum ImageReference: Hashable, Sendable {
    /// The file's own PNG or JPEG bytes, stored in the document's `images` table under their hash.
    case embedded(ImageHash)
    /// A file beside the document or elsewhere. `relativePath` is relative to the document's folder and is `nil` until the
    /// document has been saved; `absolutePath` is the fallback when the relative one finds nothing.
    case linked(relativePath: String?, absolutePath: String)

    public var isEmbedded: Bool {
        if case .embedded = self { true } else { false }
    }

    /// The hash of an embedded image.
    public var hash: ImageHash? {
        if case .embedded(let hash) = self { hash } else { nil }
    }

    /// The name of a linked file ("vent-mask.png"); `nil` for an embedded image, which has none.
    public var fileName: String? {
        guard case .linked(let relative, let absolute) = self else { return nil }
        let name = (relative ?? absolute).split(separator: "/").last.map(String.init)
        return name?.isEmpty == false ? name : absolute
    }
}
