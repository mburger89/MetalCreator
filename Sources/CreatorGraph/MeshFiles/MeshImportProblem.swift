import CreatorKernel
import Foundation

/// Why a mesh file could not be used (mesh import spec, Reading and Limits), in the plain sentences a node's error and the app's
/// alerts show. Every way a file can be wrong has a case here and none of them is a crash.
public enum MeshImportProblem: Error, Equatable, Sendable {
    /// An Import Mesh node with no file chosen.
    case notChosen
    /// Not an STL or a 3MF.
    case notAMeshFile
    /// A binary STL that holds fewer triangles than its header says, or an ASCII one that stops inside a facet.
    case endsEarly
    /// A number in an ASCII STL that is not a finite number, or a vertex with too few of them; the line is 1-based.
    case badNumber(line: Int)
    /// A file with no usable triangle.
    case noTriangles
    /// More triangles than `MeshImportLimits.maxTriangles`.
    case tooManyTriangles(Int)
    /// More bytes than `MeshImportLimits.maxFileBytes`.
    case tooLarge
    /// Coordinates that overflow once the file's units are applied.
    case coordinatesOverflow
    /// A linked path that exists but is not a file (a folder, a device, a pipe).
    case notAFile(name: String)
    /// A linked file that exists but could not be read.
    case unreadable(name: String, reason: String)
    /// A linked file that is not where the document says.
    case missing(name: String, folder: String)
    /// An embedded file whose bytes the document does not hold (a damaged file).
    case embeddedMissing

    public var message: String {
        switch self {
        case .notChosen:
            "Choose a mesh file."
        case .notAMeshFile:
            "This file isn't an STL or 3MF."
        case .endsEarly:
            "The STL ends early."
        case .badNumber(let line):
            "The STL has a bad number on line \(line.formatted(.number.locale(.messages)))."
        case .noTriangles:
            "This file holds no triangles."
        case .tooManyTriangles(let count):
            "This file has \(count.formatted(.number.locale(.messages))) triangles; Import Mesh takes at most "
                + "\(MeshImportLimits.maxTriangles.formatted(.number.locale(.messages)))."
        case .tooLarge:
            "This file is larger than the 1 GB limit."
        case .coordinatesOverflow:
            "This file's coordinates are too large at these units."
        case .notAFile(let name):
            "File '\(name)' isn't a file."
        case .unreadable(let name, let reason):
            "File '\(name)' couldn't be read: \(reason)"
        case .missing(let name, let folder):
            "File '\(name)' wasn't found at \(folder). Relink it in the inspector."
        case .embeddedMissing:
            "This embedded file's data is missing from the document, or damaged. Choose the file again in the inspector."
        }
    }
}
