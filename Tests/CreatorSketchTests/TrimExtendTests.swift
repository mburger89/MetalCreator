import CreatorGeometry
import Testing
@testable import CreatorSketch

struct TrimExtendTests {
    @Test func trimmingAnOverhangEndsTheLineAtTheCutter() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (start, oldEnd) = sketch.ends(line)
        let cutter = sketch.addLine(Vector2(6, -5), Vector2(6, 5))
        sketch.add(.horizontal(line))
        sketch.addDimension(.length(line), value: 10)
        let edit = try SketchCommands.trim(sketch, curve: line, near: Vector2(8, 0.1))
        let trimmed = edit.sketch
        #expect(edit.description == "Trim Line 1")
        let (newStart, newEnd) = trimmed.ends(line)
        #expect(newStart == start)
        #expect(isClose(try #require(trimmed.position(of: newEnd)), Vector2(6, 0)))
        #expect(trimmed.entities[oldEnd] == nil)
        #expect(trimmed.constraintList.contains(.pointOn(point: newEnd, curve: cutter)))
        #expect(trimmed.constraintList.contains(.horizontal(line)))
        #expect(trimmed.dimensions.isEmpty)
        try requireSolvesInPlace(trimmed)
    }

    @Test func trimmingTheMiddleSplitsTheLineAndKeepsItStraight() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        let left = sketch.addLine(Vector2(3, -5), Vector2(3, 5))
        let right = sketch.addLine(Vector2(7, -5), Vector2(7, 5))
        let trimmed = try SketchCommands.trim(sketch, curve: line, near: Vector2(5, 0)).sketch
        let lines = trimmed.ids(ofKind: "Line")
        try #require(lines.count == 4)
        let piece = try #require(lines.last)
        #expect(trimmed.ends(line).0 == start)
        #expect(trimmed.ends(piece).1 == end)
        let (pieceStart, lineEnd) = (trimmed.ends(piece).0, trimmed.ends(line).1)
        #expect(isClose(try #require(trimmed.position(of: lineEnd)), Vector2(3, 0)))
        #expect(isClose(try #require(trimmed.position(of: pieceStart)), Vector2(7, 0)))
        let constraints = trimmed.constraintList
        #expect(constraints.contains(.pointOn(point: lineEnd, curve: left)))
        #expect(constraints.contains(.pointOn(point: pieceStart, curve: right)))
        #expect(constraints.contains(.pointOn(point: pieceStart, curve: line)))
        #expect(constraints.contains(.pointOn(point: end, curve: line)))
        try requireSolvesInPlace(trimmed)
    }

    @Test func trimmingACurveWithNoCrossingsDeletesIt() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        sketch.addCircle(center: Vector2(50, 50), radius: 2)
        let trimmed = try SketchCommands.trim(sketch, curve: line, near: Vector2(5, 0)).sketch
        #expect(trimmed.entities[line] == nil)
        #expect(trimmed.ids(ofKind: "Point").count == 1)
    }

    @Test func trimmingACircleLeavesTheArcAwayFromThePick() throws {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 5)
        let center = sketch.centerOf(circle)
        let radius = sketch.addDimension(.radius(circle), value: 5)
        sketch.addLine(Vector2(-10, 0), Vector2(10, 0))
        let trimmed = try SketchCommands.trim(sketch, curve: circle, near: Vector2(0.5, 6)).sketch
        let (arcCenter, start, end) = trimmed.arcPoints(circle)
        #expect(arcCenter == center)
        // The bottom half remains: counter-clockwise from (−5, 0) to (5, 0).
        #expect(isClose(try #require(trimmed.position(of: start)), Vector2(-5, 0)))
        #expect(isClose(try #require(trimmed.position(of: end)), Vector2(5, 0)))
        #expect(trimmed.dimensions[radius] != nil)
        try requireSolvesInPlace(trimmed)
    }

    @Test func trimmingAtATJunctionSharesTheStemsEndpoint() throws {
        var sketch = Sketch()
        let bar = sketch.addLine(.zero, Vector2(10, 0))
        let stem = sketch.addLine(Vector2(5, 0), Vector2(5, 5))
        let trimmed = try SketchCommands.trim(sketch, curve: bar, near: Vector2(9, 0)).sketch
        #expect(trimmed.ends(bar).1 == trimmed.ends(stem).0)
        #expect(trimmed.constraints.isEmpty)
    }

    @Test func projectedEdgesCantBeTrimmed() {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(1, 0))))))
        #expect(throws: SketchCommandError("Projected edges can't be trimmed.")) {
            try SketchCommands.trim(sketch, curve: edge, near: .zero)
        }
    }

    @Test func extendingALineStopsAtTheFirstCurveItMeets() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(4, 0))
        let (_, end) = sketch.ends(line)
        let near = sketch.addLine(Vector2(10, -5), Vector2(10, 5))
        sketch.addLine(Vector2(20, -5), Vector2(20, 5))
        sketch.addDimension(.length(line), value: 4)
        let edit = try SketchCommands.extend(sketch, curve: line, near: Vector2(3.5, 0))
        #expect(edit.description == "Extend Line 1")
        #expect(isClose(try #require(edit.sketch.position(of: end)), Vector2(10, 0)))
        #expect(edit.sketch.constraintList.contains(.pointOn(point: end, curve: near)))
        #expect(edit.sketch.dimensions.isEmpty)
        try requireSolvesInPlace(edit.sketch)
    }

    @Test func extendingOntoAnEndpointSharesIt() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(4, 0))
        let wall = sketch.addLine(Vector2(10, 0), Vector2(10, 10))
        let extended = try SketchCommands.extend(sketch, curve: line, near: Vector2(4, 0)).sketch
        #expect(extended.ends(line).1 == extended.ends(wall).0)
        #expect(extended.ids(ofKind: "Point").count == 3)
    }

    @Test func extendingAnArcStartRunsClockwiseToTheLine() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let arc = sketch.addArc(center: center, start: sketch.addPoint(Vector2(5, 0)), end: sketch.addPoint(Vector2(0, 5)))
        sketch.addLine(Vector2(-10, -3), Vector2(10, -3))
        let extended = try SketchCommands.extend(sketch, curve: arc, near: Vector2(5, 0.5)).sketch
        let (_, start, _) = extended.arcPoints(arc)
        #expect(isClose(try #require(extended.position(of: start)), Vector2(4, -3)))
        try requireSolvesInPlace(extended)
    }

    @Test func aConnectedEndCantBeExtended() {
        var sketch = Sketch()
        let lines = addPolygon(&sketch, [.zero, Vector2(10, 0), Vector2(10, 10)])
        #expect(throws: SketchCommandError("That end of Line 1 is connected to other geometry.")) {
            try SketchCommands.extend(sketch, curve: lines[0], near: Vector2(9, 0))
        }
    }

    @Test func extendingTowardsNothingIsAPlainError() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(4, 0))
        sketch.addLine(Vector2(0, 5), Vector2(4, 5))
        #expect(throws: SketchCommandError("There is nothing to extend Line 1 to.")) {
            try SketchCommands.extend(sketch, curve: line, near: Vector2(4, 0))
        }
    }
}
