import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// What the nodes do over `KernelUnavailable` (cross-platform spec 2.3): the ones that need geometry show the kernel's sentence on
/// their badges, and the ones that don't go on working.
struct KernelUnavailableNodeTests {
    static let message = "Geometry isn't available on this platform yet."

    @Test func aNodeThatNeedsGeometryShowsTheKernelsSentenceOnItsBadge() async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self)
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(10)])
        h.wire(rectangle, "profile", to: extrude, "profile")
        let report = try await h.run([extrude], kernel: KernelUnavailable())
        #expect(report.error(extrude) == Self.message)
        #expect(!report.isOK(extrude))
    }

    @Test func theNodesThatMakeProfilesStillWork() async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self)
        let report = try await h.run([rectangle], kernel: KernelUnavailable())
        #expect(report.isOK(rectangle))
        #expect(report.value(rectangle, "profile")?.profiles?.count == 1)
    }
}
