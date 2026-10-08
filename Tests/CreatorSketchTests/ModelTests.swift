import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

struct ModelTests {
    @Test func idsAreHandedOutInOrderAndNeverReused() {
        var sketch = Sketch()
        let a = sketch.addPoint(.zero)
        let b = sketch.addPoint(Vector2(1, 0))
        let line = sketch.addLine(from: a, to: b)
        let constraint = sketch.add(.horizontal(line))
        #expect([a.rawValue, b.rawValue, line.rawValue, constraint.rawValue] == [1, 2, 3, 4] as [Int])
        sketch.removeEntity(line)
        #expect(sketch.addPoint(.zero).rawValue == 5)
    }

    @Test func sketchRoundTripsThroughJSON() throws {
        var sketch = Sketch(plane: .fixed(.xz))
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let center = sketch.addPoint(Vector2(5, 5))
        let (start, end) = sketch.ends(line)
        let arc = sketch.addArc(center: center, start: end, end: start, isConstruction: true)
        sketch.addCircle(center: Vector2(20, 20), radius: 3)
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge-1", curve: .line(.zero, Vector2(0, 9))))))
        sketch.add(.tangent(line, arc))
        sketch.add(.fix(start, at: .zero))
        let angle = sketch.addDimension(.angle(line, line), value: 30, isDriving: false)
        sketch.dimensions[angle]?.isExposed = true
        sketch.solved[start] = .point(Vector2(0.5, 0))
        let decoded = try JSONDecoder().decode(Sketch.self, from: try JSONEncoder().encode(sketch))
        #expect(decoded == sketch)
    }

    @Test func idsEncodeAsBareIntegers() throws {
        let data = try JSONEncoder().encode(SketchEntityID(7))
        #expect(String(decoding: data, as: UTF8.self) == "7")
    }

    @Test func sketchesEncodeDeterministicallyAsKeyedObjects() throws {
        func build() -> Sketch {
            var sketch = Sketch()
            let lines = addPolygon(&sketch, [.zero, Vector2(10, 0), Vector2(10, 5), Vector2(0, 5)])
            for line in lines { sketch.add(.horizontal(line)) }
            for line in lines { sketch.addDimension(.length(line), value: 10) }
            for id in sketch.ids(ofKind: "Point") { sketch.solved[id] = .point(Vector2(1, 2)) }
            return sketch
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Two separately built (separately hashed) sketches give the same bytes.
        let first = try encoder.encode(build())
        let second = try encoder.encode(build())
        #expect(first == second)
        let object = try #require(try JSONSerialization.jsonObject(with: first) as? [String: Any])
        for key in ["entities", "constraints", "dimensions", "solved"] {
            #expect(object[key] is [String: Any], "\(key) encodes as a JSON object")
        }
        let entities = try #require(object["entities"] as? [String: Any])
        #expect(entities.keys.sorted() == (1...8).map(String.init).sorted())
        #expect(try JSONDecoder().decode(Sketch.self, from: first) == build())
    }

    @Test func dimensionsAreNamedD1D2AndRenamesStayUnique() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let first = sketch.addDimension(.length(line), value: 10)
        let second = sketch.addDimension(.length(line), value: 10)
        #expect(sketch.dimensions[first]?.name == "d1")
        #expect(sketch.dimensions[second]?.name == "d2")
        let taken = sketch.renameDimension(second, to: "d1")
        let blank = sketch.renameDimension(second, to: "  ")
        let renamed = sketch.renameDimension(second, to: " width ")
        #expect(taken == false)
        #expect(blank == false)
        #expect(renamed)
        #expect(sketch.dimensions[second]?.name == "width")
        // Auto names are never reused, even once their dimension is renamed or removed: an exposed
        // "d2" socket can't silently start driving something else.
        sketch.addDimension(.length(line), value: 1)
        #expect(sketch.dimensions.values.map(\.name).sorted() == ["d1", "d3", "width"])
        sketch.dimensions[first] = nil
        let fourth = sketch.addDimension(.length(line), value: 2)
        #expect(sketch.dimensions[fourth]?.name == "d4")
    }

    /// Hand-named "d5" is skipped by auto naming, which carries on after it.
    @Test func autoNamesSkipNamesInUse() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let first = sketch.addDimension(.length(line), value: 10)
        sketch.renameDimension(first, to: "d2")
        #expect(sketch.dimensions[sketch.addDimension(.length(line), value: 10)]?.name == "d3")
    }

    /// Renaming to an auto-style name "d7" claims it like an auto name: once renamed away it is
    /// never handed out, and the counter already matches what decoding would clamp it to.
    @Test func renamingToAnAutoNameAdvancesTheCounter() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let first = sketch.addDimension(.length(line), value: 10)
        let claimed = sketch.renameDimension(first, to: "d7")
        #expect(claimed)
        #expect(sketch.nextDimensionNumber == 8)
        let decoded = try JSONDecoder().decode(Sketch.self, from: try JSONEncoder().encode(sketch))
        #expect(decoded == sketch)
        sketch.renameDimension(first, to: "width")
        let names = (0..<7).compactMap { _ in sketch.dimensions[sketch.addDimension(.length(line), value: 1)]?.name }
        #expect(!names.contains("d7"))
        #expect(names.first == "d8")
    }

    /// Files from before the name counter, or edited by hand, decode with counters past every ID
    /// and auto name already used.
    @Test func decodingClampsTheCountersPastWhatIsInUse() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        sketch.addDimension(.length(line), value: 10)
        let second = sketch.addDimension(.length(line), value: 10)
        sketch.renameDimension(second, to: "d7")
        var object = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(sketch)) as? [String: Any])
        object["nextID"] = 2
        object["nextDimensionNumber"] = nil
        let decoded = try JSONDecoder().decode(Sketch.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(decoded.nextID == 6)
        #expect(decoded.nextDimensionNumber == 8)
        var edited = decoded
        #expect(edited.addPoint(.zero).rawValue == 6)
        #expect(edited.dimensions[edited.addDimension(.length(line), value: 1)]?.name == "d8")
    }

    @Test func removingAPointRemovesItsCurvesAndTheirConstraints() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        let other = sketch.addLine(from: end, to: sketch.addPoint(Vector2(10, 10)))
        sketch.add(.horizontal(line))
        let kept = sketch.add(.vertical(other))
        sketch.addDimension(.length(line), value: 10)
        sketch.solved[start] = .point(.zero)
        sketch.removeEntity(start)
        #expect(sketch.entities[line] == nil)
        #expect(sketch.entities[other] != nil)
        #expect(Array(sketch.constraints.keys) == [kept])
        #expect(sketch.dimensions.isEmpty)
        #expect(sketch.solved.isEmpty)
    }

    @Test func positionsPreferTheLastSolve() {
        var sketch = Sketch()
        let p = sketch.addPoint(Vector2(1, 2))
        let circle = sketch.addCircle(center: p, radius: 4)
        #expect(sketch.position(of: p) == Vector2(1, 2))
        #expect(sketch.radius(of: circle) == 4)
        sketch.solved[p] = .point(Vector2(3, 3))
        sketch.solved[circle] = .radius(5)
        #expect(sketch.position(of: p) == Vector2(3, 3))
        #expect(sketch.radius(of: circle) == 5)
    }

    @Test func labelsCountEachKindInIDOrder() {
        var sketch = Sketch()
        let first = sketch.addLine(.zero, Vector2(1, 0))
        let second = sketch.addLine(Vector2(0, 1), Vector2(1, 1))
        let horizontal = sketch.add(.horizontal(second))
        let angle = sketch.addDimension(.angle(first, second), value: 30)
        #expect(sketch.label(of: second) == "Line 2")
        #expect(sketch.label(of: sketch.ends(second).0) == "Point 3")
        #expect(sketch.label(of: .constraint(horizontal)) == "Horizontal on Line 2")
        #expect(sketch.label(of: .dimension(angle)) == "Angle d1 (30°)")
        #expect(sketch.conflictMessage([.constraint(horizontal), .dimension(angle)])
            == "Horizontal on Line 2 conflicts with Angle d1 (30°).")
    }
}
