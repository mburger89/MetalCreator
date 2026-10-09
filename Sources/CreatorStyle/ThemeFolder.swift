import Foundation

/// The folder the person's own themes live in, one `<id>.mctheme` file each: the file's name is the theme's id,
/// which renames never change. The app's is `~/Library/Application Support/MetalCreator/Themes`; tests pass a
/// temporary folder, so they never touch the person's themes.
public struct ThemeFolder: Hashable, Sendable {
    public let url: URL

    public init(_ url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/MetalCreator/Themes`.
    public static var applicationSupport: ThemeFolder {
        ThemeFolder(URL.applicationSupportDirectory.appending(path: "MetalCreator/Themes", directoryHint: .isDirectory))
    }

    /// The `.mctheme` file of the theme with `id`.
    public func fileURL(for id: ColorTheme.ID) -> URL {
        url.appending(path: "\(id).mctheme", directoryHint: .notDirectory)
    }

    /// Every theme in the folder, by file name, and a sentence for each file that was skipped: one that can't be
    /// read, or one named like a `reserved` (built-in) id. A folder that doesn't exist yet holds no themes.
    public func load(reserved: Set<ColorTheme.ID>) -> (themes: [ColorTheme], problems: [String]) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return ([], [])
        } catch {
            return ([], ["The themes folder couldn’t be read: \(error.localizedDescription)"])
        }
        var themes: [ColorTheme] = []
        var problems: [String] = []
        let themeFiles = files.filter { $0.pathExtension == "mctheme" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in themeFiles {
            let id = file.deletingPathExtension().lastPathComponent
            let skipped = "“\(file.lastPathComponent)” was skipped:"
            guard !reserved.contains(id) else {
                problems.append("\(skipped) its name is a built-in theme’s.")
                continue
            }
            do {
                let data = try Data(contentsOf: file)
                do throws(ThemeFileError) {
                    themes.append(try ThemeFile.decode(data, id: id, fallbackName: id))
                } catch {
                    problems.append("\(skipped) \(error.message)")
                }
            } catch {
                problems.append("\(skipped) \(error.localizedDescription)")
            }
        }
        return (themes, problems)
    }

    /// Writes `theme` to its file, creating the folder if needed.
    public func save(_ theme: ColorTheme) throws(ThemeProblem) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try ThemeFile.encode(theme).write(to: fileURL(for: theme.id), options: .atomic)
        } catch {
            throw ThemeProblem("“\(theme.name)” couldn’t be saved: \(error.localizedDescription)")
        }
    }

    /// Deletes the file of the theme with `id`. A file that is already gone is fine.
    public func remove(_ id: ColorTheme.ID) throws(ThemeProblem) {
        do {
            try FileManager.default.removeItem(at: fileURL(for: id))
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw ThemeProblem("The theme couldn’t be deleted: \(error.localizedDescription)")
        }
    }
}
