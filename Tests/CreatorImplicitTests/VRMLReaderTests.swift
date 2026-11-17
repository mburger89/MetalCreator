import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

@Suite struct VRMLReaderTests {
    private static func read(_ text: String, limit: Int = 10_000_000) throws -> ImportedModelMesh {
        try VRMLReader.read(Data(text.utf8), triangleLimit: limit, isCancelled: { false })
    }

    private static let header2 = "#VRML V2.0 utf8\n"
    private static let header1 = "#VRML V1.0 ascii\n"

    private static func shape(_ points: String, _ index: String, extra: String = "") -> String {
        "Shape { geometry IndexedFaceSet { \(extra) coord Coordinate { point [ \(points) ] } coordIndex [ \(index) ] } }"
    }

    private static let triangle = shape("0 0 0, 1 0 0, 0 1 0", "0 1 2 -1")

    private static func corners(_ mesh: TriangleMesh) -> [SIMD3<Float>] { mesh.triangles.map { mesh.positions[Int($0)] } }

    private static func near(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>], tolerance: Float = 1e-5) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < tolerance && abs($0.y - $1.y) < tolerance
            && abs($0.z - $1.z) < tolerance }
    }

    private static func volume(_ mesh: TriangleMesh) -> Float {
        let c = corners(mesh)
        return stride(from: 0, to: c.count, by: 3).reduce(0) { $0 + (c[$1] * 1).dotCross(c[$1 + 1], c[$1 + 2]) } / 6
    }

    private static func problem(_ text: String, limit: Int = 10_000_000) -> String? {
        do { _ = try read(text, limit: limit) } catch let error as MeshImportProblem { return error.message } catch { return "\(error)" }
        return nil
    }

    @Test func version2TriangleAndQuad() throws {
        let triangle = try Self.read(Self.header2 + Self.triangle)
        #expect(triangle.mesh.triangles.count == 3)
        #expect(!triangle.isMillimetres && !triangle.skippedGeometry)
        let quad = try Self.read(Self.header2 + Self.shape("0 0 0 1 0 0 1 1 0 0 1 0", "0 1 2 3 -1"))
        #expect(Self.corners(quad.mesh) == [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 0, 0], [1, 1, 0], [0, 1, 0]])
    }

    @Test func rotationThenTranslation() throws {
        let text = Self.header2 + "Transform { translation 10 0 0 rotation 0 0 1 1.5707963267949 children [ \(Self.triangle) ] }"
        let mesh = try Self.read(text).mesh
        #expect(Self.near(Self.corners(mesh), [[10, 0, 0], [10, 1, 0], [9, 0, 0]]))
    }

    @Test func scaleWithOrientationAndCentre() throws {
        // Scale 2 along the axis the orientation turns to y, about (1, 0, 0), worked by hand: (2,1,0) goes to (2,2,0).
        let transform = "center 1 0 0 scale 2 1 1 scaleOrientation 0 0 1 1.5707963267949"
        let text = Self.header2 + "Transform { \(transform) children [ \(Self.shape("2 1 0 3 1 0 2 2 0", "0 1 2 -1")) ] }"
        #expect(Self.near(Self.corners(try Self.read(text).mesh), [[2, 2, 0], [3, 2, 0], [2, 4, 0]]))
    }

    @Test func nestedTransforms() throws {
        let inner = "Transform { scale 2 2 2 children [ \(Self.triangle) ] }"
        let text = Self.header2 + "Transform { translation 1 0 0 children [ \(inner) ] }"
        #expect(Self.near(Self.corners(try Self.read(text).mesh), [[1, 0, 0], [3, 0, 0], [1, 2, 0]]))
    }

    @Test func fieldsMayComeAfterChildren() throws {
        let text = Self.header2 + "Transform { children [ \(Self.triangle) ] translation 0 0 5 }"
        #expect(Self.near(Self.corners(try Self.read(text).mesh), [[0, 0, 5], [1, 0, 5], [0, 1, 5]]))
    }

    @Test func defUseInstancesAShapeTwice() throws {
        let text = Self.header2 + """
        Transform { translation 0 0 0 children [ DEF S Shape { geometry IndexedFaceSet {
          coord Coordinate { point [0 0 0, 1 0 0, 0 1 0, 1 1 0] }
          coordIndex [0 1 2 -1, 1 3 2 -1] } } ] }
        Transform { translation 5 0 0 children [ USE S ] }
        """
        let mesh = try Self.read(text).mesh
        #expect(mesh.triangles.count / 3 == 4)
        #expect(mesh.positions.contains([5, 0, 0]) && mesh.positions.contains([0, 0, 0]))
    }

    @Test func boxIsTwelveTrianglesAndPointsOutward() throws {
        let mesh = try Self.read(Self.header2 + "Shape { geometry Box { size 2 2 2 } }").mesh
        #expect(mesh.triangles.count / 3 == 12)
        let xs = mesh.positions.map(\.x), zs = mesh.positions.map(\.z)
        #expect(xs.min() == -1 && xs.max() == 1 && zs.min() == -1 && zs.max() == 1)
        #expect(abs(Self.volume(mesh) - 8) < 1e-4)
    }

    @Test func counterClockwiseFalseReverses() throws {
        let mesh = try Self.read(Self.header2 + Self.shape("0 0 0, 1 0 0, 0 1 0", "0 1 2 -1", extra: "ccw FALSE")).mesh
        #expect(Self.corners(mesh) == [[0, 0, 0], [0, 1, 0], [1, 0, 0]])
    }

    @Test func switchTakesOnlyTheChosenChild() throws {
        let other = Self.shape("5 0 0, 6 0 0, 5 1 0", "0 1 2 -1")
        let text = Self.header2 + "Switch { choice [ \(Self.triangle) \(other) ] whichChoice 1 }"
        #expect(Self.corners(try Self.read(text).mesh).first == [5, 0, 0])
        #expect(Self.problem(Self.header2 + "Switch { choice [ \(Self.triangle) ] whichChoice -1 }") == "This file holds no triangles.")
    }

    @Test func aTopLevelScaleMeansMillimetres() throws {
        let text = Self.header2 + "Transform { scale 0.3937 0.3937 0.3937 children [ \(Self.triangle) ] }"
        #expect(try Self.read(text).isMillimetres)
        let unit = Self.header2 + "Transform { scale 1 1 1 children [ \(Self.triangle) ] }"
        #expect(try !Self.read(unit).isMillimetres)
        let nested = Self.header2 + "Group { children [ Transform { scale 2 2 2 children [ \(Self.triangle) ] } ] }"
        #expect(try !Self.read(nested).isMillimetres)
    }

    @Test func unreadShapesAreSkippedAndSaid() throws {
        let read = try Self.read(Self.header2 + "Shape { geometry Sphere { radius 1 } } \(Self.triangle)")
        #expect(read.skippedGeometry && read.mesh.triangles.count == 3)
        let only = try Self.read(Self.header2 + "Shape { geometry Cylinder { } } Inline { url \"a.wrl\" }")
        #expect(only.skippedGeometry && only.mesh.triangles.isEmpty)
    }

    @Test func version1SeparatorScopesState() throws {
        let faces = "IndexedFaceSet { coordIndex [0 1 2 -1] }"
        let text = Self.header1 + """
        Coordinate3 { point [0 0 0, 1 0 0, 0 1 0] }
        Separator { Translation { translation 5 0 0 } \(faces) }
        \(faces)
        """
        let corners = Self.corners(try Self.read(text).mesh)
        #expect(Self.near(corners, [[5, 0, 0], [6, 0, 0], [5, 1, 0], [0, 0, 0], [1, 0, 0], [0, 1, 0]]))
    }

    @Test func version1MatrixTransformCubeAndOrdering() throws {
        let faces = "IndexedFaceSet { coordIndex [0 1 2 -1] }"
        let matrix = "MatrixTransform { matrix 1 0 0 0  0 1 0 0  0 0 1 0  3 4 5 1 }"
        let text = Self.header1 + "Coordinate3 { point [0 0 0, 1 0 0, 0 1 0] } Separator { \(matrix) \(faces) }"
        #expect(Self.corners(try Self.read(text).mesh).first == [3, 4, 5])
        let cube = try Self.read(Self.header1 + "Separator { Cube { width 2 height 4 depth 6 } }").mesh
        #expect(cube.triangles.count / 3 == 12)
        #expect(cube.positions.map(\.y).max() == 2 && cube.positions.map(\.z).min() == -3)
        let clockwise = Self.header1 + "Coordinate3 { point [0 0 0, 1 0 0, 0 1 0] } ShapeHints { vertexOrdering CLOCKWISE } \(faces)"
        #expect(Self.corners(try Self.read(clockwise).mesh) == [[0, 0, 0], [0, 1, 0], [1, 0, 0]])
    }

    @Test func version1TransformSeparatorKeepsOtherState() throws {
        let text = Self.header1 + """
        TransformSeparator { Translation { translation 9 0 0 } Coordinate3 { point [0 0 0, 1 0 0, 0 1 0] } }
        IndexedFaceSet { coordIndex [0 1 2 -1] }
        """
        #expect(Self.corners(try Self.read(text).mesh).first == [0, 0, 0])
    }

    @Test func refusals() {
        #expect(Self.problem(Self.triangle) == "This file isn't a VRML 1 or VRML 2 file.")
        #expect(Self.problem(Self.header2 + "Group { children [ ") == "This VRML file ends early.")
        #expect(Self.problem(Self.header2 + "Group { children [ ] ") == "This VRML file ends early.")
        #expect(Self.problem(Self.header2 + Self.shape("0 0 0 1 0 0 0 1 0", "0 1 7 -1"))
            == "This VRML file has a face that names a point it doesn't have.")
        #expect(Self.problem(Self.header2 + Self.shape("0 0 0 1 0 0 0 1 0", "0 1 2147483648 -1"))
            == "This VRML file has a face that names a point it doesn't have.")
        #expect(Self.problem(Self.header2 + "Group { children [ USE Missing ] }") == "This VRML file uses a shape before it is defined.")
        #expect(Self.problem(Self.header2 + "DEF A Group { children [ USE A ] }") == "This VRML file uses a shape before it is defined.")
        #expect(Self.problem(Self.header2 + "Group { children [ 1 x ] ") != nil)
        #expect(Self.problem(Self.header2 + "Group { scale 1.2.3 }") == "This VRML file has a bad number.")
        #expect(Self.problem(Self.header2 + "}") == "This VRML file is damaged.")
    }

    @Test func nestingTooDeep() {
        let open = String(repeating: "Group { children [ ", count: 300)
        let close = String(repeating: "] } ", count: 300)
        #expect(Self.problem(Self.header2 + open + Self.triangle + close) == "This VRML file nests too deeply.")
        let ok = String(repeating: "Group { children [ ", count: 250) + Self.triangle + String(repeating: "] } ", count: 250)
        #expect(Self.problem(Self.header2 + ok) == nil)
    }

    @Test func aFileThatDoublesItselfIsStopped() {
        var text = Self.header2 + "DEF A0 Group { children [ \(Self.triangle) ] }\n"
        for level in 1...40 { text += "DEF A\(level) Group { children [ USE A\(level - 1) USE A\(level - 1) ] }\n" }
        let message = Self.problem(text)
        #expect(message == "This VRML file is too complex." || message == MeshImportProblem.overTriangleLimit.message)
    }

    @Test func triangleLimit() throws {
        let two = Self.header2 + Self.shape("0 0 0 1 0 0 0 1 0 1 1 0", "0 1 2 -1 1 3 2 -1")
        #expect(Self.problem(two, limit: 1) == MeshImportProblem.overTriangleLimit.message)
        #expect(try Self.read(two, limit: 2).mesh.triangles.count == 6)
    }

    @Test func cancellationIsHonoured() {
        let points = (0..<70_000).map { "\($0) 0 0" }.joined(separator: " ")
        let text = Self.header2 + Self.shape(points, "0 1 2 -1")
        #expect(throws: CancellationError.self) { try VRMLReader.read(Data(text.utf8), isCancelled: { true }) }
    }

    @Test func randomMutationsNeverTrap() {
        let seed = Self.header2 + """
        Transform { translation 1 2 3 rotation 0 0 1 1.5 scale 1 1 1 children [
          DEF S Shape { appearance Appearance { material Material { diffuseColor 1 0 0 } }
            geometry IndexedFaceSet { ccw TRUE coord Coordinate { point [0 0 0, 1 0 0, 1 1 0, 0 1 0] } coordIndex [0 1 2 3 -1] } }
          Switch { whichChoice 0 choice [ USE S ] } Shape { geometry Box { size 1 2 3 } } ] }
        """
        let original = Array(seed.utf8)
        let specials = Array("{}[]#\",-.eE0123456789 \n\\DEFUS".utf8)
        var random = SeededRandom(seed: 7)
        for _ in 0..<2_000 {
            var bytes = original
            for _ in 0..<(1 + Int(random.next() % 4)) where !bytes.isEmpty {
                let at = Int(random.next() % UInt64(bytes.count))
                switch random.next() % 3 {
                case 0: bytes[at] = specials[Int(random.next() % UInt64(specials.count))]
                case 1: bytes.remove(at: at)
                default: bytes.insert(specials[Int(random.next() % UInt64(specials.count))], at: at)
                }
            }
            _ = try? VRMLReader.read(Data(bytes), triangleLimit: 1_000, isCancelled: { false })
        }
    }
}

private extension SIMD3<Float> {
    func dotCross(_ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float {
        let cross = SIMD3(b.y * c.z - b.z * c.y, b.z * c.x - b.x * c.z, b.x * c.y - b.y * c.x)
        return (self * cross).sum()
    }
}
