import CreatorDrawing
import CreatorGeometry
import CreatorStyle
import Foundation

/// The folder the person's drawing templates live in, one `<id>.mctemplate` file each (DR-5 R10): the file's stem is the id.
/// The app's is `<user data>/MetalCreator/Drawing Templates`; tests pass a temporary folder.
public struct DrawingTemplateFolder: Hashable, Sendable {
    public let url: URL

    public init(_ url: URL) {
        self.url = url
    }

    public static var applicationSupport: DrawingTemplateFolder {
        DrawingTemplateFolder(UserDataFolder.url.appending(path: "MetalCreator/Drawing Templates", directoryHint: .isDirectory))
    }

    /// Whether `id` can be a file's stem: not empty, no path separator, no leading ".", no control character, at most 200 UTF-8 bytes.
    public static func isUsable(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 200 && !id.hasPrefix(".") && !id.contains("/") && !id.contains("\\")
            && !id.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    public func fileURL(for id: String) -> URL {
        url.appending(path: "\(id).mctemplate", directoryHint: .notDirectory)
    }

    /// Every template in the folder by file name, and a sentence for each file that was skipped. A folder that doesn't exist yet
    /// holds none.
    public func load() -> (templates: [DrawingTemplate], problems: [String]) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return ([], [])
        } catch {
            return ([], ["The templates folder couldn't be read: \(error.localizedDescription)"])
        }
        var templates: [DrawingTemplate] = []
        var problems: [String] = []
        let candidates = files.filter { $0.pathExtension == "mctemplate" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in candidates {
            let id = file.deletingPathExtension().lastPathComponent
            let skipped = "“\(file.lastPathComponent)” was skipped:"
            guard Self.isUsable(id) else {
                problems.append("\(skipped) its name can't be a template's id.")
                continue
            }
            let data: Data
            do throws(RegularFileProblem) {
                data = try RegularFile.read(file, limit: DrawingTemplateLimits.maximumFileBytes)
            } catch {
                switch error {
                case .notAFile: problems.append("\(skipped) it isn't a file.")
                case .tooLarge: problems.append("\(skipped) it is larger than 3 MB.")
                case .unreadable(let reason): problems.append("\(skipped) \(reason)")
                }
                continue
            }
            do throws(DrawingTemplateProblem) {
                templates.append(try DrawingTemplateFile.decode(data, id: id))
            } catch {
                problems.append("\(skipped) \(error.message)")
            }
        }
        return (templates, problems)
    }

    /// Writes `template` to its file, creating the folder if needed.
    public func save(_ template: DrawingTemplate) throws(DrawingTemplateProblem) {
        let prefix = "“\(template.name)” couldn't be saved:"
        guard Self.isUsable(template.id) else { throw DrawingTemplateProblem("\(prefix) its id can't be a file name.") }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try DrawingTemplateFile.encode(template).write(to: fileURL(for: template.id), options: .atomic)
        } catch {
            throw DrawingTemplateProblem("\(prefix) \(error.localizedDescription)")
        }
    }

    /// Deletes the file of the template with `id`; one that is already gone is fine. `name` words the failure.
    public func remove(_ id: String, named name: String? = nil) throws(DrawingTemplateProblem) {
        let prefix = name.map { "“\($0)” couldn't be deleted:" } ?? "The template couldn't be deleted:"
        guard Self.isUsable(id) else { throw DrawingTemplateProblem("\(prefix) its id can't be a file name.") }
        do {
            try FileManager.default.removeItem(at: fileURL(for: id))
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw DrawingTemplateProblem("\(prefix) \(error.localizedDescription)")
        }
    }
}
