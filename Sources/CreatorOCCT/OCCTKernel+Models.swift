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
            throw KernelError.invalidInput(error.message.hasPrefix("occt: ") ? Self.unreadable(format) : error.message)
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
        let unreadable = OCCTError(message: Self.unreadable(.iges))
        guard data.count >= 73, data[data.startIndex + 72] == UInt8(ascii: "S") else { throw unreadable }
        let url = URL.temporaryDirectory.appending(path: "metalcreator-model-\(UUID().uuidString).igs")
        defer { try? FileManager.default.removeItem(at: url) }
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw unreadable
        }
        return try Self.serialized { () throws -> OCCTShape in try OCCTShape.readIGESFile(at: url) }
    }

    static func unreadable(_ format: SolidModelFormat) -> String {
        format == .iges ? "The IGES model couldn't be read." : "The STEP model couldn't be read."
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
        return try self.solid(from: result, keepingTagsOf: [solid], tag: tag, operation: "scale")
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
    func solid(from shape: OCCTShape, keepingTagsOf sources: [Solid], tag: NodeTag, operation: String) throws -> Solid {
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
        let result = try solid(from: shape, history: history, inputs: sources.map(\.topology), tag: tag, operation: operation)
        guard result.topology.faces.count == sourceFaces.count else {
            throw KernelError.operationFailed(operation: operation, reason: "its faces couldn't be matched to the originals.")
        }
        return result
    }
}
