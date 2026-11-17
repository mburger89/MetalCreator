import CreatorGeometry
import Testing
@testable import CreatorPCB

struct ModelPlacementTests {
    // Every case: footprint at file (12, 8), board origin (2, 3), so p = (10, 5); thickness 1.6.
    private static func frame(back: Bool = false, angle: Double = 0, offset: Vector3 = .zero,
                              rotation: Vector3 = .zero) -> ModelFrame {
        let footprint = Footprint(reference: "U1", libraryID: "L:F", uuid: nil, isBack: back,
                                  place: Placement2D(origin: Vector2(12, 8), angle: angle), holes: [], models: [])
        let model = ModelReference(path: "m.step", offset: offset, scale: Vector3(1, 1, 1), rotation: rotation,
                                   isHidden: false)
        return ModelPlacement.frame(of: model, on: footprint, boardOrigin: Vector2(2, 3), thickness: 1.6)
    }

    private static let corners: [Vector3] = [0.0, 3.0].flatMap { x in
        [0.0, 2.0].flatMap { y in [0.0, 1.0].map { z in Vector3(x, y, z) } }
    }

    private func expect(_ frame: ModelFrame, _ expected: [Vector3], _ note: String) {
        for (corner, want) in zip(Self.corners, expected) {
            let got = frame.apply(corner)
            #expect(abs(got.x - want.x) < 1e-9 && abs(got.y - want.y) < 1e-9 && abs(got.z - want.z) < 1e-9,
                    "\(note) \(corner): \(got) vs \(want)")
        }
    }

    private func expectRigid(_ frame: ModelFrame) {
        let axes = [frame.xAxis, frame.yAxis, frame.zAxis]
        func dot(_ a: Vector3, _ b: Vector3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
        for i in 0..<3 {
            #expect(abs(dot(axes[i], axes[i]) - 1) < 1e-12)
            for j in 0..<i { #expect(abs(dot(axes[i], axes[j])) < 1e-12) }
        }
        let cross = Vector3(frame.xAxis.y * frame.yAxis.z - frame.xAxis.z * frame.yAxis.y,
                            frame.xAxis.z * frame.yAxis.x - frame.xAxis.x * frame.yAxis.z,
                            frame.xAxis.x * frame.yAxis.y - frame.xAxis.y * frame.yAxis.x)
        #expect(abs(dot(cross, frame.zAxis) - 1) < 1e-12)
    }

    /// Identity: corners + (10, 5, 1.6).
    @Test func identityTop() {
        let frame = Self.frame()
        expect(frame, Self.corners.map { Vector3($0.x + 10, $0.y + 5, $0.z + 1.6) }, "identity")
        expectRigid(frame)
    }

    /// Angle 90: Rz(90) maps (x, y) to (-y, x); (3, 2, 1) -> (-2, 3, 1) + (10, 5, 1.6) = (8, 8, 2.6).
    @Test func topAngle90() {
        let frame = Self.frame(angle: 90)
        expect(frame, Self.corners.map { Vector3(-$0.y + 10, $0.x + 5, $0.z + 1.6) }, "angle 90")
        #expect(abs(frame.apply(Vector3(3, 2, 1)).x - 8) < 1e-9)
        expectRigid(frame)
    }

    /// Rotate (0, 0, 90) acts as Rz(-90): (x, y) -> (y, -x); then offset (1, 2, 3); then p and thickness.
    /// (3, 2, 1) -> (2, -3, 1) -> (3, -1, 4) -> (13, 4, 5.6).
    @Test func topOffsetAndRotateZ() {
        let frame = Self.frame(offset: Vector3(1, 2, 3), rotation: Vector3(0, 0, 90))
        expect(frame, Self.corners.map { Vector3($0.y + 1 + 10, -$0.x + 2 + 5, $0.z + 3 + 1.6) }, "offset + rz")
        #expect(frame.apply(Vector3(3, 2, 1)) == Vector3(13, 4, 5.6))
        expectRigid(frame)
    }

    /// Back, angle 0: Rx(pi) maps (x, y, z) to (x, -y, -z); z0 = 0. (3, 2, 1) -> (3, -2, -1) + (10, 5, 0).
    @Test func backAngle0() {
        let frame = Self.frame(back: true)
        expect(frame, Self.corners.map { Vector3($0.x + 10, -$0.y + 5, -$0.z) }, "back")
        expectRigid(frame)
    }

    /// Back, angle 30, offset (0.5, -1, 0.2), rotate (10, 20, 30). Worked with 3x3 matrices (angles in degrees):
    ///   model rotation Rm = Rz(-30) Ry(-20) Rx(-10)
    ///     = [[ 0.8137976813,  0.5438381425, -0.2048741287],
    ///        [-0.4698463104,  0.8231729446,  0.3187957776],
    ///        [ 0.3420201433, -0.1631759112,  0.9254165784]]
    ///   footprint A = Rz(30) Rx(180) = [[0.8660254038, 0.5, 0], [0.5, -0.8660254038, 0], [0, 0, -1]]
    ///   R = A Rm = [[ 0.4698463104,  0.8825641193, -0.0180283112],
    ///               [ 0.8137976813, -0.4409696105, -0.3785223064],
    ///               [-0.3420201433,  0.1631759112, -0.9254165784]]
    ///   origin = (10, 5, 0) + A (0.5, -1, 0.2) = (10 - 0.0669872981, 5 + 1.1160254038, -0.2)
    ///   corner c -> R c + origin; eight corners in test order (x, y, z over 0...3, 0...2, 0...1).
    @Test func backAngle30FullChain() {
        let frame = Self.frame(back: true, angle: 30, offset: Vector3(0.5, -1, 0.2), rotation: Vector3(10, 20, 30))
        expect(frame, [
            Vector3(9.9330127019, 6.1160254038, -0.2), Vector3(9.9149843907, 5.7375030974, -1.1254165784),
            Vector3(11.6981409404, 5.2340861827, 0.1263518223), Vector3(11.6801126292, 4.8555638764, -0.7990647561),
            Vector3(11.3425516331, 8.5574184478, -1.22606043), Vector3(11.3245233218, 8.1788961415, -2.1514770084),
            Vector3(13.1076798716, 7.6754792268, -0.8997086076), Vector3(13.0896515604, 7.2969569204, -1.825125186),
        ], "back 30")
        expectRigid(frame)
    }

    @Test func everyCaseIsRightHanded() {
        for back in [false, true] {
            for angle in [0.0, 30, 135, -70] {
                expectRigid(Self.frame(back: back, angle: angle, offset: Vector3(1, -2, 3),
                                       rotation: Vector3(15, -40, 200)))
            }
        }
    }
}
