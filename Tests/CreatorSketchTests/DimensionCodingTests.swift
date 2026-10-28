import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// DIM-2: the new dimension kinds and the optional saved label point encode compatibly.
struct DimensionCodingTests {
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func json(_ value: some Encodable) throws -> String {
        try #require(String(bytes: encoder().encode(value), encoding: .utf8))
    }

    @Test func aDimensionWithoutALabelPointWritesNoKey() throws {
        let dimension = SketchDimension(kind: .length(SketchEntityID(1)), name: "d1", value: 10)
        #expect(!(try json(dimension)).contains("labelPoint"))
    }

    @Test func labelPointsRoundTrip() throws {
        let dimension = SketchDimension(kind: .length(SketchEntityID(1)), name: "d1", value: 10,
                                        labelPoint: Vector2(12.5, -3))
        let text = try json(dimension)
        #expect(text.contains("labelPoint"))
        let decoded = try JSONDecoder().decode(SketchDimension.self, from: Data(text.utf8))
        #expect(decoded == dimension)
        #expect(decoded.labelPoint == Vector2(12.5, -3))
    }

    @Test func theNewKindsEncodeByName() throws {
        let a = SketchEntityID(3), b = SketchEntityID(5)
        let kinds: [(DimensionKind, String)] = [
            (.horizontalDistance(a, b), "horizontalDistance"), (.centreDistance(a, b), "centreDistance"),
            (.lineDistance(a, b), "lineDistance"), (.verticalDistance(a, b), "verticalDistance"),
        ]
        for (kind, name) in kinds {
            let text = try json(kind)
            #expect(text == "{\"\(name)\":{\"_0\":3,\"_1\":5}}")
            #expect(try JSONDecoder().decode(DimensionKind.self, from: Data(text.utf8)) == kind)
        }
    }

    @Test func aSketchFromBeforeDecodesUnchanged() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        sketch.addDimension(.length(line), value: 10)
        sketch.addDimension(.length(line), value: 10, isDriving: false)
        let before = try json(sketch)
        #expect(!before.contains("labelPoint"))
        let decoded = try JSONDecoder().decode(Sketch.self, from: Data(before.utf8))
        #expect(decoded == sketch)
        #expect(try json(decoded) == before)
    }

    @Test func aNonFiniteLabelPointIsNotFinite() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let id = sketch.addDimension(.length(line), value: 10)
        #expect(sketch.isFinite)
        sketch.dimensions[id]?.labelPoint = Vector2(.nan, 0)
        #expect(!sketch.isFinite)
    }
}
