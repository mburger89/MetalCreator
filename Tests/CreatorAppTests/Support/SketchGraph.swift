// Test fixture file: a Sketch node holding a dimensioned rectangle, extruded into an Output.
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import CreatorSketch
import Testing

/// A 60 × 40 rectangle on `plane` (four shared-corner lines, horizontal and vertical, a fixed corner), with
/// dimensions `width` (exposed when `exposed`) and `height`.
func rectangleSketch(on plane: Plane = .xy, exposed: Bool = false) -> Sketch {
    var sketch = Sketch(plane: .fixed(plane))
    let corners = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)].map { sketch.addPoint($0) }
    let lines = (0..<4).map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
    sketch.add(.horizontal(lines[0]))
    sketch.add(.horizontal(lines[2]))
    sketch.add(.vertical(lines[1]))
    sketch.add(.vertical(lines[3]))
    sketch.add(.fix(corners[0], at: .zero))
    let width = sketch.addDimension(.length(lines[0]), value: 60)
    sketch.addDimension(.length(lines[1]), value: 40)
    sketch.renameDimension(width, to: "width")
    sketch.dimensions[width]?.isExposed = exposed
    return sketch
}

extension GraphBuilder {
    /// Sketch (holding `sketch`) → Extrude (10 mm) → Output. Returns the sketch node and the extrude.
    mutating func sketchedBox(_ sketch: Sketch = rectangleSketch(),
                              values: [SocketName: ConstantValue] = [:]) -> (sketch: Node, extrude: Node) {
        var settings = values
        settings[NodeSetting.sketch] = .sketch(sketch)
        let node = add(SketchNode.self, settings)
        let extrude = add(ExtrudeNode.self, ["distance": .number(10)], at: Vector2(240, 0))
        let output = add(OutputNode.self, at: Vector2(480, 0))
        wire(node, "profiles", to: extrude, "profile")
        wire(extrude, "solid", to: output, "solid")
        return (node, extrude)
    }
}
