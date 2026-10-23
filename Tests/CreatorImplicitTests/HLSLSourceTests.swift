import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// The HLSL the generator writes (plan xp-c, X-C1 "follow macOS"): the same walk as the Metal source, statement for statement; the Metal source itself
/// unchanged by the dialect; the HLSL rules of the Global Constraints.
struct HLSLSourceTests {
    static var fixtures: [(name: String, solid: ImplicitSolid)] { GPUFixtures.all + LatticeFixtures.everyMapped + ImplicitFixtures.all }

    /// FNV-1a 64 of the UTF-8 text, as hex: stable across processes, unlike `Hasher`.
    static func digest(_ text: String) -> String { KernelSource.fnv1a(text) }

    /// Run once with `XP_RECORD_MSL_DIGESTS=1` before the generator gains its dialect, and paste the printed table into
    /// `MetalSourceDigests.swift`.
    @Test(arguments: fixtures.map(\.name))
    func theMetalSourceIsTheOneRecordedBeforeTheDialect(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        guard let source = (try? ImplicitCompiler.compile(solid))?.source else { return }
        if ProcessInfo.processInfo.environment["XP_RECORD_MSL_DIGESTS"] == "1" { print("MSLDIGEST \"\(name)\": \"\(Self.digest(source))\",") }
        #expect(MetalSourceDigests.table[name] == Self.digest(source), "\(name): the Metal source changed")
    }
}
