import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// What the three lattice nodes share about their `mapping` (implicit spec §3.5): the sockets, the inspector's section (only the
/// active mapping's inputs show), and building the mapping from the region with its warnings.
enum LatticeMappingSetup {
    static let mappingSocket = SocketSpec("mapping", .integer, defaultValue: .integer(LatticeMappingKind.straight.rawValue))
    /// The cylindrical axis: this plane's normal through its origin. Unset, the world Z axis through the origin.
    static let axisSocket = SocketSpec("axis", .plane, defaultValue: .plane(.xy))
    /// The spherical centre. Unset, the origin.
    static let centreSocket = SocketSpec("centre", .vector, defaultValue: .vector(.zero))

    /// The three sockets, in the order they follow the other settings.
    static let sockets = [mappingSocket, axisSocket, centreSocket]

    // MARK: Inspector

    /// `base` and the Mapping section for a node set to `kind`: the segmented control, the inputs of that mapping only, and its help.
    static func inspector(base: [InspectorSection], kind: LatticeMappingKind) -> [InspectorSection] {
        var controls: [InspectorControl] = [.segmented("mapping", options: LatticeMappingKind.options)]
        switch kind {
        case .straight: break
        case .cylindrical: controls.append(.planePicker("axis"))
        case .spherical: controls.append(.vector("centre"))
        case .face: controls += [.faceStatus(NodeSetting.face), .button(title: "Pick Face in View…", action: .pickFacesInView)]
        }
        controls.append(.note(kind.help))
        return base + [InspectorSection(title: "Mapping", controls: controls)]
    }

    /// The mapping a node is set to; Straight when it has none stored (a file from before 7c-4) or a value that is not one.
    static func kind(of node: Node) -> LatticeMappingKind {
        if case .integer(let stored)? = node.inputValues["mapping"], let kind = LatticeMappingKind(rawValue: stored) { return kind }
        return .straight
    }

    // MARK: Building

    /// A mapping and what it earns the node in warnings.
    struct Built {
        var mapping: LatticeMapping
        var warnings: [String]
    }

    /// The mapping the inputs choose, for a lattice filling `region`.
    /// - Parameter cells: the lattice's cells, which a turn is rounded to a whole number of; `nil` for a lattice without cells
    ///   (Voronoi), whose seeds are copied across the cut instead.
    static func make(_ inputs: NodeInputs, region: ImplicitSolid, cells: LatticeCells?, kernel: any Kernel,
                     context: EvalContext) async throws -> Built {
        let kind = LatticeMappingKind(rawValue: try inputs.choice("mapping", options: LatticeMappingKind.options)) ?? .straight
        let box = region.bounds
        let cell = cells.map { $0.nominalSize * $0.stretch.x }
        let mapping: LatticeMapping
        switch kind {
        case .straight:
            return Built(mapping: .straight, warnings: [])
        case .cylindrical:
            let plane = try inputs.plane("axis")
            guard let frame = RigidMove(plane: plane) else { throw NodeError.invalidValue("“axis” has no usable direction.") }
            let mean = LatticeMapping.meanRadius(of: region) { point in
                let offset = point - frame.origin
                return (offset - frame.zAxis * offset.dot(frame.zAxis)).length
            }
            let radius = LatticeMapping.turnRadius(mean: mean, cell: cell)
            guard let map = CylindricalMap(axis: plane, radius: radius, over: box) else {
                throw NodeError.invalidValue("“axis” has no usable direction.")
            }
            mapping = .cylindrical(map)
        case .spherical:
            let centre = try inputs.vector("centre")
            guard centre.isFinite else { throw NodeError.invalidValue("“centre” isn't a finite position.") }
            let mean = LatticeMapping.meanRadius(of: region) { ($0 - centre).length }
            guard let map = SphericalMap(centre: centre, radius: LatticeMapping.turnRadius(mean: mean, cell: cell), over: box) else {
                throw NodeError.invalidValue("“centre” isn't a finite position.")
            }
            mapping = .spherical(map)
        case .face:
            let face = try await LatticeFaceMapping.make(context: context, region: region, cells: cells, kernel: kernel)
            return Built(mapping: .face(face.map), warnings: face.warnings + warnings(for: .face(face.map), region: region, cells: cells))
        }
        return Built(mapping: mapping, warnings: warnings(for: mapping, region: region, cells: cells))
    }

    /// The warnings a mapping earns on `region`.
    static func warnings(for mapping: LatticeMapping, region: ImplicitSolid, cells: LatticeCells?) -> [String] {
        var warnings: [String] = []
        let box = region.bounds
        if let noun = mapping.singularNoun {
            let near = region.signedDistances(at: mapping.singularSamples(in: box)).contains { $0 < LatticeMapping.exclusion }
            if near { warnings.append("The mapping is singular near \(noun); cells there are left solid.") }
        }
        if let cells, cells.size.slope > 0, mapping.periods.first != nil,
           region.signedDistances(at: mapping.cutSamples(in: box)).contains(where: { $0 < 0 }) {
            warnings.append("The cell size is graded, so cells may not meet where the angle wraps round.")
        }
        if mapping.stretch >= slowStretch {
            let stretch = mapping.stretch.formatted(.number.precision(.fractionLength(0)).locale(.messages))
            warnings.append("The mapping stretches the cells up to \(stretch) times in this region; the preview may be slow.")
        }
        return warnings
    }

    /// From this stretch the lipschitz bound is large enough to slow the sparse evaluation noticeably.
    static let slowStretch = 10.0
}
