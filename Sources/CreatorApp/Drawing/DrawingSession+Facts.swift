import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The title block's facts (plan R16, DR-5 R5, R6, R11): the parts every sheet's balloons and parts list read, the mass of an
/// assembly sheet (the kernel's volumes off the main actor, cached by solid identity, times the sheet's density) and the logo.
extension DrawingSession {
    struct FactsKey: Hashable {
        var sheet: SheetID
        var density: Double?
        var solids: [ObjectIdentifier]
        var inches: Bool
    }

    /// The facts of any sheet, not only the one shown (the export reads every sheet's).
    public func facts(for sheet: DrawingSheet) async -> TitleBlockFacts {
        var facts = TitleBlockFacts(parts: partFacts())
        if let hash = sheet.titleBlock.logo { facts.logo = await logo(forHash: hash) }
        facts.massText = await massText(of: sheet)
        return facts
    }

    /// The mass field's text for `sheet`, or nil when it stays empty.
    func massText(of sheet: DrawingSheet) async -> String? {
        guard let density = sheet.titleBlock.density, density > 0, density.isFinite, let solids = massSolids(of: sheet) else {
            return nil
        }
        let grams = await mass(of: solids, density: density)
        return grams.map { TitleBlockFacts.massText(grams: $0, inches: document.units.length == .inches) }
    }

    /// Every part the drawing wants (R5): a live Output as its name and the number of solid values it holds (nil without a result),
    /// a removed one as its remembered name ("?" with none), no quantity and `isRemoved`.
    func partFacts() -> [NodeID: PartFacts] {
        var result: [NodeID: PartFacts] = [:]
        for part in PartItems.wanted(in: editor.document) {
            let source = Self.content(of: part, in: document)
            if case .removed = source.state {
                result[part] = PartFacts(name: editor.rememberedPartNames[part] ?? "?", quantity: nil, isRemoved: true)
                continue
            }
            var quantity: Int?
            if case .ready(let solids, _, _) = source.state { quantity = solids.count }
            result[part] = PartFacts(name: source.name, quantity: quantity, isRemoved: false)
        }
        return result
    }

    /// Hands the editor the parts as they are now and notes the live names (R5); nothing here is an edit.
    func followParts() {
        let parts = partFacts()
        if editor.partFacts != parts { editor.partFacts = parts }
        editor.rememberPartNames(parts.filter { !$0.value.isRemoved }.mapValues(\.name))
    }

    /// The closed solids of the Outputs the sheet shows, when one view's Outputs hold every Output any view of the sheet shows
    /// (R6: an assembly sheet, or a sheet of one Output), each Output once and in that view's order; `nil` when an Output has no
    /// result yet or the sheet shows unrelated parts.
    func massSolids(of sheet: DrawingSheet) -> [Solid]? {
        let shown = sheet.views.reduce(into: Set<NodeID>()) { $0.formUnion($1.outputs) }
        guard !shown.isEmpty, let lead = sheet.views.first(where: { shown.isSubset(of: Set($0.outputs)) }) else { return nil }
        var seen: Set<NodeID> = []
        var closed: [Solid] = []
        for output in lead.outputs where seen.insert(output).inserted {
            guard case .ready(let solids, _, _) = Self.content(of: output, in: document).state else { return nil }
            closed += solids.filter(\.holdsClosedSolid)
        }
        return closed.isEmpty ? nil : closed
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
        followParts()
        let solids = massSolids(of: sheet)
        let key = FactsKey(
            sheet: sheet.id, density: sheet.titleBlock.density, solids: (solids ?? []).map(ObjectIdentifier.init),
            inches: document.units.length == .inches)
        if key != factsKey {
            factsKey = key
            factsTask?.cancel()
            if sheet.titleBlock.density != nil, solids != nil {
                factsTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    let text = await self.massText(of: sheet)
                    guard !Task.isCancelled, self.factsKey == key else { return }
                    self.shownMass = text
                    self.factsTask = nil
                    self.publishFacts()
                }
            } else {
                factsTask = nil
                shownMass = nil
            }
        }
        publishFacts()
    }

    /// The editor's facts for the shown sheet: the parts, the mass last measured and the logo as far as it is decoded (the rest is
    /// asked for, and lands through here).
    func publishFacts() {
        guard let sheet = editor.currentSheet.flatMap({ editor.document.sheet($0) }) else { return }
        var facts = TitleBlockFacts(massText: shownMass, parts: editor.partFacts)
        if let hash = sheet.titleBlock.logo { facts.logo = decodedLogo(forHash: hash) }
        if editor.facts != facts { editor.facts = facts }
    }

    /// Every view of the sheets (all of them without `only`) projected and every sheet's facts computed, for export: read by lookup only.
    public func projectAll(of only: [SheetID]? = nil) async -> DrawingSnapshot {
        var contents: [ViewID: ViewContent] = [:]
        var facts: [SheetID: TitleBlockFacts] = [:]
        for sheet in editor.document.sheets where only?.contains(sheet.id) ?? true {
            await projectViews(of: sheet) { contents[$0] = $1 }
            facts[sheet.id] = await self.facts(for: sheet)
        }
        return DrawingSnapshot(contents: contents, facts: facts)
    }

    /// Projects each view of `sheet`, parents first (a detail is its parent's content cut to a circle, made here without a kernel
    /// call, R14), handing each content to `store` as it lands.
    func projectViews(of sheet: DrawingSheet, store: (ViewID, ViewContent) -> Void) async {
        let projector = DrawingProjector(cache: cache, kernel: kernel)
        var made: [ViewID: ViewContent] = [:]
        for view in sheet.viewsParentsFirst {
            if Task.isCancelled { return }
            let content: ViewContent
            if case .detail(let circle)? = view.derivation {
                content = DetailClip.content(of: made[circle.parent], circle: circle)
            } else {
                content = await Self.projected(
                    projector, view: view, scale: (view.scale ?? sheet.scale).value, sources: sources(of: view),
                    previous: editor.contents[view.id])
            }
            made[view.id] = content
            store(view.id, content)
        }
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
