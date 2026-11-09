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
}
