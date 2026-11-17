import CreatorGraph
import Foundation

/// Reads X3D (XML encoding) into one triangle mesh, the way `VRMLReader` reads VRML 2: faces of `IndexedFaceSet` and
/// `IndexedTriangleSet`, and `Box`, under the `Transform`s that reach them. Element names are compared after any `prefix:`. Colours,
/// normals, appearances and every other node are ignored. A model file is untrusted input: at most 64 MB, nesting 256 deep, the
/// triangles of Import Mesh, and cancellation asked at least every 65,536 events; every way to be wrong is a
/// `MeshImportProblem.x3d` with a sentence (or the scanner's `malformedModel` for broken XML), and nothing traps. X3D's unit is the
/// metre, but KiCad's models are written in whatever its exporter chose, so `isMillimetres` is always false and the caller scales.
public enum X3DReader {
    static var notX3D: MeshImportProblem { .x3d("This file isn't an X3D file.") }
    static var badNumber: MeshImportProblem { .x3d("This X3D file has a bad number.") }
    static var tooComplex: MeshImportProblem { .x3d("This X3D file is too complex.") }
    static var undefinedShape: MeshImportProblem { .x3d("This X3D file uses a shape before it is defined.") }

    /// `isCancelled` is asked as the file is read; a cancelled read throws `CancellationError`.
    public static func read(_ data: Data, isCancelled: () -> Bool) throws -> ImportedModelMesh {
        try read(data, triangleLimit: MeshImportLimits.maxTriangles, isCancelled: isCancelled)
    }

    /// `read` with the triangle limit as a parameter, so a test can reach it without a file of millions of triangles.
    static func read(_ data: Data, triangleLimit: Int, elementLimit: Int = X3DBuilder.maximumElements,
                     isCancelled: () -> Bool) throws -> ImportedModelMesh {
        guard data.count <= VRMLReader.maximumBytes else {
            throw MeshImportProblem.x3d("This X3D file is larger than the 64 MB limit.")
        }
        return try withoutActuallyEscaping(isCancelled) { escaping in
            try data.withUnsafeBytes { raw in
                var builder = X3DBuilder(scanner: XMLScanner(bytes: raw), isCancelled: escaping)
                let root = try builder.build(maximumElements: elementLimit)
                let scene = VRMLScene(triangleLimit: triangleLimit, format: "X3D", isCancelled: escaping)
                try scene.evaluateX3D(root)
                return try VRMLReader.finish(scene, millimetres: false)
            }
        }
    }
}
