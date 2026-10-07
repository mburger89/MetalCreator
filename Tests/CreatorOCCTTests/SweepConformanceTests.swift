import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct SweepConformanceTests {
    /// A 5 × 4 rectangle on the XZ plane spanning x 5…10, z 0…4 (a tube cross-section).
    let ring = Profile2D.rectangle(width: 5, height: 4, plane: Plane(origin: Vector3(7.5, 0, 2), normal: -.unitY, xAxis: .unitX))

    @Test(arguments: KernelUnderTest.allCases)
    func fullRevolveMakesATube(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let tube = try await kernel.revolve(ring, axis: .z, angle: .degrees(360), tag: tag)
        #expect(isClose(try await kernel.properties(of: tube).volume, Double.pi * (100 - 25) * 4, relative: 1e-5))
        #expect(tube.topology.faces.count == 4)
        #expect(faces(tube, role: .startCap, of: tag).isEmpty)
        for k in 0..<4 {
            #expect(faces(tube, role: .side(segment: k), of: tag).count == 1)
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func partialRevolveHasCaps(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let quarter = try await kernel.revolve(ring, axis: .z, angle: .degrees(90), tag: tag)
        #expect(isClose(try await kernel.properties(of: quarter).volume, Double.pi * (100 - 25) * 4 / 4, relative: 1e-5))
        #expect(faces(quarter, role: .startCap, of: tag).count == 1)
        #expect(faces(quarter, role: .endCap, of: tag).count == 1)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func revolveInputsAreValidated(_ under: KernelUnderTest) async {
        let kernel = under.make()
        await #expect(throws: KernelError.invalidInput("The revolve angle must be between 0° and 360°.")) {
            try await kernel.revolve(ring, axis: .z, angle: .degrees(0), tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("The revolve axis needs a direction.")) {
            try await kernel.revolve(ring, axis: Axis(origin: .zero, direction: .zero), angle: .degrees(90), tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func ruledLoftBetweenSquaresIsAFrustum(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let bottom = Profile2D.rectangle(width: 10, height: 10, plane: .xy)
        let top = Profile2D.rectangle(width: 6, height: 6, plane: Plane.xy.offset(by: 10))
        let frustum = try await kernel.loft([bottom, top], ruled: true, tag: tag)
        #expect(isClose(try await kernel.properties(of: frustum).volume, 10.0 / 3.0 * (100 + 36 + 60), relative: 1e-5))
        #expect(frustum.topology.faces.count == 6)
        #expect(faces(frustum, role: .startCap, of: tag).count == 1)
        #expect(faces(frustum, role: .endCap, of: tag).count == 1)
        for k in 0..<4 {
            #expect(faces(frustum, role: .side(segment: k), of: tag).count == 1)
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func loftInputsAreValidated(_ under: KernelUnderTest) async {
        let kernel = under.make()
        let square = Profile2D.rectangle(width: 1, height: 1, plane: .xy)
        await #expect(throws: KernelError.invalidInput("A loft needs at least two sections.")) {
            try await kernel.loft([square], ruled: true, tag: newTag())
        }
        let circle = Profile2D.circle(radius: 1, center: .zero, plane: Plane.xy.offset(by: 5))
        await #expect(throws: KernelError.invalidInput("Every loft section needs the same number of segments.")) {
            try await kernel.loft([square, circle], ruled: true, tag: newTag())
        }
    }
}
