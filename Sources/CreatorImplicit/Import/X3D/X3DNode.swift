/// A parsed X3D element that matters to the reader. `USE` is the same instance as its `DEF`, so instancing costs nothing until the
/// scene is evaluated. Only the attributes the reader uses are kept.
final class X3DNode {
    let type: String
    var children: [X3DNode] = []
    var translation: [Float]?
    var rotation: [Float]?
    var scale: [Float]?
    var scaleOrientation: [Float]?
    var center: [Float]?
    var size: [Float]?
    var point: [Float] = []
    var index: [Float] = []
    var whichChoice: Float = -1
    var counterClockwise = true

    init(type: String) { self.type = type }
}
