#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
@testable import CreatorOCCT

/// The §7.2 acceptance bracket's chamfered plate, built the way `NamingStabilityTests` builds it (shared with the projection tests).
enum BracketFixture {
    static func chamfered(_ kernel: any Kernel) async throws -> Solid {
        let builder = NamingStabilityTests()
        let holes = builder.grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20)
        return try await builder.build(kernel, nodes: .init(), outline: .rectangle(width: 90, height: 40, plane: .xy),
                                       holeCenters: holes).chamfered
    }
}
#endif
