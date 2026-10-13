import Foundation

/// The document's `images` table as it is written (fields spec §5): the file's own PNG or JPEG bytes in base64, keyed by the
/// SHA-256 of the bytes. Reading is forgiving, because a damaged picture must not cost the person the rest of the document:
/// an entry whose key is not a hash, whose text is not base64, whose bytes pass 16 MB or do not hash to their key is left out,
/// and a node that points at it says its image is missing. Each entry is judged alone: a value that is not even a string
/// (a number, a list) costs that picture and no other. A save writes the table again from the pictures the nodes use, so a
/// damaged entry that was left out is gone from the file for good once the person saves.
enum ImageTable {
    /// One value of the table as it is read: its text, or `nil` when the value is not a string.
    struct Entry: Decodable {
        let text: String?

        init(from decoder: any Decoder) {
            text = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    static func encode(_ images: [ImageHash: Data]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: images.map { ($0.key.hex, $0.value.base64EncodedString()) })
    }

    static func decode(_ table: [String: Entry]) -> [ImageHash: Data] {
        var images: [ImageHash: Data] = [:]
        for (key, entry) in table {
            guard let text = entry.text, let hash = ImageHash(hex: key), text.utf8.count <= ImageLimits.maxBytes * 4 / 3 + 4,
                  let data = Data(base64Encoded: text), data.count <= ImageLimits.maxBytes,
                  ImageHash(of: data) == hash else { continue }
            images[hash] = data
        }
        return images
    }
}
