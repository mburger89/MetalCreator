/// The plain inputs of `ZstdFixtures`: deterministic, so a test regenerates what a frame must decode to.
enum ZstdFixtureInputs {
    /// SplitMix64.
    struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    }

    static let tiny = Array("hello, zstd".utf8)

    /// A STEP-like text, the same few lines over and over.
    static var repetitive: [UInt8] {
        var text = "ISO-10303-21;\nHEADER;\n"
        for index in 0..<1500 { text += "#\(index * 7 % 13) = CARTESIAN_POINT('', (\(index % 5).0, \(index % 3).5, 0.0));\n" }
        return Array(text.utf8)
    }

    /// Words from a skewed vocabulary of 300, a line every twelve.
    static func text(seed: UInt64, size: Int) -> [UInt8] {
        var generator = Generator(state: seed)
        let words = vocabulary(&generator)
        var out = [UInt8]()
        var count = 0
        while out.count < size {
            let pick = generator.below(300) * generator.below(300) / 300
            out += words[pick]
            count += 1
            out.append(count % 12 == 0 ? 10 : 32)
        }
        return Array(out[0..<size])
    }

    /// Stretches of text, of random bytes, of copies of earlier output and of one repeated byte.
    static func mixed(seed: UInt64, size: Int) -> [UInt8] {
        var generator = Generator(state: seed)
        var out = [UInt8]()
        var piece = 0
        while out.count < size {
            let length = 800 + generator.below(5000)
            switch piece % 7 {
            case 1:
                out += (0..<length / 8).map { _ in UInt8(truncatingIfNeeded: generator.next()) }
            case 3 where out.count > length:
                let from = generator.below(out.count - length)
                out += out[from..<from + length]
            case 5:
                out += [UInt8](repeating: UInt8(truncatingIfNeeded: generator.next()), count: length)
            default:
                out += text(seed: generator.next(), size: length)
            }
            piece += 1
        }
        return Array(out[0..<size])
    }

    static func same(_ byte: UInt8, count: Int) -> [UInt8] { [UInt8](repeating: byte, count: count) }

    private static func vocabulary(_ generator: inout Generator) -> [[UInt8]] {
        (0..<300).map { _ in
            (0..<2 + generator.below(9)).map { _ in UInt8(97 + generator.below(26) * generator.below(26) / 26) }
        }
    }
}
