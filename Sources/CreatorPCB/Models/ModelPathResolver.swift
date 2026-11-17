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
        var vars = variables.values
        vars["KIPRJMOD"] = boardFolder
        let expanded = expand(path, vars)
        let first = isAbsolute(expanded) ? expanded : join(boardFolder, expanded, platform: platform)

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

    private static func expand(_ path: String, _ vars: [String: String]) -> String {
        var out = ""
        let chars = Array(path)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "$", index + 1 < chars.count, chars[index + 1] == "{" || chars[index + 1] == "(" {
                let close: Character = chars[index + 1] == "{" ? "}" : ")"
                if let end = chars[(index + 2)...].firstIndex(of: close) {
                    let name = String(chars[(index + 2)..<end])
                    if let value = vars[name] {
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

    private static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\") { return true }
        let chars = Array(path)
        return chars.count >= 3 && chars[0].isLetter && chars[1] == ":" && (chars[2] == "\\" || chars[2] == "/")
    }

    private static func usesBackslashes(_ folder: String, platform: KiCadPlatform) -> Bool {
        folder.contains("\\") || (platform == .windows && folder.count >= 2 && Array(folder)[1] == ":")
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
            if lowered.hasPrefix(prefix) { return String(normal.dropFirst(prefix.count)) }
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
