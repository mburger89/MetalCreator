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
        let factor = units.millimetres.map { $0 / file.fileUnitMillimetres } ?? 1
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
        var outputs = NodeOutputs(lists: ["solids": solids, "sheets": sheets, "curves": curves])
        outputs.facts = [
            PayloadFact("Format", model.format == .step ? "STEP" : "IGES"),
            PayloadFact("File units", unitName(file.fileUnitMillimetres)),
            PayloadFact("Solids", file.solids.count.display),
            PayloadFact("Sheets", file.sheets.count.display),
            PayloadFact("Curves", file.curves.count.display),
        ]
        return outputs
    }

    /// The solid or sheet named for this node and scaled by `factor` (1 leaves it as it is).
    private static func placed(_ shape: Solid, factor: Double, kernel: any Kernel, context: EvalContext) async throws -> Solid {
        let named = ImportedModelTags.retargeted(shape, to: context.node.id)
        guard factor != 1 else { return named }
        return try await kernel.scaled(named, by: Vector3(factor, factor, factor), tag: context.tag)
    }

    /// The model a file holds: from the cache when its stamp is known, else read and kept.
    private static func load(_ reference: ImageReference, resolver: ImageResolver, kernel: any Kernel) async throws -> ImportedModel {
        let sentinel = NodeTag(node: ImportedModelCache.sentinel, item: 0)
        do {
            return try await ImportedModelCache.shared.model(for: resolver.stamp(of: reference)) {
                let data = try resolver.modelFileBytes(of: reference)
                let format = try format(of: data)
                do {
                    return ImportedModel(shapes: try await kernel.readShapes(data, format: format, tag: sentinel), format: format)
                } catch KernelError.invalidInput(let reason) {
                    throw ImportedModelProblem(message: reason)
                } catch KernelError.operationFailed(_, let reason) {
                    throw ImportedModelProblem(message: reason)
                }
            }
        } catch let problem as ImportedModelProblem {
            throw NodeError.invalidValue(problem.message)
        }
    }

    /// The format the bytes are: STEP begins "ISO-10303-21", IGES has the section letter "S" in column 73 of its first record.
    static func format(of data: Data) throws -> SolidModelFormat {
        if ModelFormat.step.matches(data) { return .step }
        if ModelFormat.iges.matches(data) { return .iges }
        throw ImportedModelProblem(message: "This isn't a STEP or IGES file.")
    }

    /// "mm", "in" and so on for the units a file may use, else millimetres per unit.
    static func unitName(_ millimetres: Double) -> String {
        let known: [(Double, String)] = [(1, "mm"), (10, "cm"), (1000, "m"), (25.4, "in"), (304.8, "ft")]
        if let name = known.first(where: { abs($0.0 - millimetres) < 1e-9 * $0.0 })?.1 { return name }
        return "\(millimetres.display) mm per unit"
    }
}
