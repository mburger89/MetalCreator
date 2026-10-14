import Foundation

/// What the first bytes of a picture file say, read without decoding a pixel (fields spec §5): the format, the stored size and the
/// EXIF orientation tag. It exists so the limits (`ImageLimits`) can be checked before MetalUI's decoder allocates anything, and
/// reads the same tag MetalUI's `DecodedImage.orientation` reports (the first `Exif` APP1 segment before a JPEG's first scan; a
/// PNG's first `eXIf` chunk before the first `IDAT`, else the first after the last one). `GreyImageDecoder.decode` checks that
/// the decoded size agrees with this reading, so a disagreement is a refusal and never a wrong grid.
///
/// Every read is bounds-checked: a truncated or hostile header gives `nil`, never a trap.
struct ImageHeader: Equatable {
    /// The kind of file the signature names.
    enum Kind: Equatable {
        case png, jpeg
        /// A picture format that is recognised and refused: GIF, TIFF, BMP, WebP, HEIF.
        case other
    }

    let kind: Kind
    /// The stored size, before the orientation is applied; 0 for `.other`.
    let width: Int
    let height: Int
    /// The EXIF/TIFF orientation tag, 1 (upright) to 8.
    let orientation: Int

    /// The header of `data`, or `nil` when it is no picture this reader knows or its header is cut short or has a zero side.
    static func read(_ data: Data) -> ImageHeader? {
        data.withUnsafeBytes { bytes in
            if bytes.starts(with: pngSignature) { return readPNG(bytes) }
            if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF { return readJPEG(bytes) }
            return isOtherPicture(bytes) ? ImageHeader(kind: .other, width: 0, height: 0, orientation: 1) : nil
        }
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static func isOtherPicture(_ bytes: UnsafeRawBufferPointer) -> Bool {
        func starts(_ text: String, at offset: Int = 0) -> Bool {
            let wanted = Array(text.utf8)
            return bytes.count >= offset + wanted.count && bytes[offset..<(offset + wanted.count)].elementsEqual(wanted)
        }
        return starts("GIF87a") || starts("GIF89a") || starts("BM") || starts("II*\0") || starts("MM\0*")
            || (starts("RIFF") && starts("WEBP", at: 8)) || starts("ftyp", at: 4)
    }

    private static func read16(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> Int {
        Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    private static func read32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> Int {
        read16(bytes, offset) << 16 | read16(bytes, offset + 2)
    }

    // MARK: PNG

    private static func readPNG(_ bytes: UnsafeRawBufferPointer) -> ImageHeader? {
        // IHDR is the first chunk: length 13, "IHDR", width, height.
        guard bytes.count >= 24, read32(bytes, 8) == 13, bytes[12...15].elementsEqual(Array("IHDR".utf8)) else { return nil }
        let width = read32(bytes, 16), height = read32(bytes, 20)
        guard width >= 1, height >= 1 else { return nil }
        var offset = 8
        var seenData = false
        var afterData: Range<Int>?
        while offset <= bytes.count - 12 {
            let length = read32(bytes, offset)
            guard length <= bytes.count - offset - 12 else { break }
            let type = Array(bytes[(offset + 4)..<(offset + 8)])
            let body = (offset + 8)..<(offset + 8 + length)
            if type == Array("IDAT".utf8) {
                seenData = true
                afterData = nil
            } else if type == Array("eXIf".utf8) {
                if !seenData { afterData = body; break }
                if afterData == nil { afterData = body }
            } else if type == Array("IEND".utf8) {
                break
            }
            offset += 12 + length
        }
        let tag = afterData.flatMap { tiffOrientation(UnsafeRawBufferPointer(rebasing: bytes[$0])) } ?? 1
        return ImageHeader(kind: .png, width: width, height: height, orientation: tag)
    }

    // MARK: JPEG

    private static func readJPEG(_ bytes: UnsafeRawBufferPointer) -> ImageHeader? {
        var offset = 2
        var size: (width: Int, height: Int)?
        var tag: Int?
        while true {
            guard offset <= bytes.count - 2, bytes[offset] == 0xFF else { break }
            let marker = bytes[offset + 1]
            if marker == 0xFF { offset += 1; continue }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { offset += 2; continue }
            if marker == 0xD8 || marker == 0xD9 || marker == 0xDA { break }  // SOI, EOI, start of scan
            guard offset <= bytes.count - 4 else { break }
            let length = read16(bytes, offset + 2)
            guard length >= 2, length <= bytes.count - offset - 2 else { break }
            let payload = offset + 4
            // SOFn carries precision (1), height (2) and width (2); C4, C8 and CC are not frame headers.
            if (0xC0...0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker), size == nil, length >= 8 {
                size = (read16(bytes, payload + 3), read16(bytes, payload + 1))
            }
            if marker == 0xE1, tag == nil, let found = exifOrientation(inSegment: bytes, payload: payload, end: offset + 2 + length) {
                tag = found
            }
            offset += 2 + length
        }
        guard let size, size.width >= 1, size.height >= 1 else { return nil }
        return ImageHeader(kind: .jpeg, width: size.width, height: size.height, orientation: tag ?? 1)
    }

    // MARK: EXIF

    /// The orientation of an APP1 segment (`payload` to `end`) if it is an `Exif` one, 1 when it is but holds no usable tag, else
    /// `nil` (some other APP1, such as XMP, so the walk goes on: the first `Exif` segment decides).
    private static func exifOrientation(inSegment bytes: UnsafeRawBufferPointer, payload: Int, end: Int) -> Int? {
        guard end - payload >= 6, bytes[payload..<(payload + 6)].elementsEqual([0x45, 0x78, 0x69, 0x66, 0, 0]) else { return nil }
        return tiffOrientation(UnsafeRawBufferPointer(rebasing: bytes[(payload + 6)..<end])) ?? 1
    }

    /// Orientation tag 0x0112 of IFD0 in a TIFF block (`II*\0` or `MM\0*`): type SHORT, count 1, value 1 to 8; otherwise `nil`.
    /// Only IFD0 is read and the entry count is clamped to the bytes left, so no loop and no read past the block is possible.
    private static func tiffOrientation(_ bytes: UnsafeRawBufferPointer) -> Int? {
        guard bytes.count >= 8 else { return nil }
        let little: Bool
        if bytes[0] == 0x49, bytes[1] == 0x49 {
            little = true
        } else if bytes[0] == 0x4D, bytes[1] == 0x4D {
            little = false
        } else {
            return nil
        }
        func short(_ offset: Int) -> Int? {
            guard offset >= 0, offset <= bytes.count - 2 else { return nil }
            return little ? Int(bytes[offset + 1]) << 8 | Int(bytes[offset]) : Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        func long(_ offset: Int) -> Int? {
            guard let first = short(offset), let second = short(offset + 2) else { return nil }
            return little ? second << 16 | first : first << 16 | second
        }
        guard short(2) == 42, let ifd = long(4), let declared = short(ifd) else { return nil }
        let first = ifd + 2
        let entries = min(declared, (bytes.count - first) / 12)
        for index in 0..<entries {
            let entry = first + index * 12
            guard short(entry) == 0x0112 else { continue }
            guard short(entry + 2) == 3, long(entry + 4) == 1, let value = short(entry + 8), (1...8).contains(value) else { return nil }
            return value
        }
        return nil
    }
}
