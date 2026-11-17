import CreatorGeometry
import CreatorKernel
import Foundation

/// Reading solid models, scaling and compounds (KiCad import, KI-2).
extension OCCTKernel {
    public func readModel(_ data: Data, format: SolidModelFormat, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        let shape: OCCTShape
        do {
            switch format {
            case .step:
                shape = try Self.serialized { () throws -> OCCTShape in try OCCTShape.readSTEPModel(data) }
            case .iges:
                shape = try readIGES(data)
            }
        } catch let error as OCCTError {
            // The shim's own sentences are about the file; any other exception (bad_alloc too) says nothing about its contents.
            if error.message.hasPrefix("occt: ") {
                throw KernelError.operationFailed(operation: "read model", reason: Self.unreadable(format))
            }
            throw KernelError.invalidInput(error.message)
        }
        let read: Solid
        do {
            read = try solid(from: shape, history: [], inputs: [], tag: tag, operation: "read model")
        } catch KernelError.operationFailed {
            throw KernelError.invalidInput("The model contains no shapes.")
        }
        var topology = read.topology
        for index in topology.faces.indices {
            topology.faces[index].tags = [TopoTag(tag, .imported(face: index))]
        }
        return Solid(topology: topology, bounds: read.bounds, storage: read.storage)
    }

    /// OpenCascade 7.9 reads IGES from a file only (`ReadStream` fails on every IGES file), so the bytes go through a uniquely named
    /// file, written before the kernel lock is taken (mode 0600 where the platform has modes) and removed on every path. An IGES file
    /// is 80-column records ending in a section letter, "S" for the first: anything else is refused here, since OpenCascade reads
    /// text with no entities as an empty model.
    private func readIGES(_ data: Data) throws -> OCCTShape {
        let url = try Self.igesFile(for: data)
        defer { try? FileManager.default.removeItem(at: url) }
        return try Self.serialized { () throws -> OCCTShape in try OCCTShape.readIGESFile(at: url) }
    }

    /// The temporary file holding `data` as an IGES model, which the caller removes.
    static func igesFile(for data: Data) throws -> URL {
        let unreadable = OCCTError(message: Self.unreadable(.iges))
        guard data.count >= 73, data[data.startIndex + 72] == UInt8(ascii: "S") else { throw unreadable }
        let url = URL.temporaryDirectory.appending(path: "metalcreator-model-\(UUID().uuidString).igs")
        // Mode 0600 where the platform has modes; a platform without them (Windows) is tried again with none.
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
            || FileManager.default.createFile(atPath: url.path, contents: data) else {
            throw unreadable
        }
        return url
    }

    static func unreadable(_ format: SolidModelFormat) -> String {
        format == .iges ? "The IGES model couldn't be read." : "The STEP model couldn't be read."
    }

    public func readShapes(_ data: Data, format: SolidModelFormat, tag: NodeTag) throws -> ImportedShapes {
        try Task.checkCancellation()
        let read: (shapes: [(shape: OCCTShape, kind: Int)], unit: Double)
        do {
            switch format {
            case .step:
                read = try Self.serialized { () throws -> (shapes: [(shape: OCCTShape, kind: Int)], unit: Double) in
                    try OCCTShape.readShapes(data, igesURL: nil)
                }
            case .iges:
                let url = try Self.igesFile(for: data)
                defer { try? FileManager.default.removeItem(at: url) }
                read = try Self.serialized { () throws -> (shapes: [(shape: OCCTShape, kind: Int)], unit: Double) in
                    try OCCTShape.readShapes(data, igesURL: url)
                }
            }
        } catch let error as OCCTError {
            // The shim's own sentences are about the file; any other exception (bad_alloc too) says nothing about its contents.
            if error.message.hasPrefix("occt: ") {
                throw KernelError.operationFailed(operation: "read model", reason: Self.unreadable(format))
            }
            throw KernelError.invalidInput(error.message)
        }
        var shapes = ImportedShapes(fileUnitMillimetres: read.unit)
        for (shape, kind) in read.shapes {
            try Task.checkCancellation()
            switch kind {
            case 0: shapes.solids.append(try importedSolid(shape, tag: tag, isSheet: false))
            case 1: shapes.sheets.append(try importedSolid(shape, tag: tag, isSheet: true))
            default: shapes.curves.append(try curve(from: shape, operation: "read model"))
            }
        }
        return shapes
    }

    /// A solid or sheet read from a file: its faces named `.imported(face: i)` in the shape's face order and, for a sheet, its free edges
    /// `.boundary(.imported(edge: i))` in the shape's edge order.
    private func importedSolid(_ shape: OCCTShape, tag: NodeTag, isSheet: Bool) throws -> Solid {
        let read = try solid(from: shape, history: [], inputs: [], tag: tag, operation: "read model")
        var topology = read.topology
        for index in topology.faces.indices {
            topology.faces[index].tags = [TopoTag(tag, .imported(face: index))]
        }
        if isSheet {
            for index in topology.edges.indices where topology.edges[index].isBoundary {
                topology.edges[index].tags = [TopoTag(tag, .boundary(.imported(edge: index)))]
            }
        }
        return Solid(topology: topology, bounds: read.bounds, storage: read.storage)
    }

    public func scaled(_ curve: Curve, by factor: Double, tag: NodeTag) throws -> Curve {
        try Task.checkCancellation()
        guard factor.isFinite, factor > 0 else { throw KernelError.invalidInput("The scale must be greater than 0.") }
        let source = try curveShape(of: curve)
        let result: OCCTShape
        do {
            result = try Self.serialized { () throws -> OCCTShape in try source.scaled(by: Vector3(factor, factor, factor)) }
        } catch let error as OCCTError {
            throw KernelError.occt("scale", error)
        }
        return try self.curve(from: result, operation: "scale")
    }

    public func scaled(_ solid: Solid, by factors: Vector3, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard [factors.x, factors.y, factors.z].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw KernelError.invalidInput("The scale must be greater than 0.")
        }
        let source = try shape(of: solid)
        let result: OCCTShape
        do {
            result = try Self.serialized { () throws -> OCCTShape in try source.scaled(by: factors) }
        } catch let error as OCCTError {
            throw KernelError.occt("scale", error)
        }
        return try self.solid(from: result, keepingTagsOf: [solid], tag: tag, operation: "scale", carriesEdgeTags: true)
    }

    /// One solid holding all of `solids`, every tag kept. Inputs that share geometry at the same location (the same solid twice) are
    /// refused, because OpenCascade's face map would hold each shared face once and the tags could not be matched.
    public func compound(_ solids: [Solid], tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard !solids.isEmpty else { throw KernelError.invalidInput("There is nothing to combine.") }
        let shapes = try solids.map { try shape(of: $0) }
        let result: OCCTShape
        do {
            result = try Self.serialized { () throws -> OCCTShape in try OCCTShape.compound(shapes) }
        } catch let error as OCCTError {
            throw KernelError.occt("compound", error)
        }
        return try solid(from: result, keepingTagsOf: solids, tag: tag, operation: "compound")
    }

    /// A solid made from `shape` whose faces, in the shape's face map order, carry the tags of `sources`' faces in order (the
    /// operations that move or join shapes without renaming a face). A shape with another face count is refused rather than guessed at.
    func solid(from shape: OCCTShape, keepingTagsOf sources: [Solid], tag: NodeTag, operation: String,
               carriesEdgeTags: Bool = false) throws -> Solid {
        let sourceFaces = sources.flatMap(\.topology.faces)
        let history = sourceFaces.indices.map { index -> OCCTHistoryRecord in
            var position = index
            var operand = 0
            while position >= sources[operand].topology.faces.count {
                position -= sources[operand].topology.faces.count
                operand += 1
            }
            return OCCTHistoryRecord(outFace: index, kind: .face, operand: operand, index: position)
        }
        let result = try solid(from: shape, history: history, inputs: sources.map(\.topology), tag: tag, operation: operation,
                               carriesEdgeTags: carriesEdgeTags)
        guard result.topology.faces.count == sourceFaces.count else {
            throw KernelError.operationFailed(operation: operation, reason: "its faces couldn't be matched to the originals.")
        }
        return result
    }
}
