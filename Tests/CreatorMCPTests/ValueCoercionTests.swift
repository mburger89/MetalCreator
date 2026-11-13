import CreatorGeometry
import CreatorGraph
import CreatorMCP
import Testing

struct ValueCoercionTests {
    private let width = SocketSpec("width", .number, unit: .millimetres, range: 0...1000)

    private func value(_ json: JSONValue, _ spec: SocketSpec, options: [String]? = nil) -> Result<ConstantValue?, Refusal> {
        ValueCoercion.value(json, for: spec, options: options)
    }

    @Test func numbersTakeIntsAndDoublesWithinRange() {
        #expect(value(.int(3), width) == .success(.number(3)))
        #expect(value(.number(2.5), width) == .success(.number(2.5)))
        #expect(value(.int(2000), width) == .failure(Refusal("Width must be between 0 and 1000.")))
        #expect(value(.string("x"), width) == .failure(Refusal("Width needs a number.")))
    }

    @Test func nullClears() {
        #expect(value(.null, width) == .success(nil))
    }

    @Test func integersBoolsAndVectors() {
        #expect(value(.int(4), SocketSpec("count", .integer)) == .success(.integer(4)))
        #expect(value(.number(4.5), SocketSpec("count", .integer)) == .failure(Refusal("Count needs a whole number.")))
        #expect(value(.bool(true), SocketSpec("reversed", .bool)) == .success(.bool(true)))
        #expect(value(.int(1), SocketSpec("reversed", .bool)) == .failure(Refusal("Reversed needs true or false.")))
        #expect(value(.array([.int(1), .int(2), .number(3.5)]), SocketSpec("size", .vector)) == .success(.vector(Vector3(1, 2, 3.5))))
        #expect(value(.array([.int(1)]), SocketSpec("size", .vector)) != .success(nil))
    }

    @Test func segmentedTakesNameAnyCaseOrIndex() {
        let spec = SocketSpec("mode", .integer)
        let options = ["One side", "Symmetric"]
        #expect(value(.string("symmetric"), spec, options: options) == .success(.integer(1)))
        #expect(value(.int(1), spec, options: options) == .success(.integer(1)))
        #expect(value(.int(2), spec, options: options) != .success(.integer(2)))
        #expect(value(.string("Both"), spec, options: options) == .failure(Refusal("Mode must be one of One side, Symmetric.")))
    }

    @Test func labelsReadAsTheInspectorDoes() {
        #expect(SocketLabel.text(for: "startAngle") == "Start angle")
    }

    @Test func refusalsUseTheInspectorLabels() {
        let spec = SocketSpec("startAngle", .number, range: 0...90)
        #expect(value(.int(200), spec) == .failure(Refusal("\(SocketLabel.text(for: "startAngle")) must be between 0 and 90.")))
    }
}
