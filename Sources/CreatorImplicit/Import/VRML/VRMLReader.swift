import CreatorGraph
import Foundation

/// A model read from a VRML file: the mesh in the file's own units.
public struct ImportedModelMesh: Sendable {
    public var mesh: TriangleMesh
    /// Whether the file held shapes that are not read (spheres, cylinders and the like).
    public var skippedGeometry: Bool
    /// Whether the file's units are millimetres: a VRML 2 file whose top-level `Transform` has a `scale` other than 1 (KiCad's way
    /// of writing millimetres). Every other VRML file is in 0.1 inch, and the caller applies that factor.
    public var isMillimetres: Bool

    public init(mesh: TriangleMesh, skippedGeometry: Bool, isMillimetres: Bool) {
        self.mesh = mesh
        self.skippedGeometry = skippedGeometry
        self.isMillimetres = isMillimetres
    }
}

/// Reads VRML 1 (`#VRML V1.0 ascii`) and VRML 2 (`#VRML V2.0 utf8`) into one triangle mesh: faces of `IndexedFaceSet`, `Box` and `Cube`
/// under the transforms that reach them. Colours, normals, materials and every other node are ignored. A model file is untrusted
/// input: at most 64 MB, nesting 256 deep, the triangles of Import Mesh, and cancellation asked at least every 65,536 tokens; every way
/// to be wrong is a `MeshImportProblem.vrml` with a sentence, and nothing traps.
public enum VRMLReader {
    public static let maximumBytes = 64 << 20

    static var damaged: MeshImportProblem { .vrml("This VRML file is damaged.") }
    static var endsEarly: MeshImportProblem { .vrml("This VRML file ends early.") }
    static var badNumber: MeshImportProblem { .vrml("This VRML file has a bad number.") }
    static var tooDeep: MeshImportProblem { .vrml("This VRML file nests too deeply.") }
    static var tooComplex: MeshImportProblem { .vrml("This VRML file is too complex.") }

    /// The refusals the shared scene makes, worded for `format` ("VRML" or "X3D").
    static func sceneProblem(_ format: String, _ rest: String) -> MeshImportProblem {
        let sentence = "This \(format) file \(rest)"
        return format == "VRML" ? .vrml(sentence) : .x3d(sentence)
    }
    static var undefinedShape: MeshImportProblem { .vrml("This VRML file uses a shape before it is defined.") }
    static var badIndex: MeshImportProblem { .vrml("This VRML file has a face that names a point it doesn't have.") }

    /// `isCancelled` is asked as the file is read; a cancelled read throws `CancellationError`.
    public static func read(_ data: Data, isCancelled: () -> Bool) throws -> ImportedModelMesh {
        try read(data, triangleLimit: MeshImportLimits.maxTriangles, isCancelled: isCancelled)
    }

    /// `read` with the triangle limit as a parameter, so a test can reach it without a file of millions of triangles.
    static func read(_ data: Data, triangleLimit: Int, isCancelled: () -> Bool) throws -> ImportedModelMesh {
        guard data.count <= maximumBytes else { throw MeshImportProblem.vrml("This VRML file is larger than the 64 MB limit.") }
        return try withoutActuallyEscaping(isCancelled) { escaping in
            try data.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                guard let version = version(of: bytes) else {
                    throw MeshImportProblem.vrml("This file isn't a VRML 1 or VRML 2 file.")
                }
                let root = try VRMLParser(bytes, isCancelled: escaping).parseFile()
                let scene = VRMLScene(triangleLimit: triangleLimit, isCancelled: escaping)
                if version == 1 {
                    try scene.evaluate1(root.children)
                } else {
                    try scene.evaluate2(root.children)
                }
                return try finish(scene, millimetres: version == 2 && scalesTopLevel(root))
            }
        }
    }

    /// 1 or 2 from the first line's `#VRML V1` or `#VRML V2`, past a byte order mark.
    private static func version(of bytes: UnsafeBufferPointer<UInt8>) -> Int? {
        var start = 0
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { start = 3 }
        let marker = Array("#VRML V".utf8)
        guard bytes.count >= start + marker.count + 1, Array(bytes[start..<(start + marker.count)]) == marker else { return nil }
        switch bytes[start + marker.count] {
        case 0x31: return 1
        case 0x32: return 2
        default: return nil
        }
    }

    /// A top-level `Transform` whose `scale` is not (1, 1, 1).
    private static func scalesTopLevel(_ root: VRMLNode) -> Bool {
        root.children.contains { node in
            guard node.type == "Transform", let scale = node.numbers("scale"), scale.count >= 3 else { return false }
            return scale[0] != 1 || scale[1] != 1 || scale[2] != 1
        }
    }

    static func finish(_ scene: VRMLScene, millimetres: Bool) throws -> ImportedModelMesh {
        let welded = ExactWeld.weld(corners: scene.corners)
        guard !welded.triangles.isEmpty else {
            guard scene.skippedGeometry else { throw MeshImportProblem.noTriangles }
            return ImportedModelMesh(mesh: TriangleMesh(positions: [], triangles: [], creaseAngle: 30), skippedGeometry: true,
                                     isMillimetres: millimetres)
        }
        let mesh = TriangleMesh(positions: welded.positions, triangles: welded.triangles, creaseAngle: 30)
        return ImportedModelMesh(mesh: mesh, skippedGeometry: scene.skippedGeometry, isMillimetres: millimetres)
    }
}
