import CreatorGeometry
import CreatorKernel
import CreatorOCCT
import Metal
import Testing
@testable import CreatorViewport

/// Guides (spec §6.3, Errata (M6)): a guide's selected edges are drawn over the scene, its surfaces and ID-pass pixels
/// never. These read a few pixels back, like the view cube's label test. The colours are far apart: the selection
/// pink (#ff79c6), the edge white (#f8f8f2) and the dark background.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct GuideRenderTests {
    /// A box standing on z = 0, centred on x = 0 and y = 0 (as `OffscreenRenderTests.box()` builds one).
    func box(width: Double, depth: Double, height: Double) async throws -> (solid: Solid, mesh: DisplayMesh) {
        let kernel = OCCTKernel()
        let solid = try await kernel.extrude(.rectangle(width: width, height: depth, plane: .xy), distance: height,
                                             mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        return (solid, try await kernel.tessellate(solid, tolerance: 0.05))
    }

    /// `OffscreenRenderTests`' view (front, orthographic, 5 points per mm) of a 10 × 20 × 30 part, with `guide`'s
    /// every edge selected on a guide item when there is one.
    func frame(guide: DisplayMesh?) async throws -> ViewportFrame {
        let part = try await box(width: 10, depth: 20, height: 30)
        var frame = TestFrames.frame(mesh: part.mesh, pose: OffscreenRenderTests.front, size: OffscreenRenderTests.size,
                                     bounds: part.solid.bounds)
        if let guide {
            frame.items.append(FrameItem(meshSerial: 2, mesh: guide, solidIndex: 1, isGhost: false, hoveredFace: nil,
                                         selectedFaces: [], selectedEdges: Set(guide.edgePolylines.keys), isGuide: true))
        }
        return frame
    }

    /// The main pass at 2 pixels per point, as BGRA bytes of a 400 × 400 target.
    func render(_ frame: ViewportFrame) throws -> [UInt8] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try ViewportRenderer(device: device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 400, height: 400,
                                                                  mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())
        renderer.encode(frame, into: target, scale: 2, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: 400 * 400 * 4)
        target.getBytes(&bytes, bytesPerRow: 400 * 4, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
        return bytes
    }

    /// The colour at view point (`x`, `y`).
    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test func aGuidesEdgesDrawInTheSelectionColourOverEmptySpaceAndItsSurfacesDoNot() async throws {
        let wide = try await box(width: 30, depth: 20, height: 30)
        let with = try render(try await frame(guide: wide.mesh))
        let without = try render(try await frame(guide: nil))
        // The guide spans x -15…15 mm: its left edges are at view x = 25, clear of the part (x 75…125).
        let edge = color(with, 25, 100)
        #expect(edge[0] > 200 && edge[2] > 150 && edge[1] < 170, "pink: \(edge)")
        #expect(color(without, 25, 100)[0] < 100, "the dark background")
        #expect(color(with, 40, 100) == color(without, 40, 100), "inside the guide, off its edges: no surface is drawn")
    }

    @Test func aGuideEdgeOnThePartCoversThePartsEdgeInTheSelectionColour() async throws {
        let wide = try await box(width: 30, depth: 20, height: 30)
        let with = try render(try await frame(guide: wide.mesh))
        let without = try render(try await frame(guide: nil))
        // The guide's top front edge runs along the part's, at view y = 25, between x = 75 and 125.
        #expect(color(without, 100, 25)[1] > 230, "the part's own edge is white")
        let covered = color(with, 100, 25)
        #expect(covered[0] > 200 && covered[1] < 170, "and the guide's edge glows over it: \(covered)")
    }

    @Test func aGuideIsNeverPicked() async throws {
        let wide = try await box(width: 30, depth: 20, height: 30)
        let with = try await frame(guide: wide.mesh)
        let without = try await frame(guide: nil)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let picker = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        let reference = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        #expect(picker.pick(at: ScreenPoint(25, 100), in: with) == nil, "on the guide's edge")
        #expect(picker.pick(at: ScreenPoint(40, 100), in: with) == nil, "where the guide's face would be")
        #expect(picker.pick(at: ScreenPoint(100, 100), in: with) == reference.pick(at: ScreenPoint(100, 100), in: without),
                "the part is picked as before")
    }

    @Test func anEdgeBehindThePartStaysHidden() async throws {
        let inside = try await box(width: 4, depth: 4, height: 10)
        let with = try render(try await frame(guide: inside.mesh))
        let without = try render(try await frame(guide: nil))
        // The guide's left edges are at view x = 90, 8 mm behind the part's front face.
        #expect(color(with, 90, 150) == color(without, 90, 150))
    }
}
