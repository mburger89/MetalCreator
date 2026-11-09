import Foundation
import Testing
@testable import CreatorMCP

struct JSONValueTests {
    @Test func roundTripsEveryCase() throws {
        let value = JSONValue.object([
            "n": .null, "b": .bool(true), "i": .int(-3), "d": .number(1.5), "s": .string("a\"b\n"),
            "a": .array([.int(1), .object(["k": .array([.null, .bool(false)])])]),
        ])
        #expect(try JSONValue.parse(value.encoded()) == value)
    }

    @Test func integersStayIntegers() throws {
        let value = try JSONValue.parse(Data("{\"id\":7}".utf8))
        #expect(value["id"] == .int(7))
        let text = value.text
        #expect(text.contains("7"))
        #expect(!text.contains("7.0"))
        #expect(text == "{\"id\":7}")
    }

    @Test func accessorsConvertWhereTheyShould() {
        #expect(JSONValue.number(3).int == 3)
        #expect(JSONValue.number(3.5).int == nil)
        #expect(JSONValue.int(2).double == 2)
        #expect(JSONValue.string("x").string == "x")
        #expect(JSONValue.bool(true).bool == true)
        #expect(JSONValue.int(1).string == nil)
        #expect(JSONValue.array([.null]).array?.count == 1)
        #expect(JSONValue.object(["a": .null]).object?["a"] == .null)
    }

    @Test func keysAreSorted() {
        let value = JSONValue.object(["b": .int(1), "a": .int(2)])
        #expect(value.text == "{\"a\":2,\"b\":1}")
    }

    static func nested(_ depth: Int) -> String {
        String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    }

    @Test(arguments: [
        (#""\u0041\u00e9""#, JSONValue.string("Aé")),
        (#""\ud83d\ude00""#, JSONValue.string("😀")),
        ("\"😀\"", JSONValue.string("😀")),
        ("99999999999999999999", JSONValue.number(99999999999999999999)),
        ("1.5e3", JSONValue.number(1500)),
        ("-0.5", JSONValue.number(-0.5)),
        (" [ 1 , 2 ] ", JSONValue.array([.int(1), .int(2)])),
    ])
    func parserAccepts(text: String, expected: JSONValue) throws {
        #expect(try JSONValue.parse(Data(text.utf8)) == expected)
    }

    @Test(arguments: [
        #""\ud83d""#, #""\ude00""#, #""\ud83d\u0041""#, "1 2", "{} x", "\"a\nb\"", "\"a\tb\"",
        "01", "1.", "1e", "-", "+1", "[1,]", "{\"a\":1,}", "\"\\x\"", "\"abc", "tru", "",
        nested(300), nested(257),
    ])
    func parserRejects(text: String) {
        #expect(throws: JSONParseError.self) { try JSONValue.parse(Data(text.utf8)) }
    }

    /// Parsed only, never compared: `==` on 256 nested arrays overflows a test thread's small stack in a debug build.
    @Test func acceptsNestingAtTheLimit() throws {
        #expect(try JSONValue.parse(Data(Self.nested(256).utf8)).array != nil)
    }

    @Test func rejectsInvalidUTF8() {
        #expect(throws: JSONParseError.self) { try JSONValue.parse(Data([0x22, 0xFF, 0x22])) }
    }

    @Test(arguments: [
        JSONValue.null, .bool(true), .int(-9), .number(2.5), .string("x\"y"),
        .array([.int(1), .null]), .object(["a": .array([.bool(false)]), "b": .object([:])]),
    ])
    func codableRoundTrips(value: JSONValue) throws {
        let data = try JSONEncoder().encode([value])
        #expect(try JSONDecoder().decode([JSONValue].self, from: data) == [value])
    }
}
