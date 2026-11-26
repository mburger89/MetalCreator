import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

/// The sheet's general notes above the title block (DR-4 Task 6, plan R12).
@Suite struct SheetNotesTests {
    private let iso = NumberFormat(units: .millimetres, standard: .iso, decimalSign: .point)
    private let surfaceNote = SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2)

    private func sheet(_ notes: SheetNotes, withSymbol: Bool = false) -> DrawingSheet {
        let texture = SurfaceTexture(
            requirement: SurfaceRequirement(), feature: LeaderEnd(target: .point(.zero), hint: .zero))
        return DrawingSheet(
            name: "S", size: .a4, orientation: .portrait,
            annotations: withSymbol ? [DrawingAnnotation(view: nil, kind: .surfaceTexture(texture))] : [], notes: notes)
    }

    private func picture(
        _ sheet: DrawingSheet, standard: DrawingStandard = .iso, format: NumberFormat? = nil
    ) -> SheetPicture {
        let settings = DrawingSettings(standard: standard)
        return SheetNotesLayout.picture(
            for: sheet, settings: settings,
            format: format ?? NumberFormat(units: .millimetres, standard: standard, decimalSign: .point))
    }

    private func blockTop(_ sheet: DrawingSheet, _ standard: DrawingStandard = .iso) -> (origin: Vector2, top: Double) {
        let origin = TitleBlockLayout.origin(for: sheet, standard: standard)
        return (origin, origin.y + TitleBlockLayout.height)
    }

    @Test func notesSitAboveTheTitleBlock() {
        let s = sheet(SheetNotes(lines: ["Deburr.", "Paint."]))
        let p = picture(s)
        let (origin, top) = blockTop(s)
        #expect(p.texts.map(\.original) == ["1. Deburr.", "2. Paint."])
        let pitch = AnnotationStyle.iso.linePitch * p.texts[0].height
        #expect(abs(p.texts[1].origin.y - (top + SymbolStyle.of(.iso).notesGap)) < 1e-9)
        #expect(abs(p.texts[0].origin.y - (p.texts[1].origin.y + pitch)) < 1e-9)
        #expect(p.texts.allSatisfy { $0.origin.x == origin.x })
    }

    @Test func theEdgeBreakIsTheLastNote() {
        let iso = picture(sheet(SheetNotes(lines: ["Deburr."], edgeBreak: EdgeBreak(minimum: 0.2, maximum: 0.5))))
        #expect(iso.texts.map(\.original) == ["1. Deburr.", "2. Break all sharp edges 0.2 to 0.5."])
        let equal = picture(sheet(SheetNotes(edgeBreak: EdgeBreak(minimum: 0.3, maximum: 0.3))))
        #expect(equal.texts.map(\.original) == ["1. Break all sharp edges 0.3."])
        let inches = NumberFormat(units: DocumentUnits(length: .inches, precision: 3), standard: .asme, decimalSign: .point)
        let asme = picture(
            sheet(SheetNotes(edgeBreak: EdgeBreak(minimum: 0.2032, maximum: 0.508))), standard: .asme, format: inches)
        #expect(asme.texts.map(\.original) == ["1. BREAK ALL SHARP EDGES .008-.020"])
        let asmeEqual = picture(
            sheet(SheetNotes(edgeBreak: EdgeBreak(minimum: 0.2032, maximum: 0.2032))), standard: .asme, format: inches)
        #expect(asmeEqual.texts.map(\.original) == ["1. BREAK ALL SHARP EDGES .008"])
    }

    @Test func theGeneralSurfaceStandsRightAligned() {
        let s = sheet(SheetNotes(surface: surfaceNote))
        let p = picture(s)
        let (origin, top) = blockTop(s)
        let right = origin.x + TitleBlockLayout.width
        let apexY = top + SymbolStyle.of(.iso).notesGap
        #expect(!p.strokes.isEmpty)
        let xs = p.strokes.flatMap(\.segments).flatMap { segment -> [Double] in
            if case .line(let a, let b) = segment { return [a.x, b.x] }
            return []
        }
        let textRight = p.texts.map { $0.origin.x + $0.run.width }.max() ?? 0
        #expect(abs(Swift.max(xs.max() ?? 0, textRight) - right) < 1e-9)
        #expect(p.strokes.flatMap(\.segments).contains { if case .line(let a, _) = $0 { abs(a.y - apexY) < 1e-9 } else { false } })
    }

    @Test func parenthesesFollowWhenTheSheetHasSurfaceSymbols() {
        let with = picture(sheet(SheetNotes(surface: surfaceNote), withSymbol: true))
        let open = with.texts.first { $0.original == "(" }, close = with.texts.first { $0.original == ")" }
        #expect(open != nil && close != nil)
        if let open, let close {
            #expect(open.origin.x < close.origin.x)
            // Both stand with their middle at the middle of the symbol's legs, not with their baseline on its apex.
            let (_, top) = blockTop(sheet(SheetNotes()))
            let apexY = top + SymbolStyle.of(.iso).notesGap
            let middle = apexY + SymbolStyle.of(.iso).surfaceLong * open.height / 2
            for paren in [open, close] { #expect(abs(paren.origin.y + paren.height / 2 - middle) < 1e-9) }
            let (origin, _) = blockTop(sheet(SheetNotes()))
            #expect(abs(close.origin.x + close.run.width - (origin.x + TitleBlockLayout.width)) < 1e-9)
        }
        let without = picture(sheet(SheetNotes(surface: surfaceNote)))
        #expect(!without.texts.contains { $0.original == "(" || $0.original == ")" })
    }

    @Test func notesAreOnTheTextLayer() {
        let p = picture(
            sheet(
                SheetNotes(lines: ["A"], edgeBreak: EdgeBreak(minimum: 0.2, maximum: 0.5), surface: surfaceNote),
                withSymbol: true))
        #expect(!p.texts.isEmpty && !p.strokes.isEmpty)
        #expect(p.texts.allSatisfy { $0.layer == .text } && p.strokes.allSatisfy { $0.layer == .text })
        #expect(p.fills.allSatisfy { $0.layer == .text })
    }

    @Test func emptyNotesDrawNothing() {
        let p = picture(sheet(SheetNotes()))
        #expect(p.texts.isEmpty && p.strokes.isEmpty && p.fills.isEmpty)
    }

    @Test func notesAreInTheComposedSheetAboveTheTitleBlock() {
        let s = sheet(SheetNotes(lines: ["Deburr."]))
        let document = DrawingDocument(sheets: [s])
        let composed = SheetComposer.compose(s, in: document, contents: [:], facts: TitleBlockFacts())
        #expect(composed.texts.contains { $0.original == "1. Deburr." })
    }

    // MARK: DR-5 Task 5

    private func composed(_ list: PartsList) -> (SheetPicture, DrawingSheet) {
        let part = NodeID()
        let s = DrawingSheet(
            name: "S", size: .a4, orientation: .portrait,
            views: [DrawingView(kind: .base, source: part, orientation: .standard(.top), center: .zero)],
            annotations: [DrawingAnnotation(view: nil, kind: .partsList(list))], notes: SheetNotes(lines: ["Deburr."]))
        let facts = TitleBlockFacts(parts: [part: PartFacts(name: "Plate", quantity: 1, isRemoved: false)])
        return (SheetComposer.compose(s, in: DrawingDocument(sheets: [s]), contents: [:], facts: facts), s)
    }

    @Test func notesStandAboveAStandingPartsList() {
        let (picture, s) = composed(PartsList())
        let (_, top) = blockTop(s)
        let listTop = top + PartsListLayout.height(rows: 1)
        let note = picture.texts.first { $0.original == "1. Deburr." }!
        #expect(abs(note.origin.y - (listTop + SymbolStyle.of(.iso).notesGap)) < 1e-9)
    }

    @Test func aFreePartsListLeavesTheNotesOnTheBlock() {
        let (picture, s) = composed(PartsList(bottomRight: Vector2(100, 100)))
        let (_, top) = blockTop(s)
        let note = picture.texts.first { $0.original == "1. Deburr." }!
        #expect(abs(note.origin.y - (top + SymbolStyle.of(.iso).notesGap)) < 1e-9)
    }
}
