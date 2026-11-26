import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The title block's mass (plan R16): the volume of the Output's closed solids, from the kernel off the main actor and cached by
/// solid identity, times the sheet's density.
extension DrawingSession {
    struct FactsKey: Hashable {
        var sheet: SheetID
        var density: Double?
        var solids: [ObjectIdentifier]
        var inches: Bool
    }

    /// The facts of any sheet, not only the one shown (the export reads every sheet's).
    public func facts(for sheet: DrawingSheet) async -> TitleBlockFacts {
        guard let density = sheet.titleBlock.density, density > 0, density.isFinite, let solids = massSolids(of: sheet) else {
            return TitleBlockFacts()
        }
        let grams = await mass(of: solids, density: density)
        return TitleBlockFacts(
            massText: grams.map { TitleBlockFacts.massText(grams: $0, inches: document.units.length == .inches) })
    }

    /// The closed solids the sheet's views show, when they all show one Output with a result.
    func massSolids(of sheet: DrawingSheet) -> [Solid]? {
        let sources = Set(sheet.views.map(\.source))
        guard sources.count == 1, let source = sources.first,
              case .ready(let solids, _, _) = Self.content(of: source, in: document).state else { return nil }
        return Self.closedSolids(in: solids)
    }

    /// The values that hold a closed solid, or `nil`. A value that holds a sheet as well counts: the kernel's properties report only
    /// its solids' volume (NS-5 R17).
    static func closedSolids(in solids: [Solid]) -> [Solid]? {
        let closed = solids.filter(\.holdsClosedSolid)
        return closed.isEmpty ? nil : closed
    }

    private func mass(of solids: [Solid], density: Double) async -> Double? {
        // Read into a local first: another call may trim the cache while this one awaits the kernel.
        var known: [ObjectIdentifier: Double?] = [:]
        for solid in solids { known[ObjectIdentifier(solid)] = volumes[ObjectIdentifier(solid)]?.volume }
        let missing = solids.filter { volumes[ObjectIdentifier($0)] == nil }
        if !missing.isEmpty {
            let measured = await Self.measure(missing, with: kernel)
            // A cancelled task's measurements are failures of the cancellation, not of the solid: never remember them.
            if Task.isCancelled { return nil }
            for (solid, volume) in measured {
                volumes[ObjectIdentifier(solid)] = (solid, volume)
                known[ObjectIdentifier(solid)] = volume
            }
        }
        // Keep only what is asked for now: an entry holds its solid alive, so an old one would pin a whole OCCT shape.
        let asked = Set(solids.map(ObjectIdentifier.init))
        volumes = volumes.filter { asked.contains($0.key) }
        var total = 0.0
        for solid in solids {
            guard let entry = known[ObjectIdentifier(solid)], let volume = entry else { return nil }
            total += volume
        }
        return total * density / 1000
    }

    /// The kernel's volumes (mm³); the kernel is an actor, so this is off the main actor. `nil` for a solid it can't measure.
    private static func measure(_ solids: [Solid], with kernel: any Kernel) async -> [(Solid, Double?)] {
        var measured: [(Solid, Double?)] = []
        for solid in solids {
            let volume = try? await kernel.properties(of: solid).volume
            measured.append((solid, volume))
        }
        return measured
    }

    func followFacts(of sheet: DrawingSheet) {
        let solids = massSolids(of: sheet)
        let key = FactsKey(
            sheet: sheet.id, density: sheet.titleBlock.density, solids: (solids ?? []).map(ObjectIdentifier.init),
            inches: document.units.length == .inches)
        guard key != factsKey else { return }
        factsKey = key
        factsTask?.cancel()
        guard sheet.titleBlock.density != nil, solids != nil else {
            factsTask = nil
            if editor.facts != TitleBlockFacts() { editor.facts = TitleBlockFacts() }
            return
        }
        factsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let facts = await self.facts(for: sheet)
            guard !Task.isCancelled, self.factsKey == key else { return }
            self.editor.facts = facts
            self.factsTask = nil
        }
    }

    /// Every view of every sheet projected and every sheet's facts computed, for export: read by lookup only.
    public func projectAll() async -> DrawingSnapshot {
        var contents: [ViewID: ViewContent] = [:]
        var facts: [SheetID: TitleBlockFacts] = [:]
        let projector = DrawingProjector(cache: cache, kernel: kernel)
        let drawings = editor.document
        for sheet in drawings.sheets {
            // Parents first: a detail is its parent's content cut to a circle, made here without a kernel call (R14).
            for view in sheet.viewsParentsFirst {
                if case .detail(let circle)? = view.derivation {
                    contents[view.id] = DetailClip.content(of: contents[circle.parent], circle: circle)
                    continue
                }
                let scale = (view.scale ?? sheet.scale).value
                let source = Self.content(of: view.source, in: document)
                contents[view.id] = await projector.content(
                    for: view, scale: scale, source: source, previous: editor.contents[view.id])
            }
            facts[sheet.id] = await self.facts(for: sheet)
        }
        return DrawingSnapshot(contents: contents, facts: facts)
    }
}

/// What an export reads: every view's content and every sheet's title-block facts, looked up by ID.
public struct DrawingSnapshot: Sendable {
    public var contents: [ViewID: ViewContent]
    public var facts: [SheetID: TitleBlockFacts]

    public init(contents: [ViewID: ViewContent] = [:], facts: [SheetID: TitleBlockFacts] = [:]) {
        self.contents = contents
        self.facts = facts
    }
}
