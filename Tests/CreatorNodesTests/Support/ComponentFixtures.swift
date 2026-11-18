// Test fixture file: 3D model files for the Import KiCad Board component tests, made with the OCCT kernel.
#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
@testable import CreatorOCCT

enum ComponentFixtures {
    /// The L block's profile: 6 x 5, its notch the corner x > 2, y > 2.
    static let outline = [Vector2(0, 0), Vector2(6, 0), Vector2(6, 2), Vector2(2, 2), Vector2(2, 5), Vector2(0, 5)]

    /// The block's twelve vertices, 3 mm tall (a rotated block's box is that of these, not of its own bounding box).
    static let corners: [Vector3] = outline.flatMap { point in [0.0, 3.0].map { Vector3(point.x, point.y, $0) } }

    static func lBlock(_ kernel: OCCTKernel) async throws -> Solid {
        let points = outline
        let segments = points.indices.map { Segment2D.line(points[$0], points[($0 + 1) % points.count]) }
        return try await kernel.extrude(Profile2D(plane: .xy, segments: segments), distance: 3, mode: .oneSided,
                                        tag: NodeTag(node: NodeID(), item: 0))
    }

    static func step(_ kernel: OCCTKernel, scaledBy factor: Double = 1) async throws -> Data {
        var solid = try await lBlock(kernel)
        if factor != 1 {
            solid = try await kernel.scaled(solid, by: Vector3(factor, factor, factor), tag: NodeTag(node: NodeID(), item: 0))
        }
        let url = URL.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([solid], format: .step, to: url)
        return try Data(contentsOf: url)
    }

    /// The L block written as a closed shell with no solid around it, as some vendors' component models are.
    static func shellStep(_ kernel: OCCTKernel) async throws -> Data {
        let shape = try await kernel.shape(of: try await lBlock(kernel))
        let url = URL.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        try OCCTKernel.serialized { () throws in try shape.children()[0].writeSTEP(to: url, unit: "MM") }
        return try Data(contentsOf: url)
    }

    static func iges(_ kernel: OCCTKernel) async throws -> Data {
        let shape = try await kernel.shape(of: try await lBlock(kernel))
        let url = URL.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString).igs")
        defer { try? FileManager.default.removeItem(at: url) }
        try OCCTKernel.serialized { () throws in try shape.writeIGES(to: url) }
        return try Data(contentsOf: url)
    }

    /// One gzip member of stored deflate blocks, its CRC-32 and size.
    static func gzip(_ data: Data) -> Data {
        func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) } }
        var out: [UInt8] = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3]
        var rest = [UInt8](data)[...]
        repeat {
            let chunk = rest.prefix(65_535)
            rest = rest.dropFirst(chunk.count)
            let length = UInt16(chunk.count)
            out += [rest.isEmpty ? 1 : 0, UInt8(length & 255), UInt8(length >> 8), UInt8(~length & 255), UInt8(~length >> 8)]
            out += chunk
        } while !rest.isEmpty
        out += le32(CRC32.checksum(data)) + le32(UInt32(truncatingIfNeeded: data.count))
        return Data(out)
    }
}
#endif
