import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation

/// The solids, sheets and curves of a STEP or IGES file (NURBS spec, Import Model). The file is the node's `NodeSetting.modelFile`,
/// embedded or linked; its format is told by its bytes, not its name. The read is kept by `ImportedModelCache`, so moving or scaling
/// the result never reads the file again, and a file saved elsewhere changes its stamp and is read at the next evaluation. Solids
/// come out of `solids`, free shells and faces out of `sheets` (their free edges named `.boundary(.imported(edge: i))`) and free
/// wires and edges out of `curves`. The file's own length unit is applied by the reader, so with units "From file" the geometry is
/// in millimetres as the file meant it; an explicit unit says what the file's numbers are in instead.
public enum ImportModelNode: NodeDefinition {
    public static let typeID = "creator.importModel"
    public static let displayName = "Import Model"
    public static let category = NodeCategory.solid
    public static let factsTitle = "Model"
    public static let inputs = [
        SocketSpec("units", .integer, defaultValue: .integer(ImportUnits.fromFile.rawValue)),
    ]
    public static let outputs = [
        SocketSpec("solids", .solid),
        SocketSpec("sheets", .solid),
        SocketSpec("curves", .curve),
    ]
    public static let inspector = [
        InspectorSection(title: "File", controls: [.modelFile(NodeSetting.modelFile)]),
        InspectorSection(title: "Units", controls: [.segmented("units", options: ImportUnits.options)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard let reference = context.node.inputValues[NodeSetting.modelFile]?.fileReference else { throw ModelImportProblem.notChosen }
        guard let units = ImportUnits(rawValue: try inputs.integer("units")) else {
            throw NodeError.invalidValue("“units” must be From file, mm, cm, m or in.")
        }
        let model = try await load(reference, resolver: context.images, kernel: kernel)
        let file = model.shapes
        let (factor, warning) = try unitFactor(units, fileUnit: file.fileUnitMillimetres)
        let warnings = warning.map { [$0] } ?? []
        guard factor.isFinite, factor > 0 else { throw NodeError.invalidValue("The model's unit can't be used.") }

        var solids: [Scalar] = [], sheets: [Scalar] = [], curves: [Scalar] = []
        for solid in file.solids {
            solids.append(.solid(try await placed(solid, factor: factor, kernel: kernel, context: context)))
        }
        for sheet in file.sheets {
            sheets.append(.solid(try await placed(sheet, factor: factor, kernel: kernel, context: context)))
        }
        for curve in file.curves {
            curves.append(.curve(factor == 1 ? curve : try await kernel.scaled(curve, by: factor, tag: context.tag)))
        }
        var outputs = NodeOutputs(lists: ["solids": solids, "sheets": sheets, "curves": curves], warnings: warnings)
        outputs.facts = [
            PayloadFact("Format", model.format == .step ? "STEP" : "IGES"),
            PayloadFact("File units", file.fileUnitMillimetres > 0 ? unitName(file.fileUnitMillimetres) : "Unknown"),
            PayloadFact("Solids", file.solids.count.display),
            PayloadFact("Sheets", file.sheets.count.display),
            PayloadFact("Curves", file.curves.count.display),
            PayloadFact("Picks", "Last until the file changes."),
        ]
        return outputs
    }

    /// The solid or sheet named for this node and scaled by `factor` (1 leaves it as it is).
    private static func placed(_ shape: Solid, factor: Double, kernel: any Kernel, context: EvalContext) async throws -> Solid {
        let named = ImportedModelTags.retargeted(shape, to: context.node.id, item: context.tag.item)
        guard factor != 1 else { return named }
        return try await kernel.scaled(named, by: Vector3(factor, factor, factor), tag: context.tag)
    }

    /// The model a file holds: from the cache when its stamp is known, else read and kept.
    private static func load(_ reference: ImageReference, resolver: ImageResolver, kernel: any Kernel) async throws -> ImportedModel {
        let sentinel = NodeTag(node: ImportedModelCache.sentinel, item: 0)
        do {
            return try await ImportedModelCache.shared.model(for: resolver.stamp(of: reference)) {
                let (data, format) = try bytesAndFormat(of: try resolver.modelFileBytes(of: reference))
                do {
                    return ImportedModel(shapes: try await kernel.readShapes(data, format: format, tag: sentinel), format: format)
                } catch KernelError.invalidInput(let reason) {
                    throw ImportedModelProblem(message: reason)
                } catch KernelError.operationFailed(_, let reason) {
                    // Not remembered: an out-of-memory or other kernel failure says nothing lasting about the file.
                    throw NodeError.invalidValue(reason)
                }
            }
        } catch let problem as ImportedModelProblem {
            throw NodeError.invalidValue(problem.message)
        }
    }

    /// The scale an explicit unit asks for on a file in `fileUnit` millimetres per unit (0: the file names none), with the warning when
    /// "From file" is chosen for such a file; an explicit unit for it is refused.
    static func unitFactor(_ units: ImportUnits, fileUnit: Double) throws -> (factor: Double, warning: String?) {
        guard let explicit = units.millimetres else { return (1, fileUnit > 0 ? nil : unknownUnit) }
        guard fileUnit > 0 else { throw NodeError.invalidValue(unknownUnit) }
        return (explicit / fileUnit, nil)
    }

    private static let unknownUnit = "The file's length unit isn't known; explicit units can't be applied."

    /// The bytes without a UTF-8 byte order mark, and the format they are: STEP begins "ISO-10303-21", IGES has the section letter
    /// "S" in column 73 of its first record. A gzip file is refused in words.
    static func bytesAndFormat(of data: Data) throws -> (Data, SolidModelFormat) {
        if data.starts(with: [0x1F, 0x8B]) {
            throw ImportedModelProblem(message: "Compressed STEP files can't be read; unzip it first.")
        }
        let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        if ModelFormat.step.matches(bytes) { return (bytes, .step) }
        if ModelFormat.iges.matches(bytes) { return (bytes, .iges) }
        throw ImportedModelProblem(message: "This isn't a STEP or IGES file.")
    }

    /// "mm", "in" and so on for the units a file may use, else millimetres per unit.
    static func unitName(_ millimetres: Double) -> String {
        let known: [(Double, String)] = [(1, "mm"), (10, "cm"), (1000, "m"), (25.4, "in"), (304.8, "ft")]
        if let name = known.first(where: { abs($0.0 - millimetres) < 1e-9 * $0.0 })?.1 { return name }
        return "\(millimetres.display) mm per unit"
    }
}
