/// One field of a VRML node as the parser read it: the numbers (a whole list or a run of them), the first non-numeric word
/// (`TRUE`, `CLOCKWISE`), and the nodes it holds. Which of these a field uses depends on the field; the evaluator asks for the one it knows.
struct VRMLField {
    var name: String
    var numbers: [Float] = []
    var word: String?
    var nodes: [VRMLNode] = []
}

/// A parsed VRML node. `USE` is the same instance as its `DEF`, so instancing costs nothing until the scene is evaluated.
/// `children` are the nodes written directly in the body (VRML 1's way); VRML 2 nodes sit in a field's `nodes`.
final class VRMLNode {
    let type: String
    var fields: [VRMLField] = []
    var children: [VRMLNode] = []

    init(type: String) { self.type = type }

    func field(_ name: String) -> VRMLField? { fields.first { $0.name == name } }

    func numbers(_ name: String) -> [Float]? { field(name)?.numbers }

    func nodes(_ name: String) -> [VRMLNode] { fields.filter { $0.name == name }.flatMap(\.nodes) }
}
