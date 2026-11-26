import CreatorDrawing
import CreatorGraph
import CreatorKernel
import Foundation

/// Reading drawings and exporting them (DR-5 R19). They work in every mode; an export is refused whenever edits are. No drawing edit
/// goes through MCP (placing a dimension needs a pick).
@MainActor public enum DrawingTools {
    /// How long `get_sheet` and `export_drawing` wait for the evaluation and the sheet's projections together, as the edit tools wait.
    public static let settleLimit: Duration = .seconds(60)

    public static let exportKinds = ["pdf", "pdf_sheet", "dxf_sheet", "dxf_view", "dxf_view_annotations", "svg_sheet"]
    static let viewKinds: Set<String> = ["dxf_view", "dxf_view_annotations"]

    public static var tools: [MCPTool] { [listDrawings, getSheet, exportDrawing] }

    private static func schema(_ properties: [String: JSONValue] = [:], required: [String] = []) -> JSONValue {
        var fields: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { fields["required"] = .array(required.map { .string($0) }) }
        return .object(fields)
    }

    private static func property(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    // MARK: list_drawings

    private static let listDrawings = MCPTool(
        name: "list_drawings",
        description: "Lists the drawing's sheets with their views, the parts each view shows and how many annotations each sheet holds.",
        inputSchema: schema()
    ) { _, session, _ in
        .ok(listJSON(session))
    }

    static func listJSON(_ session: any DocumentSession) -> JSONValue {
        let graph = session.content.graph
        let document = graph.drawings
        let remembered = session.rememberedPartNames
        let standard = document.settings.standard
        let sheets = document.sheets.map { sheet -> JSONValue in
            let views = sheet.views.map { view -> JSONValue in
                var fields: [String: JSONValue] = [
                    "id": .string(view.id.rawValue.uuidString),
                    "kind": .string(view.kind.rawValue),
                    "orientation": .string(orientationName(view.orientation)),
                    "scale": .string((view.scale ?? sheet.scale).text(for: standard)),
                    "parts": .array(view.outputs.map { part in
                        let name = graph.nodes[part]?.name ?? remembered[part]
                            ?? document.partNames.first { $0.part == part }?.name ?? "?"
                        return .object(["node": .string(part.rawValue.uuidString), "name": .string(name)])
                    }),
                ]
                if let letter = view.letter { fields["letter"] = .string(letter) }
                return .object(fields)
            }
            return .object([
                "id": .string(sheet.id.rawValue.uuidString),
                "name": .string(sheet.name),
                "size": .string(sheet.size.title),
                "orientation": .string(sheet.orientation.rawValue),
                "scale": .string(sheet.scale.text(for: standard)),
                "revision": .string(sheet.revisionShown),
                "views": .array(views),
                "annotations": .int(sheet.annotations.count),
            ])
        }
        return .object(["standard": .string(standard.rawValue), "sheets": .array(sheets)])
    }

    private static func orientationName(_ orientation: ViewOrientation) -> String {
        switch orientation {
        case .standard(let named): named.title
        case .custom: "custom"
        }
    }

    // MARK: get_sheet

    private static let getSheet = MCPTool(
        name: "get_sheet",
        description: "Reads one sheet as it would be exported: each view's status, each annotation's label and whether it still holds "
            + "what it measures, the numbered parts and the revisions. A view still being drawn is reported pending, and a view "
            + "that failed says why; either makes complete false.",
        inputSchema: schema(["sheet": property("string", "The sheet's ID or unique name.")], required: ["sheet"])
    ) { arguments, session, _ in
        let document = session.content.graph.drawings
        switch DrawingAddressing.sheet(arguments["sheet"], in: document) {
        case .failure(let refusal): return .refused(refusal.sentence)
        case .success(let id):
            guard let snapshot = await session.drawingSheet(id) else { return .refused("Drawings can't be read from this session.") }
            // The sheet may have changed during the wait: read the one the session has now.
            guard let sheet = session.content.graph.drawings.sheet(id) else { return .refused("That sheet no longer exists.") }
            return .ok(sheetJSON(sheet, snapshot: snapshot, document: session.content.graph.drawings))
        }
    }

    static func sheetJSON(_ sheet: DrawingSheet, snapshot: DrawingSheetSnapshot, document: DrawingDocument) -> JSONValue {
        var complete = true
        let views = sheet.views.map { view -> JSONValue in
            var fields: [String: JSONValue] = ["id": .string(view.id.rawValue.uuidString)]
            switch snapshot.views[view.id] ?? .pending {
            case .drawn: fields["status"] = .string("drawn")
            case .pending:
                complete = false
                fields["status"] = .string("pending")
            case .failed(let problem):
                complete = false
                fields["status"] = .string("failed")
                fields["problem"] = .string(problem)
            }
            return .object(fields)
        }
        let annotations = sheet.annotations.map { annotationJSON($0, report: snapshot.picture.annotationReports[$0.id]) }
        let names = PartItems.names(of: snapshot.facts.parts)
        let items = PartItems.numbered(document, names: names).map { item -> JSONValue in
            let facts = snapshot.facts.parts[item.part]
            return .object([
                "item": .int(item.number),
                "name": .string(facts?.name ?? "?"),
                "quantity": facts?.quantity.map { JSONValue.int($0) } ?? .null,
                "material": .string(item.material),
                "part_number": .string(item.partNumber),
            ])
        }
        let revisions = (sheet.revisionTable?.table.rows ?? []).map { row -> JSONValue in
            .object([
                "letter": .string(row.letter), "description": .string(row.description),
                "date": .string(row.date), "approved": .string(row.approved),
            ])
        }
        return .object([
            "sheet": .object(["id": .string(sheet.id.rawValue.uuidString), "name": .string(sheet.name)]),
            "complete": .bool(complete),
            "views": .array(views),
            "annotations": .array(annotations),
            "parts_list": .array(items),
            "revisions": .array(revisions),
        ])
    }

    private static func annotationJSON(_ annotation: DrawingAnnotation, report: AnnotationReport?) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(annotation.id.rawValue.uuidString),
            "kind": .string(kindName(annotation.kind)),
            "label": .string(report?.label ?? ""),
            "status": .string("held"),
        ]
        if let view = annotation.view { fields["view"] = .string(view.rawValue.uuidString) }
        if let report {
            if case .lost(let reason) = report.status {
                fields["status"] = .string("lost")
                fields["reason"] = .string(reason.sentence)
            }
            if !report.warnings.isEmpty { fields["warnings"] = .array(report.warnings.map { .string($0) }) }
        }
        return .object(fields)
    }

    // The `type` the annotation is coded with in the file (one case per kind, so the switch is as long as the list).
    // swiftlint:disable:next cyclomatic_complexity
    private static func kindName(_ kind: AnnotationKind) -> String {
        switch kind {
        case .dimension: "dimension"
        case .holeCallout: "holeCallout"
        case .centreMark: "centreMark"
        case .centreLine: "centreLine"
        case .note: "note"
        case .datumFeature: "datumFeature"
        case .featureControl: "featureControl"
        case .surfaceTexture: "surfaceTexture"
        case .balloon: "balloon"
        case .partsList: "partsList"
        case .revisionTable: "revisionTable"
        }
    }

    // MARK: export_drawing

    private static let exportDrawing = MCPTool(
        name: "export_drawing",
        description: "Exports the drawing as pdf (every sheet), pdf_sheet, dxf_sheet or svg_sheet (one sheet), or dxf_view or "
            + "dxf_view_annotations (one view at 1:1). An existing file is only replaced when overwrite is true.",
        inputSchema: schema(
            [
                "kind": .object(["type": .string("string"), "enum": .array(exportKinds.map { .string($0) })]),
                "path": property("string", "An absolute path."),
                "sheet": property("string", "The sheet's ID or unique name; needed for every kind but pdf."),
                "view": property("string", "The view's ID; needed for dxf_view and dxf_view_annotations."),
                "overwrite": property("boolean", "True to replace an existing file."),
            ],
            required: ["kind", "path"]
        )
    ) { arguments, session, _ in
        guard let kind = arguments["kind"]?.string, exportKinds.contains(kind) else {
            return .refused("Drawing export kinds are pdf, pdf_sheet, dxf_sheet, dxf_view, dxf_view_annotations and svg_sheet.")
        }
        let document = session.content.graph.drawings
        var sheetID: SheetID?
        var viewID: ViewID?
        let needsSheet = kind != "pdf"
        if needsSheet || arguments["sheet"] != nil {
            if needsSheet, arguments["sheet"]?.string?.isEmpty ?? true { return .refused("Say which sheet to export.") }
            switch DrawingAddressing.sheet(arguments["sheet"], in: document) {
            case .failure(let refusal): return .refused(refusal.sentence)
            case .success(let id): sheetID = id
            }
        }
        if viewKinds.contains(kind) {
            guard let sheetID, let sheet = document.sheet(sheetID) else { return .refused("Say which sheet to export.") }
            if arguments["view"]?.string?.isEmpty ?? true { return .refused("Say which view to export.") }
            switch DrawingAddressing.view(arguments["view"], on: sheet) {
            case .failure(let refusal): return .refused(refusal.sentence)
            case .success(let id): viewID = id
            }
        }
        guard let path = arguments["path"]?.string, !path.isEmpty else { return .refused("Say which file, by its absolute path.") }
        guard AbsolutePath.isAbsolute(path) else { return .refused(AbsolutePath.refusal) }
        let outcome = await session.exportDrawing(
            kind, sheet: sheetID, view: viewID, to: URL(fileURLWithPath: path), overwrite: arguments["overwrite"]?.bool ?? false)
        switch outcome {
        case .refused(let sentence): return .refused(sentence)
        case .done(let message):
            var fields: [String: JSONValue] = ["done": .bool(true)]
            if let message { fields["message"] = .string(message) }
            return .ok(.object(fields))
        }
    }
}
