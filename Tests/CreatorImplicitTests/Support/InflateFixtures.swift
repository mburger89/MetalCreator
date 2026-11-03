import Foundation

/// Streams made outside Swift (zlib and a hand-written encoder, `scratchpad/inflate-fix/mk.py`), pinned as base64 so every platform
/// decodes the same bytes. Expected output is zlib's; `nil` is a stream zlib refuses.
enum InflateFixtures {
    struct Hostile: Sendable, CustomStringConvertible {
        let name: String
        let stream: [UInt8]
        let expected: Data?
        var description: String { name }
        init(_ name: String, _ stream: [String], _ expected: Data?) {
            self.name = name
            self.stream = InflateFixtures.bytes(stream)
            self.expected = expected
        }
    }

    static func bytes(_ base64: [String]) -> [UInt8] {
        [UInt8](Data(base64Encoded: base64.joined()) ?? Data())
    }

    /// A dynamic block (BTYPE 2) zlib wrote, with run-length coded lengths: its data is `zlibDynamicPlain`.
    static let zlibDynamic = bytes([
            "hYyxDQMBDAJXyWqAwRQv/f5dXKYLBQW6g5OGZO1RNulG00l2R9U6jGt5ItrdxWHsHIsV7NPaAEMH0xMGVO5E5orw4i5zqRujQuvn",
            "eT8//X/4Ag==",
        ])
    static var zlibDynamicPlain: Data { Data(bytes([
            "YmRmaGZiYmJoZWVkY2ZnZmZoZ2ZjZGhkZmZnZ2RjaGNnZWZiZmVoZWNlZGZjYmVlaGdnYWZnZmJoZGdmZmFnY2FlZWNmZ2hoZmFh",
            "ZGJlZmFkaGVmYmRhYmNmZGhkY2ViZ2NiYWVnYWNkaGZmZmZoZWhmZWFoY2FoaGVsbG8gaGVsbG8gaGVsbG9oZWxsbyBoZWxsbyBo",
            "ZWxsb2hlbGxvIGhlbGxvIGhlbGxv",
        ])) }
    static let zlibDynamicHash = "acb95f62162ce54251b7189121a220332b9bada85574b0b38f931981947f4be0"

    /// Four pieces in one stream, written by Python's zlib with a full flush between them: a fixed block, a dynamic block, a fixed block
    /// and a final stored block (each flush adds an empty stored block). Its data is `mixedBlocksPlain`.
    static let mixedBlocks = bytes([
            "SsusSE1RSMrJT85WyM9L1VFIQxVQRBcgSwUAAAD//6xQMbJDQQi6Sq4mIFJk5t+/Cy9t2r+FM4uKgHkDeDS4g9Cf5vrlHrGEDIxyTryi",
            "sHEWOJrptN0OimI2e56YyGipu6Azyyt+Ikhpwt3h2ZxcH8oiKKwKzLfquKUF0rcotuGoG4s1LUs6KZ7nqBwbD0cbqYCqK98Zl+tRDsPK",
            "4gzYtVl1p/7GuaLl7lAN9ORIO9WPWJt0sETlKX/jqRZzmeYUivfY6ml3M3NuLGoUtff13Jt4rLZg29nyunHULotrq6NpeHamEStlzb7f",
            "f6+f+i/wBwAA//8qTk3Oz0tRSMusSE2xUqiorELGegAAAAD//wEcAOP/c3RvcmVkIHRhaWwsIHN0b3JlZCB0YWlsIDEyMw==",
        ])
    static var mixedBlocksPlain: Data { Data(bytes([
            "Zml4ZWQgYmxvY2sgb25lLCBmaXhlZCBibG9jayBvbmUhIGZpeGVkIGJsb2NrIG9uZSwgZml4ZWQgYmxvY2sgb25lISBmaXhlZCBibG9j",
            "ayBvbmUsIGZpeGVkIGJsb2NrIG9uZSEgZmNnYWJiZmFkYWJnZ2JkYmdhYmRhZ2FkYWNlZ2NiZWNiZGZiYmFkaGdmaGhmZWRjZGJlaGZo",
            "ZWJiZ2NmY2hnYWJmZmZoaGJiZWhiYWVoZWdmYWhmY2JoYWRlY2RnZ2hiY2hnZWNnZWdmZ2RjYmNjZGRhaGNlZWFjZ2ZmY2FoZ2dnZ2Jo",
            "Z2FkYmRoY2JmYWJhY2JmYWJkZ2NlZmZoYmJoaGhoZWJjYmZlaGNhZGZjYWViZWZjZmRmZGRkZ2RkaGZhYWVoZWRmaGZmYmRiZGhkZmRo",
            "YWhmYmJnZGhjZ2ZiZ2hnYmNjY2FjaGNoZmNjYWFiY2dkZGFlZGVkZmVnY2FmaGdjY2FoY2FjY2NoYmFmaGJhZGRlYWJoYWJoZmRlaGhk",
            "ZWRoY2diZ2hmYmRnYmRlYmNmY2VjaGRiZ2hjZGNnZ2ZnZGZmYmZhZmhoYWdmZWJiZGJiZWVhY2VjZ2VnY2hmYmVhY2diZWFiZWJkYmVi",
            "aGFmZ2VjYWRiY2VhY2RlZWRlaGNlZmFlYWFhZGhkaGJnaGhlbGxvIGhlbGxvIGhlbGxvIGhlbGxvaGVsbG8gaGVsbG8gaGVsbG8gaGVs",
            "bG9oZWxsbyBoZWxsbyBoZWxsbyBoZWxsb2hlbGxvIGhlbGxvIGhlbGxvIGhlbGxvc2Vjb25kIGZpeGVkOiB4eXogeHl6IHh5eiB4eXou",
            "c3RvcmVkIHRhaWwsIHN0b3JlZCB0YWlsIDEyMw==",
        ])) }

    /// A dynamic block written by hand: 33 KB of output from 300 literals, then matches of every length symbol's first and last length
    /// against every distance symbol's first and last distance (all 29 length and 30 distance symbols, distances to 32,768).
    static let everySymbol = bytes([
            "7f3bkiRJkizLZgREgmdGRERmQEBGZiZkJDhAQkBmZkBmREREOkRCRDg4RGQEBEQGREZGAEBkZkJkREJGZEJCQkQkBGRmJgQAZAZk",
            "RERkQGZAJmSERyZERgSEZwBEQCQkZGZGRjokJERCRGYGpENCRCQkBHhAhGdCRmRCAkRkOERGBkSCRwakA0SkR0RERERERERERERE",
            "RCSZmZmZmamZmaGaqZmZmZm55DhGVWu/RevtcEqxr1+pzT5TFlMgL9n2aJc0Re2VZVz0sqlmd3mns0pbFletMY5y2+j4ucWr7by4",
            "sSWmIlNT8eVUWpLBWh/13xcn49ubO2rNUu+r7b/GNQSpNMJrna/sTlR61wtsVjTsDLvsapEkP6CfrfWIanVPta466JFRqfAJLRGI",
            "FFabnhaamPzOu1efK+5oDvQ9XftQfXFruVnoofUbGkL+GLpFevoHK66rlNtLM4KfHE742aFM+XUkt+276w3b8Av6Nj/yPwaZFPoV",
            "RjjdDE9LcndItKsLFG2RHxNlJwulMv/4WKGgMlYpsLS7ZJQltn0mazT/IIto+uRaHKOQyi3rjG/lp4rvVuUYPg7bvDdA7GIueZ5u",
            "qpLIlaWvo6vPSoJMy67uP2e0KhkrrLDCCiussMIKK6ywwgorrLDCCiussMIKK6ywwgorrLDCCiussMIKK6ywwgorrLDCCiussMIK",
            "K6ywwgorrLDCCiussMIKK6ywwgorrLDCCiussMIKK6ywwgorrLDCCiussMIKK6ywwgorrLDCCiussMIKK6ywwgorrLDCCiussMIK",
            "K6ywwgorrLDCCiussMIKK6ywwgorrLDCCiussEqcxgrgOQ8HAA7dxerx5z9Sl2XO//G/RX/z+/6GN0v//r/fzLf/PePMgPXQ/l5D",
            "eihGGcGDRXABIH7i5c+agx3AuhlsAMfHnn7Awp//Sxf/9f87Iwa4vQRuAMh7yn19tXf/wQsAIbrv/xsM7q7pKWu6/v8vXwYPAASO",
            "HH7N6OM/2luVLcAJgPdAS8Dc7/9NdT8AcB5o19NlxV25kPf/iybvn778n/+PGB7elw8AXJkEgGT2039RV5439fhv76uLugur6a//",
            "b2chAUjoraQPC+AyqEPBGBNonWABOqcQAf8A",
        ])
    static let everySymbolSize = 36574
    static let everySymbolHash = "f756ad5d5d9df65a8bcfa22a67f4c4a1c104f938c9820da0d4e0f9f52636c762"

    static let hostile: [Hostile] = [
        Hostile("hlit 287", [
            "9eDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAgAAAAAAAAAAAAAA",
            "AAAAAA==",
        ], nil),
        Hostile("hlit 288", [
            "/eDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAgAAAAAAAAAAAAAA",
            "AAAAAA==",
        ], nil),
        Hostile("hdist 31", [
            "Df7bkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAgAAAAAAAAAAAAAA",
            "AAAAAA==",
        ], nil),
        Hostile("hdist 32", [
            "Df/bkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAgAAAAAAAAAAAAAA",
            "AAAAAAA=",
        ], nil),
        Hostile("16 first", [
            "BeDbkiRJkizLXgAAAAAAAAAAAA==",
        ], nil),
        Hostile("17 past total", [
            "BeDbkiRJkizL/v///z8AAAAAAAAAAA==",
        ], nil),
        Hostile("18 exactly to the end, no eob", [
            "BeDbkiRJkizL/v8HAAAAAAAAAAAA",
        ], nil),
        Hostile("16 crossing lit/dist boundary", [
            "BeDbkiRJkizL/v9XI14AAAAAAAAAAAA=",
        ], nil),
        Hostile("lit incomplete", [
            "DeDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAQ==",
        ], nil),
        Hostile("lit over", [
            "BeDbkiRJkizLIiIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgBA==",
        ], nil),
        Hostile("two dist, incomplete", [
            "DeHbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQEg0=",
        ], nil),
        Hostile("dist over-subscribed", [
            "DeLbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQIuI=",
        ], nil),
        Hostile("lone dist of length 2", [
            "DeDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQ0g==",
        ], nil),
        Hostile("lone dist 1-bit match", [
            "DeDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQYgw=",
        ], Data(bytes([
            "YWFhYQ==",
        ]))),
        Hostile("lone dist, the unused code", [
            "DeDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQYg4=",
        ], nil),
        Hostile("no dist codes, literals only", [
            "DeDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQQgM=",
        ], Data(bytes([
            "YQ==",
        ]))),
        Hostile("no dist codes, a match", [
            "DeDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQQgw=",
        ], nil),
        Hostile("no eob code", [
            "BeDbkiRJkizLIgIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
        ], nil),
        Hostile("lone eob, the unused code", [
            "BeDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgBA==",
        ], nil),
        Hostile("fixed 286", [
            "SxwDAA==",
        ], nil),
        Hostile("fixed 287", [
            "SxwHAA==",
        ], nil),
        Hostile("fixed dist 30", [
            "SwQ+AA==",
        ], nil),
        Hostile("fixed dist 31", [
            "SwR+AA==",
        ], nil),
        Hostile("fixed dist=produced+1", [
            "SwRCAA==",
        ], nil),
        Hostile("fixed dist=produced overlap", [
            "SwQCAA==",
        ], Data(bytes([
            "YWFhYQ==",
        ]))),
        Hostile("stored nlen wrong", [
            "AQMA+/9hYmM=",
        ], nil),
        Hostile("stored nlen wrong2", [
            "AQMA/P5hYmM=",
        ], nil),
        Hostile("stored short", [
            "AQMA/P9hYg==",
        ], nil),
        Hostile("stored header cut", [
            "AQMA/A==",
        ], nil),
        Hostile("btype3", [
            "BwA=",
        ], nil),
        Hostile("trailing", [
            "AQMA/P9hYmNqdW5r",
        ], Data(bytes([
            "YWJj",
        ]))),
        Hostile("hlit 286 (29)", [
            "7eDbkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAgAAAAAAAAAAAAAA",
            "AAAA",
        ], Data()),
        Hostile("hdist 30", [
            "Df3bkiRJkizLAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAgAAAAAAAAAAAAAA",
            "AAAAAA==",
        ], Data()),
    ]
}
