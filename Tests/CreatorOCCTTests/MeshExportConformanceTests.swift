import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct MeshExportConformanceTests {
    @Test(arguments: KernelUnderTest.allCases)
    func boxMeshCoversEveryFaceAndEdge(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let mesh = try await kernel.tessellate(solid, tolerance: 0.1)
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.triangleFaces.count == mesh.indices.count / 3)
        #expect(mesh.triangleFaces.count >= 12)
        #expect(Set(mesh.triangleFaces) == Set(solid.topology.faces.map(\.id)))
        #expect(mesh.normals.count == mesh.positions.count)
        #expect(mesh.normals.allSatisfy { isClose($0.length, 1, relative: 1e-6) })
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
        let slack = Vector3(1e-6, 1e-6, 1e-6)
        #expect(mesh.positions.allSatisfy { p in
            p.x >= solid.bounds.min.x - slack.x && p.x <= solid.bounds.max.x + slack.x
                && p.z >= solid.bounds.min.z - slack.z && p.z <= solid.bounds.max.z + slack.z
        })
        #expect(mesh.edgePolylines.count == 12)
        #expect(mesh.edgePolylines.values.allSatisfy { $0.count >= 2 })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func meshNormalsPointOutward(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 2, 2, 2)
        let mesh = try await kernel.tessellate(solid, tolerance: 0.1)
        let center = solid.bounds.center
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.positions[Int(mesh.indices[triangle])]
            let b = mesh.positions[Int(mesh.indices[triangle + 1])]
            let c = mesh.positions[Int(mesh.indices[triangle + 2])]
            let winding = (b - a).cross(c - a)
            #expect(winding.dot(a - center) > 0, "triangle \(triangle / 3) is wound inward")
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func seamEdgesHaveNoPolyline(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let rod = try await kernel.extrude(.circle(radius: 2, center: .zero, plane: .xy), distance: 5, mode: .oneSided, tag: newTag())
        let mesh = try await kernel.tessellate(rod, tolerance: 0.05)
        let seams = rod.topology.edges.filter(\.isSeam).map(\.id)
        #expect(!seams.isEmpty)
        #expect(seams.allSatisfy { mesh.edgePolylines[$0] == nil })
        #expect(mesh.edgePolylines.count == 2)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func stepExportRoundTripsVolumeAndFaces(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 10, 20, 30)
        let edge = try #require(a.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
        let filleted = try await kernel.fillet(a, edges: [edge.id], radius: 2, tag: newTag())
        let b = try await kernel.transform(try await box(kernel, 5, 5, 5), by: Transform(translation: Vector3(50, 0, 0)), tag: newTag())
        let url = URL.temporaryDirectory.appending(path: "conformance-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([filleted, b], format: .step, to: url)
        let read = try OCCTShape.readSTEP(url)
        let expected = try await kernel.properties(of: filleted).volume + 125
        #expect(isClose(try read.properties().volume, expected, relative: 1e-5))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("SI_UNIT(.MILLI.,.METRE.)"), "the STEP file must declare millimetres")
        #expect(try OCCTRawTopology.read(read).faces.count == 7 + 6)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func stlExportIsClosedAndManifold(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(.circle(radius: 3, center: .zero, plane: .xy), distance: 4, mode: .oneSided, tag: newTag())
        let url = URL.temporaryDirectory.appending(path: "conformance-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([solid], format: .stl, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(edgeUseCounts(stl: text).values.allSatisfy { $0 == 2 }, "every mesh edge must be shared by exactly two triangles")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func exportToAnUnwritablePathIsAPlainError(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 1, 1, 1)
        for format in ExportFormat.allCases {
            let error = await #expect(throws: KernelError.self) {
                try await kernel.export([solid], format: format, to: URL(filePath: "/nonexistent-directory/out.\(format.rawValue)"))
            }
            guard case .exportFailed? = error else { Issue.record("expected exportFailed for \(format)"); continue }
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func exportingNothingIsRejected(_ under: KernelUnderTest) async {
        await #expect(throws: KernelError.invalidInput("There is nothing to export.")) {
            try await under.make().export([], format: .step, to: URL.temporaryDirectory.appending(path: "empty.step"))
        }
    }

    /// Counts how many triangles use each undirected edge, after welding vertices to 1e-6 mm.
    func edgeUseCounts(stl: String) -> [String: Int] {
        func key(_ line: Substring) -> String {
            line.split(separator: " ").dropFirst().prefix(3).map { (Double($0) ?? .nan).formatted(.number.precision(.fractionLength(6))) }
                .joined(separator: ",")
        }
        let vertices = stl.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("vertex") }.map { key(Substring($0)) }
        var counts: [String: Int] = [:]
        for triangle in stride(from: 0, to: vertices.count - 2, by: 3) {
            let corners = [vertices[triangle], vertices[triangle + 1], vertices[triangle + 2]]
            for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                let edge = [corners[a], corners[b]].sorted().joined(separator: "|")
                counts[edge, default: 0] += 1
            }
        }
        return counts
    }
}
