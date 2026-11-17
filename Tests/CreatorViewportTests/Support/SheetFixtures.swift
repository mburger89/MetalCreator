// Test fixture file: a one-quad sheet and a straight curve in the front view of `RenderFixtures`.
import CreatorGeometry
import CreatorKernel
@testable import CreatorViewport

enum SheetFixtures {
    /// A single face in the plane y = 0 over x −5…5, z 0…30, numbered 0. Seen from the front view (the eye on −Y) a sheet made
    /// with `facingEye` true is a front face; with it false its triangles are wound the other way, so the eye sees its back.
    static func sheet(facingEye: Bool) -> DisplayMesh {
        let (x0, x1, z0, z1) = (-5.0, 5.0, 0.0, 30.0)
        let corners = [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
        let order = facingEye ? [0, 1, 2, 0, 2, 3] : [0, 2, 1, 0, 3, 2]
        let normal = Vector3(0, facingEye ? -1 : 1, 0)
        return DisplayMesh(positions: corners, normals: Array(repeating: normal, count: 4), indices: order.map { UInt32($0) },
                           triangleFaces: [FaceID(0), FaceID(0)], edgePolylines: [:])
    }

    static func sheetFrame(facingEye: Bool, openShell: Bool, ghost: Bool = false) -> ViewportFrame {
        var frame = TestFrames.frame(mesh: sheet(facingEye: facingEye), pose: RenderFixtures.front, size: RenderFixtures.size,
                                     bounds: RenderFixtures.bounds)
        frame.items[0].openShellFaces = openShell ? [FaceID(0)] : []
        frame.items[0].isGhost = ghost
        // The GPU keeps a mesh by serial, and a serial is one mesh with one set of open faces: each variant has its own.
        frame.items[0].meshSerial = (facingEye ? 10 : 20) + (openShell ? 1 : 0) + (ghost ? 100 : 0)
        return frame
    }

    /// A curve item: no triangles, one polyline up the middle of the view (x = 0, y = 0, z 0…30).
    static func curveFrame(shading: ShadingMode = .shaded, ghost: Bool = false) -> ViewportFrame {
        let mesh = DisplayMesh(positions: [], normals: [], indices: [], triangleFaces: [],
                               edgePolylines: [EdgeID(0): [Vector3(0, 0, 0), Vector3(0, 0, 30)]])
        var frame = TestFrames.frame(mesh: mesh, pose: RenderFixtures.front, size: RenderFixtures.size, bounds: RenderFixtures.bounds)
        frame.items[0].isCurve = true
        frame.items[0].isGhost = ghost
        frame.shading = shading
        return frame
    }

    /// The front shade of the sheet's lit-from-the-key colour, for any theme, at the sheet's centre: the ramp's `t` for a normal
    /// facing the eye (the shader's own formula).
    static func backExpected(_ palette: ViewportPalette, seenNormalZ: Float) -> [Int] {
        let key = SIMD3<Float>(-0.4, 0.7, 0.6)
        let length = (key * key).sum().squareRoot()
        let diffuse = max(0, min(1, seenNormalZ * key.z / length))
        let scale = 0.7 + 0.3 * diffuse
        return [palette.sheetBack.x, palette.sheetBack.y, palette.sheetBack.z].map { Int(($0 * scale * 255).rounded()) }
    }
}
