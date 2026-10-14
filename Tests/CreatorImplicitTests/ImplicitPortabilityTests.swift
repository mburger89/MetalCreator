import Foundation
import Testing

/// Errata D11: `CreatorImplicit` builds on Linux and Windows. Nothing in it imports an Apple-only framework except the engines that live
/// in files named `Metal*.swift`, and those are compiled only under `#if canImport(Metal)`. This reads the sources, so it runs
/// everywhere and fails the day someone adds `import simd` to the mesher.
struct ImplicitPortabilityTests {
    /// Frameworks that exist on Apple platforms only.
    static let appleOnly = [
        "Metal", "MetalKit", "MetalPerformanceShaders", "simd", "CoreGraphics", "os", "Accelerate", "QuartzCore", "AppKit", "UIKit",
        "Darwin", "CoreFoundation", "ImageIO", "CoreImage", "Security",
    ]

    static let sources: [(name: String, lines: [String])] = {
        let module = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/CreatorImplicit")
        guard let walker = FileManager.default.enumerator(at: module, includingPropertiesForKeys: nil) else { return [] }
        var files: [(String, [String])] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            files.append((url.lastPathComponent, text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }))
        }
        return files.sorted { $0.0 < $1.0 }
    }()

    private static func imports(_ line: String) -> String? {
        let words = line.split(separator: " ").map(String.init)
        guard let at = words.firstIndex(of: "import"), at <= 1, words[..<at].allSatisfy({ $0 == "@preconcurrency" }),
              at + 1 < words.count else { return nil }
        return words[at + 1]
    }

    @Test func theModuleIsFound() {
        #expect(Self.sources.count > 20, "the sources were not found from \(#filePath)")
    }

    @Test func nothingButTheMetalEngineImportsAnAppleOnlyFramework() {
        for (name, lines) in Self.sources {
            for line in lines {
                guard let framework = Self.imports(line), Self.appleOnly.contains(framework) else { continue }
                #expect(name.hasPrefix("Metal") && framework == "Metal", "\(name) imports \(framework)")
            }
        }
    }

    @Test func aMetalFileIsWhollyUnderCanImportMetal() {
        for (name, lines) in Self.sources where name.hasPrefix("Metal") {
            let code = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("//") }
            #expect(code.first == "#if canImport(Metal)" && code.last == "#endif", "\(name) must be wrapped in #if canImport(Metal)")
        }
    }

    @Test func noMetalTypeIsNamedOutsideTheMetalEngine() {
        for (name, lines) in Self.sources where !name.hasPrefix("Metal") {
            for line in lines where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                #expect(line.range(of: #"\bMTL[A-Z]\w*"#, options: .regularExpression) == nil, "\(name) names a Metal type: \(line)")
            }
        }
    }
}
