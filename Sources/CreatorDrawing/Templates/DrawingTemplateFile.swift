import Foundation

/// What a template file may be (DR-5 R10).
public enum DrawingTemplateLimits {
    /// 3 MiB: a 2 MiB logo's base64 is 2,796,203 bytes, plus the JSON around it.
    public static let maximumFileBytes = 3_145_728
}

/// Why a template could not be read, saved or deleted. `message` is a full sentence part: for a file that was skipped it is the part
/// after "was skipped:"; for a save or delete it is the whole sentence.
public struct DrawingTemplateProblem: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// The `.mctemplate` file: JSON with sorted keys (`version` 1, `name`, `size`, `orientation`, `standard`, `titleBlock`, `logo` as
/// base64). The file's name, not its content, is the template's id. A template file is untrusted input.
public enum DrawingTemplateFile {
    public static let version = 1

    private struct Version: Decodable { var version: Int }

    private struct Body: Codable {
        var version: Int
        var name: String
        var size: SheetSize
        var orientation: SheetOrientation
        var standard: DrawingStandard
        var titleBlock: TitleBlock?
        var logo: String?
    }

    public static func encode(_ template: DrawingTemplate) -> Data {
        let body = Body(
            version: version, name: template.name, size: template.size, orientation: template.orientation, standard: template.standard,
            titleBlock: template.titleBlock, logo: template.logo?.base64EncodedString())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // Encoding plain strings, numbers and enums cannot fail.
        return (try? encoder.encode(body)) ?? Data()
    }

    public static func decode(_ data: Data, id: String) throws(DrawingTemplateProblem) -> DrawingTemplate {
        let decoder = JSONDecoder()
        guard let found = try? decoder.decode(Version.self, from: data) else { throw notATemplate }
        guard found.version <= version else { throw DrawingTemplateProblem("it was saved by a newer MetalCreator.") }
        guard let body = try? decoder.decode(Body.self, from: data), body.version >= 1 else { throw notATemplate }
        var logo: Data?
        if let text = body.logo {
            guard let bytes = Data(base64Encoded: text) else { throw DrawingTemplateProblem("its logo isn't readable.") }
            guard bytes.count <= LogoLimits.maximumBytes else { throw DrawingTemplateProblem("its logo is larger than 2 MB.") }
            logo = bytes
        }
        return DrawingTemplate(
            id: id, name: body.name, size: body.size, orientation: body.orientation, standard: body.standard,
            titleBlock: body.titleBlock ?? TitleBlock(), logo: logo)
    }

    private static let notATemplate = DrawingTemplateProblem("it isn't a drawing template.")
}
