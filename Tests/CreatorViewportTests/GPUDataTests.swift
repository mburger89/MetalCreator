import CreatorGeometry
import CreatorKernel
import simd
import Testing
@testable import CreatorViewport

struct GPUDataTests {
    let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))

    /// These must match the MSL structs in ViewportShaders.swift byte for byte.
    @Test func gpuStructsHaveTheShaderStrides() {
        #expect(MemoryLayout<MeshVertex>.stride == 48)
        #expect(MemoryLayout<LineInstance>.stride == 64)
        #expect(MemoryLayout<LineInstance>.offset(of: \LineInstance.width) == 48)
        #expect(MemoryLayout<CubeVertex>.stride == 64)
        #expect(MemoryLayout<CubeVertex>.offset(of: \CubeVertex.uv) == 32)
        #expect(MemoryLayout<CubeVertex>.offset(of: \CubeVertex.labelRect) == 48)
        #expect(MemoryLayout<FrameUniforms>.stride == 176)
        #expect(MemoryLayout<FrameUniforms>.offset(of: \FrameUniforms.viewportPixels) == 160)
        #expect(MemoryLayout<DrawUniforms>.stride == 16)
        #expect(MemoryLayout<ShadeUniforms>.stride == 64)
        #expect(MemoryLayout<BackgroundUniforms>.stride == 32)
        #expect(MemoryLayout<LineUniforms>.stride == 16)
        #expect(MemoryLayout<GridUniforms>.stride == 48)
        #expect(MemoryLayout<GridUniforms>.offset(of: \GridUniforms.minorColor) == 16)
    }

    @Test func pickIDsRoundTripAndRejectWhatDoesNotFit() {
        for target in [PickTarget.face(solid: 0, FaceID(0)), .face(solid: 255, FaceID(4_194_303)), .edge(solid: 3, EdgeID(17))] {
            let raw = PickID.encode(target)
            #expect(raw != nil && raw != 0)
            #expect(raw.flatMap(PickID.decode) == target)
        }
        #expect(PickID.decode(0) == nil)
        #expect(PickID.decode(3 << 30) == nil, "kind 3 is unused")
        #expect(PickID.encode(.face(solid: 256, FaceID(0))) == nil)
        #expect(PickID.encode(.edge(solid: 0, EdgeID(1 << 22))) == nil)
        #expect(PickID.encode(.face(solid: -1, FaceID(0))) == nil)
        #expect(PickID.base(kind: PickID.faceKind, solid: 2) == (1 << 30) | (2 << 22))
    }

    @Test func meshVerticesAreDeIndexedAndCarryTheirFace() {
        let mesh = TestMeshes.box(bounds)
        let vertices = GPUGeometry.meshVertices(mesh)
        #expect(vertices.count == mesh.indices.count)
        #expect(vertices[0].face == 0)
        #expect(vertices[vertices.count - 1].face == 5)
        #expect(vertices[6].position == GPUGeometry.float3(mesh.positions[Int(mesh.indices[6])]))
        var broken = mesh
        broken.indices[0] = 999
        #expect(GPUGeometry.meshVertices(broken).count == mesh.indices.count - 3, "a triangle with a bad index is skipped")
    }

    @Test func edgeInstancesAreOnePerSegmentWithTheirPickID() {
        let mesh = TestMeshes.box(bounds)
        let instances = GPUGeometry.edgeInstances(mesh.edgePolylines, solid: 2, selected: [EdgeID(1)], selectedOnly: false, scale: 2)
        #expect(instances.count == 12)
        #expect(instances.map(\.id).compactMap(PickID.decode).count == 12)
        #expect(PickID.decode(instances[1].id) == .edge(solid: 2, EdgeID(1)))
        #expect(instances[1].color == ViewportPalette.dracula.selection)
        #expect(instances[1].width == 5)
        #expect(instances[0].color == ViewportPalette.dracula.edge)
        #expect(instances[0].width == 2.5)
        let selectedOnly = GPUGeometry.edgeInstances(mesh.edgePolylines, solid: 0, selected: [EdgeID(1)], selectedOnly: true, scale: 1)
        #expect(selectedOnly.count == 1)
    }

    @Test func hiddenEdgesTakeTheFadedSelectionColour() {
        let mesh = TestMeshes.box(bounds)
        let palette = ViewportPalette.dracula
        let hidden = GPUGeometry.edgeInstances(mesh.edgePolylines, solid: 1, selected: [EdgeID(1)], selectedOnly: true, scale: 1,
                                               hidden: true)
        #expect(hidden.count == 1)
        #expect(hidden[0].color == palette.hiddenSelection)
        #expect(SIMD3(hidden[0].color.x, hidden[0].color.y, hidden[0].color.z)
            == SIMD3(palette.selection.x, palette.selection.y, palette.selection.z), "the same hue")
        #expect(abs(hidden[0].color.w - palette.selection.w * ViewportPalette.hiddenGuideOpacity) < 1e-6)
        #expect(hidden[0].color.w < palette.selection.w)
        let shown = GPUGeometry.edgeInstances(mesh.edgePolylines, solid: 1, selected: [EdgeID(1)], selectedOnly: true, scale: 1)
        #expect(shown[0].color == palette.selection, "not hidden: unchanged")
    }

    @Test func faceFlagsMarkHoverAndSelection() {
        let flags = GPUGeometry.faceFlags(count: 4, hovered: FaceID(1), selected: [FaceID(1), FaceID(3), FaceID(9)])
        #expect(flags == [0, 3, 0, 2])
    }

    @Test func handlesBecomeAShaftAndAKnob() {
        let handle = ViewportHandle(id: "h", anchor: .zero, direction: Vector3(0, 0, 2), value: 6, range: 0...50,
                                    style: .linear, tint: .feature)
        #expect(handle.knob == Vector3(0, 0, 6))
        let lines = GPUGeometry.handleInstances([handle], scale: 1)
        #expect(lines.count == 2)
        #expect(lines[1].a == lines[1].b, "the knob is a square drawn from a zero-length line")
        #expect(lines.allSatisfy { $0.color == ViewportPalette.dracula.feature })
    }

    @Test func theCubeIsSixVerticesPerTileAndHighlightsTheHoveredRegion() {
        func isCyan(_ vertex: CubeVertex) -> Bool {
            vertex.color.x == ViewportPalette.dracula.hover.x && vertex.color.z == ViewportPalette.dracula.hover.z
        }
        func firstVertex(of region: ViewCubeRegion, in vertices: [CubeVertex]) -> CubeVertex {
            vertices[(ViewCubeCell.all.firstIndex { $0.region == region } ?? 0) * 6]
        }
        // Looking from the front makes FRONT the active region, so hover a different one (RIGHT) to isolate the hover branch.
        let pose = CameraPose(target: .zero, distance: 10, yaw: 0, pitch: 0)
        let vertices = GPUGeometry.cubeVertices(hovered: .right, pose: pose)
        #expect(vertices.count == 54 * 6)
        #expect(isCyan(firstVertex(of: .right, in: vertices)), "the hovered, non-active region is cyan")
        #expect(!isCyan(firstVertex(of: .back, in: vertices)), "a region that is neither hovered nor active is not cyan")
        let unhovered = GPUGeometry.cubeVertices(hovered: nil, pose: pose)
        #expect(!isCyan(firstVertex(of: .right, in: unhovered)), "without hover RIGHT is not cyan")
    }

    @Test func theCubeTintsTheRegionTheCameraLooksFrom() {
        func isCyan(_ vertex: CubeVertex) -> Bool {
            vertex.color.x == ViewportPalette.dracula.hover.x && vertex.color.z == ViewportPalette.dracula.hover.z
        }
        let tile = (ViewCubeCell.all.firstIndex { $0.region == .front } ?? 0) * 6
        let front = GPUGeometry.cubeVertices(hovered: nil, pose: CameraPose(target: .zero, distance: 10, yaw: 0, pitch: 0))
        #expect(isCyan(front[tile]), "looking from the front, FRONT is the active face")
        #expect(front.filter(isCyan).count == 6 * ViewCubeCell.all.filter { $0.region == .front }.count)
        let turned = GPUGeometry.cubeVertices(hovered: nil, pose: CameraPose(target: .zero, distance: 10, yaw: 0.3, pitch: 0))
        #expect(!turned.contains(where: isCyan), "between regions, nothing is active")
    }

    @Test func frameUniformsCarryTheViewportAndProjection() {
        let pose = CameraPose(target: .zero, distance: 10, yaw: 0, pitch: 0, projection: .orthographic)
        let uniforms = GPUGeometry.frameUniforms(pose, size: ViewportSize(width: 200, height: 100), sceneRadius: 5,
                                                 pixelWidth: 400, pixelHeight: 200)
        #expect(uniforms.viewportPixels == SIMD2(400, 200))
        #expect(uniforms.isOrthographic == 1)
        #expect(uniforms.forward == SIMD3(0, 1, 0))
    }

    @Test func theGridIsCentredOnTheTargetSnappedToMajorLines() {
        var frame = ViewportFrame(pose: CameraPose(target: Vector3(123, -47, 9), distance: 100),
                                  size: ViewportSize(width: 400, height: 300),
                                  sceneBounds: nil, items: [], shading: .shadedEdges, gridSpacing: 1, handles: [],
                                  cube: ViewCubeLayout(), hoveredCubeRegion: nil, triad: TriadLayout())
        #expect(GPUGeometry.gridUniforms(frame).center == SIMD2(120, -50))
        frame.gridSpacing = 10
        #expect(GPUGeometry.gridUniforms(frame).center == SIMD2(100, 0))
        #expect(frame.sceneRadius == 1)
    }
}
