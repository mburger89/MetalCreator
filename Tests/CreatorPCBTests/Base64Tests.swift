import Foundation
import Testing
@testable import CreatorPCB

struct Base64Tests {
    private func decode(_ text: String, limit: Int = 1 << 20) -> String? {
        Base64.decode(text[...].utf8, limit: limit).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    @Test func rfcVectors() {
        let vectors = [
            ("", ""), ("Zg==", "f"), ("Zm8=", "fo"), ("Zm9v", "foo"), ("Zm9vYg==", "foob"),
                       ("Zm9vYmE=", "fooba"), ("Zm9vYmFy", "foobar"),
        ]
        for (encoded, plain) in vectors { #expect(decode(encoded) == plain) }
    }

    @Test func wrappedLinesAndWhitespace() {
        let bytes = Data((0..<500).map { UInt8($0 * 7 % 256) })
        let encoded = bytes.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        #expect(encoded.contains("\r\n"))
        #expect(Base64.decode(encoded[...].utf8, limit: 1000) == bytes)
        #expect(decode(" Zm9v \n Yg = = ") == "foob")
        #expect(decode("Zm9v\tYg==\n") == "foob")
    }

    @Test func badInput() {
        #expect(decode("Zm9v!") == nil)
        #expect(decode("Zm9") == nil)
        #expect(decode("Zg=") == nil)
        #expect(decode("Z===") == nil)
        #expect(decode("Zg==Zg==") == nil)
        #expect(decode("Zg=a") == nil)
        #expect(decode("Z") == nil)
        #expect(decode("Zm9vY") == nil)
        #expect(decode("é") == nil)
    }

    @Test func overLimitIsRefusedWithoutDecoding() {
        let big = String(repeating: "AAAA", count: 1_000_000)
        #expect(Base64.decode(big[...].utf8, limit: 10) == nil)
        #expect(Base64.decode(big[...].utf8, limit: 3_000_000)?.count == 3_000_000)
    }

    @Test func decodingSaysWhyItFailed() {
        #expect(Base64.decoding("Zm9v!"[...].utf8, limit: 10) == .failure(.malformed))
        #expect(Base64.decoding("Zm9vYmFy"[...].utf8, limit: 5) == .failure(.tooLarge))
        #expect(Base64.decoding("Zm9vYmFy"[...].utf8, limit: 6) == .success(Data("foobar".utf8)))
    }

    @Test func limit() {
        #expect(decode("Zm9vYmFy", limit: 6) == "foobar")
        #expect(decode("Zm9vYmFy", limit: 5) == nil)
        #expect(decode("Zm9vYg==", limit: 4) == "foob")
        #expect(decode("Zm9vYg==", limit: 3) == nil)
    }
}
