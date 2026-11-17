import Foundation

/// Where a footprint's 3D model is.
public enum ModelLocation: Sendable, Equatable {
    /// Candidate files, in the order to try.
    case files([String])
    /// A model stored in the board (`kicad-embed://name`).
    case embedded(name: String)
}

/// Turns a model path as KiCad stores it into candidate files. Pure: it never touches the file system.
public enum ModelPathResolver {
    public static func locate(_ path: String, boardFolder: String, variables: KiCadPathVariables,
                              platform: KiCadPlatform) -> ModelLocation {
        let embedPrefix = "kicad-embed://"
        if path.lowercased().hasPrefix(embedPrefix) {
            return .embedded(name: String(path.dropFirst(embedPrefix.count)))
        }
        var board = boardFolder
        if board.count > 1, board.hasSuffix("/") || board.hasSuffix("\\") { board.removeLast() }
        var vars = variables.values
        vars["KIPRJMOD"] = board
        let expanded = expand(path, vars, caseInsensitive: platform == .windows)
        let first = isAbsolute(expanded) ? expanded : joinRelative(board, expanded, platform: platform)

        var candidates = [first]
        if let relative = libraryRelativePart(of: first) {
            let versions: [Int] = platform == .linux || platform == .macOS ? [10] : Array((6...10).reversed())
            for version in versions {
                candidates.append(join(platform.libraryFolder(version: version), relative, platform: platform))
            }
        }

        var result: [String] = []
        for candidate in candidates {
            for option in twins(of: candidate) where !result.contains(option) { result.append(option) }
        }
        return .files(result)
    }

    private static func expand(_ path: String, _ vars: [String: String], caseInsensitive: Bool) -> String {
        var out = ""
        let chars = Array(path)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "$", index + 1 < chars.count, chars[index + 1] == "{" || chars[index + 1] == "(" {
                let close: Character = chars[index + 1] == "{" ? "}" : ")"
                if let end = chars[(index + 2)...].firstIndex(of: close) {
                    let name = String(chars[(index + 2)..<end])
                    if let value = lookup(name, vars, caseInsensitive: caseInsensitive) {
                        out += value
                        index = end + 1
                        continue
                    }
                }
            }
            out.append(char)
            index += 1
        }
        return out
    }

    private static func lookup(_ name: String, _ vars: [String: String], caseInsensitive: Bool) -> String? {
        if let value = vars[name] { return value }
        guard caseInsensitive else { return nil }
        let upper = name.uppercased()
        for key in vars.keys.sorted() where key.uppercased() == upper { return vars[key] }
        return nil
    }

    private static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\") { return true }
        let chars = Array(path)
        return chars.count >= 3 && chars[0].isLetter && chars[1] == ":" && (chars[2] == "\\" || chars[2] == "/")
    }

    private static func usesBackslashes(_ folder: String, platform: KiCadPlatform) -> Bool {
        folder.contains("\\") || (platform == .windows && folder.count >= 2 && Array(folder)[1] == ":")
    }

    /// Joins a relative path to the board's folder, collapsing `.` and `..` (never above the root).
    private static func joinRelative(_ folder: String, _ relative: String, platform: KiCadPlatform) -> String {
        let backslashes = usesBackslashes(folder, platform: platform)
        let separator = backslashes ? "\\" : "/"
        var root = ""
        var rest = folder
        if folder.count >= 3, Array(folder)[1] == ":" {
            root = String(folder.prefix(2)) + separator
            rest = String(folder.dropFirst(2))
        } else if folder.hasPrefix("\\\\") || folder.hasPrefix("//") {
            root = separator + separator
        } else if folder.hasPrefix("/") || folder.hasPrefix("\\") {
            root = separator
        }
        var segments = rest.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        for part in relative.replacingOccurrences(of: "\\", with: "/").split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(String(part))
            }
        }
        return root + segments.joined(separator: separator)
    }

    private static func join(_ folder: String, _ relative: String, platform: KiCadPlatform) -> String {
        if usesBackslashes(folder, platform: platform) {
            let tail = relative.replacingOccurrences(of: "/", with: "\\")
            return folder.hasSuffix("\\") ? folder + tail : folder + "\\" + tail
        }
        return folder.hasSuffix("/") ? folder + relative : folder + "/" + relative
    }

    /// The part of an absolute path under any known KiCad library folder, `/`-separated.
    private static func libraryRelativePart(of path: String) -> String? {
        let normal = path.replacingOccurrences(of: "\\", with: "/")
        let lowered = normal.lowercased()
        var folders: [String] = []
        for platform in [KiCadPlatform.macOS, .linux] { folders.append(platform.libraryFolder(version: 10)) }
        for version in 6...10 { folders.append(KiCadPlatform.windows.libraryFolder(version: version)) }
        for folder in folders {
            let prefix = folder.replacingOccurrences(of: "\\", with: "/").lowercased() + "/"
            if lowered.hasPrefix(prefix) {
                let rest = lowered.dropFirst(prefix.count)
                if normal.count == lowered.count { return String(normal.dropFirst(prefix.count)) }
                return String(rest)
            }
        }
        return nil
    }

    /// For a VRML file its STEP then STP twins come first.
    private static func twins(of path: String) -> [String] {
        let lowered = path.lowercased()
        guard lowered.hasSuffix(".wrl") || lowered.hasSuffix(".wrz") else { return [path] }
        let stem = String(path.dropLast(4))
        return [stem + ".step", stem + ".stp", path]
    }
}
