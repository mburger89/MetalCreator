import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp

/// Where the slice starts and what it covers (fields spec §6, "Slice plane").
struct SlicePoseTests {
    /// A 60 × 40 × 6 plate, top on z = 0.
    let bounds = BoundingBox(min: Vector3(-30, -20, -6), max: Vector3(30, 20, 0))
    let noise = Field.noise(seed: 1, scale: 5, octaves: 1)

    func eye(yaw: Double, pitch: Double) -> Vector3 { CameraPose(target: .zero, distance: 1, yaw: yaw, pitch: pitch).toEye }

    @Test func aFieldWithAPlaneStartsOnIt() {
        let plane = Plane(origin: Vector3(-30, 0, 0), normal: .unitX, xAxis: .unitY)
        let pose = SlicePose.starting(for: .linearGradient(plane: plane, length: 60), bounds: bounds, toEye: eye(yaw: 0, pitch: 1))
        #expect(pose.choice == .own && pose.offset == 0)
        #expect(pose.worldPlane.normal == .unitX && pose.worldPlane.origin.x == -30, "on the gradient's plane, 0 at the edge")
        #expect(abs(pose.worldPlane.origin.y) < 1e-9 && abs(pose.worldPlane.origin.z + 3) < 1e-9, "centred on the part in the plane")
        #expect(abs(pose.halfWidth - 22) < 1e-9 && abs(pose.halfHeight - 3.3) < 1e-9, "the box seen along x, 10% to spare")
        #expect(abs(pose.offsetLimit - 60) < 1e-9, "far enough to reach the other end of the part")
    }

    @Test func withoutOneItGoesThroughTheBoxCentreOnTheAxisPlaneNearestTheCamera() {
        let above = SlicePose.starting(for: noise, bounds: bounds, toEye: eye(yaw: 0.3, pitch: 1.4))
        #expect(above.choice == .axis(.xy) && above.worldPlane.normal == .unitZ && above.worldPlane.origin == Vector3(0, 0, -3))
        #expect(abs(above.halfWidth - 33) < 1e-9 && abs(above.halfHeight - 22) < 1e-9)
        let front = SlicePose.starting(for: noise, bounds: bounds, toEye: eye(yaw: 0, pitch: 0))
        #expect(front.choice == .axis(.xz) && abs(front.worldPlane.normal.y) == 1)
        let right = SlicePose.starting(for: noise, bounds: bounds, toEye: eye(yaw: .pi / 2, pitch: 0))
        #expect(right.choice == .axis(.yz) && abs(right.worldPlane.normal.x) == 1)
    }

    @Test func aTieGoesToXYThenYZThenXZ() {
        let tie = Vector3(1, 1, 1).normalized ?? .unitZ
        #expect(SlicePose.starting(for: noise, bounds: bounds, toEye: tie).choice == .axis(.xy))
        let yz = Vector3(1, 0, 0), xz = Vector3(0, 1, 0)
        #expect(SlicePose.starting(for: noise, bounds: bounds, toEye: yz).choice == .axis(.yz))
        #expect(SlicePose.starting(for: noise, bounds: bounds, toEye: xz).choice == .axis(.xz))
    }

    /// The default camera looks along (1, 1, 1) up to the last bits of its sines and cosines, which differ between platforms'
    /// maths libraries (the Windows suite chose YZ). Last-bit differences are still a tie.
    @Test(arguments: [Vector3(1 + 1e-13, 1, 1), Vector3(1, 1 + 1e-13, 1), Vector3(1, 1, 1 - 1e-13), Vector3(1 + 2e-13, 1 + 1e-13, 1)])
    func aTieWithinTheLastBitsStillGoesToXY(toEye: Vector3) {
        #expect(SlicePose.startingChoice(for: noise, toEye: toEye) == .axis(.xy))
        #expect(SlicePose.starting(for: noise, bounds: bounds, toEye: toEye).choice == .axis(.xy))
    }

    @Test func aRealDifferenceIsNotATie() {
        #expect(SlicePose.startingChoice(for: noise, toEye: Vector3(1.001, 1, 1)) == .axis(.yz))
        #expect(SlicePose.startingChoice(for: noise, toEye: Vector3(1, 1.001, 1)) == .axis(.xz))
    }

    @Test func theStartingChoiceNeedsNoBox() {
        let plane = Plane(origin: .zero, normal: .unitX, xAxis: .unitY)
        #expect(SlicePose.startingChoice(for: .linearGradient(plane: plane, length: 5), toEye: eye(yaw: 0, pitch: 0)) == .own)
        #expect(SlicePose.startingChoice(for: noise, toEye: eye(yaw: 0, pitch: 0)) == .axis(.xz))
        let degenerate = Plane(origin: .zero, normal: .zero, xAxis: .unitX)
        #expect(SlicePose.startingChoice(for: .linearGradient(plane: degenerate, length: 5), toEye: eye(yaw: 0, pitch: 1.5)) == .axis(.xy))
    }

    @Test func aPoseForAChoiceIsTheStartingOneOrNothing() {
        let plane = Plane(origin: Vector3(-30, 0, 0), normal: .unitX, xAxis: .unitY)
        let gradient = Field.linearGradient(plane: plane, length: 60)
        #expect(SlicePose.pose(for: .own, field: gradient, bounds: bounds)?.choice == .own)
        #expect(SlicePose.pose(for: .own, field: noise, bounds: bounds) == nil, "no plane of its own")
        #expect(SlicePose.pose(for: .axis(.yz), field: noise, bounds: bounds) == SlicePose.through(.yz, bounds: bounds))
        #expect(SlicePose.pose(for: .hidden, field: noise, bounds: bounds) == nil)
    }

    @Test func theLegendsAxisButtonsGoThroughTheCentreToo() {
        for axis in SliceAxis.allCases {
            let pose = SlicePose.through(axis, bounds: bounds)
            #expect(pose.choice == .axis(axis) && pose.offset == 0)
            #expect(isOnCentre(pose.worldPlane.origin), "\(axis)")
        }
    }

    @Test func anOwnPlaneWithoutAUsableNormalGivesNoPose() {
        for normal in [Vector3.zero, Vector3(.nan, 0, 1), Vector3(.infinity, 0, 0)] {
            let plane = Plane(origin: .zero, normal: normal, xAxis: .unitX)
            let field = Field.linearGradient(plane: plane, length: 10)
            #expect(SlicePose.pose(for: .own, field: field, bounds: bounds) == nil, "\(normal)")
        }
    }

    func isOnCentre(_ point: Vector3) -> Bool { (point - bounds.center).length < 1e-9 }

    @Test func movingAddsTheOffsetAlongTheNormalAndHoldsItToTheLimit() {
        let pose = SlicePose.through(.xy, bounds: bounds)
        let moved = pose.moved(to: 2)
        #expect(moved.offset == 2 && moved.worldPlane.origin == Vector3(0, 0, -1) && moved.halfWidth == pose.halfWidth)
        #expect(pose.moved(to: 1_000).offset == pose.offsetLimit && pose.moved(to: -1_000).offset == -pose.offsetLimit)
        #expect(pose.moved(to: .nan).offset == 0, "not a number: stays put")
        #expect(pose.moved(to: .infinity).offset == pose.offsetLimit && pose.moved(to: -.infinity).offset == -pose.offsetLimit)
    }

    @Test func aFlatBoxStillMakesAUsableQuad() {
        let flat = BoundingBox(min: Vector3(-5, -5, 0), max: Vector3(5, 5, 0))
        let pose = SlicePose.through(.xz, bounds: flat)
        #expect(pose.halfHeight >= 0.5 && pose.offsetLimit >= 1)
    }

    @Test func theGridIsFinerWhereNoKernelIsNeeded() async throws {
        #expect(SlicePose.resolution(for: noise) == 256)
        let solid = try await FakeKernelBox.solid()
        #expect(SlicePose.resolution(for: .distance(.kernel(.solid(solid)), signed: true)) == 64)
        #expect(SlicePose.resolution(for: .distance(.point(.zero), signed: false)) == 256)
    }
}

import CreatorKernel

/// A solid to measure to.
enum FakeKernelBox {
    static func solid() async throws -> Solid {
        try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                       tag: NodeTag(node: NodeID(), item: 0))
    }
}
