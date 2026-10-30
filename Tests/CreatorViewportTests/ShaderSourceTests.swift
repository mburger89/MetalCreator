import Foundation
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU
#endif
import Testing
@testable import CreatorGraph
@testable import CreatorViewport

/// The HLSL shaders in `Sources/CreatorViewport/Shaders` and what the build made of them. The HLSL structs the shaders read have the sizes of the
/// Swift structs that fill them (every platform: `GPUDataTests` pins the Swift side, this pins the HLSL side to the same numbers).
/// On Linux and Windows the compiled shaders are a build product (MetalUI's `CompileShadersOnBuild` plugin, user decision U1(b)), so the tests also
/// check that the build made every one of them where the renderer looks and that it is current. Nothing compiled is checked in.
struct ShaderSourceTests {
    /// `Sources/CreatorViewport/Shaders`, found from this file: `Tests/CreatorViewportTests/ShaderSourceTests.swift` is three directories
    /// below the root.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/CreatorViewport/Shaders")

    static func hexDigest(of url: URL) throws -> String {
        SHA256.hash(try Data(contentsOf: url)).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    static var stageSources: [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".vert.hlsl") || $0.hasSuffix(".frag.hlsl") }.sorted().map { directory.appending(path: $0) }
    }

    // MARK: The HLSL structs have the Swift structs' sizes (every platform)

    /// The size in bytes of each HLSL type the header uses. There is no float3: it packs differently in a constant buffer, a
    /// structured buffer and Swift, which is why the header spells every vector as a float4.
    static let typeSizes: [String: Int] = ["float4": 16, "uint4": 16, "float2": 8, "uint2": 8, "float": 4, "uint": 4]

    /// `struct Name { type member; ... };` blocks of the header, as member types in order (array members repeat their element).
    static func structs() throws -> [String: [(type: String, count: Int)]] {
        let text = try String(contentsOf: directory.appending(path: "common.hlsli"), encoding: .utf8)
        var result: [String: [(type: String, count: Int)]] = [:]
        var current: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {   // "\r\n" too: a Windows checkout
            // A `//` comment, whole-line or trailing, is no part of the declaration.
            let code = rawLine.components(separatedBy: "//")[0]
            let line = code.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("struct "), line.hasSuffix("{") {
                current = line.dropFirst("struct ".count).dropLast(1).trimmingCharacters(in: .whitespaces)
                result[current ?? ""] = []
            } else if line.hasPrefix("}") {
                current = nil
            } else if let name = current, line.hasSuffix(";") {
                let words = line.dropLast().split(separator: " ")
                guard words.count == 2 else { continue }
                var count = 1
                if let open = words[1].firstIndex(of: "["), let close = words[1].firstIndex(of: "]") {
                    count = Int(words[1][words[1].index(after: open)..<close]) ?? 1
                }
                result[name, default: []].append((String(words[0]), count))
            }
        }
        return result
    }

    /// The struct's size: members in order, each aligned to its own size (at most 16), the whole rounded up to 16.
    static func size(of members: [(type: String, count: Int)]) -> Int? {
        var offset = 0
        for member in members {
            guard let size = typeSizes[member.type] else { return nil }
            let alignment = min(size, 16)
            offset = (offset + alignment - 1) / alignment * alignment + size * member.count
        }
        return (offset + 15) / 16 * 16
    }

    @Test func theHeadersStructsHaveTheSizesOfTheirSwiftTwins() throws {
        let sizes = try Self.structs().compactMapValues { Self.size(of: $0) }
        let swift: [String: Int] = [
            "FrameUniforms": MemoryLayout<FrameUniforms>.stride, "MeshVertex": MemoryLayout<MeshVertex>.stride,
            "DrawUniforms": MemoryLayout<DrawUniforms>.stride, "ShadeUniforms": MemoryLayout<ShadeUniforms>.stride,
            "LineInstance": MemoryLayout<LineInstance>.stride, "LineUniforms": MemoryLayout<LineUniforms>.stride,
            "GridUniforms": MemoryLayout<GridUniforms>.stride, "FillVertex": MemoryLayout<FillVertex>.stride,
            "ClipUniforms": MemoryLayout<ClipUniforms>.stride, "FieldRampUniforms": MemoryLayout<FieldRampUniforms>.stride,
            "CubeVertex": MemoryLayout<CubeVertex>.stride,
            "SliceUniforms": MemoryLayout<SliceUniforms>.stride,
        ]
        #expect(sizes.count == (try Self.structs().count), "every struct in the header is made of float4, uint4, float2, float and uint")
        for (name, expected) in swift {
            #expect(sizes[name] == expected, "\(name): HLSL \(sizes[name].map(String.init) ?? "missing") against Swift \(expected)")
        }
        #expect(Set(sizes.keys) == Set(swift.keys), "a struct added to the header needs its Swift twin pinned here")
    }

    #if os(Linux) || os(Windows)
    // MARK: The build made the shaders (Linux and Windows)

    /// Where a running app finds its compiled shaders: MetalUI's own lookup (`SDLGPUShaderLibrary.locate`, `docs/packaging.md` section 4a),
    /// `MetalUIAppShaders` beside the executable, then the target's resource bundle the plugin filled, which `SDLViewportShaders` asks.
    static var runtimeDirectory: URL? { try? SDLViewportShaders.library().directory }

    /// What a missing or stale result of the build tells the person who sees it.
    static let remedy = "The shaders are compiled by `swift build` (MetalUI's CompileShadersOnBuild plugin) with the pinned "
        + "SDL_shadercross, scripts/shadercross.env, found by METALUI_SHADERCROSS or on PATH; scripts/linux-test.sh does it in the image."

    /// `<sha256>  <name>` lines of a file the build wrote (`SOURCE.sha256` and `INCLUDES.sha256`, both by MetalUI's `MetalUICompileShaders`), as a dictionary of name to digest.
    static func hashes(in file: String, of directory: URL) throws -> [String: String] {
        let text = try String(contentsOf: directory.appending(path: file), encoding: .utf8)
        var table: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2 { table[String(parts[1])] = String(parts[0]) }
        }
        return table
    }

    /// The build produced every stage's four files where the renderer reads them, and the build is current: the `SOURCE.sha256` and
    /// `INCLUDES.sha256` MetalUI's tool wrote match the sources and the header now (the freshness check of user decision
    /// U1(b)). A source edited after the last build fails here and says so.
    @Test func theBuildCompiledEveryStageIntoTheDirectoryTheRendererReads() throws {
        let sources = Self.stageSources
        #expect(sources.count >= 20, "the viewport's vertex and fragment stages are found")
        let compiled = try #require(
            Self.runtimeDirectory, "no compiled shader directory beside the executable or in the resource bundle. \(Self.remedy)")
        for source in sources {
            let stem = String(source.lastPathComponent.dropLast(".hlsl".count))
            for blob in ["spv", "dxil", "msl", "json"] {
                let size = (try? Data(contentsOf: compiled.appending(path: "\(stem).\(blob)")).count) ?? 0
                #expect(size > 0, "\(stem).\(blob) is missing or empty in \(compiled.path). \(Self.remedy)")
            }
        }
        let table = try Self.hashes(in: "SOURCE.sha256", of: compiled)
        #expect(Set(table.keys) == Set(sources.map(\.lastPathComponent)), "SOURCE.sha256 lists exactly the stage sources. \(Self.remedy)")
        for source in sources {
            #expect(table[source.lastPathComponent] == (try Self.hexDigest(of: source)),
                    "\(source.lastPathComponent) changed after the last build. \(Self.remedy)")
        }
        let includes = try Self.hashes(in: "INCLUDES.sha256", of: compiled)
        let headers = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path).filter { $0.hasSuffix(".hlsli") }
        #expect(Set(includes.keys) == Set(headers), "INCLUDES.sha256 lists exactly the shared headers. \(Self.remedy)")
        for header in headers {
            #expect(includes[header] == (try Self.hexDigest(of: Self.directory.appending(path: header))),
                    "\(header) changed after the last build. \(Self.remedy)")
        }
    }
    #endif
}

#if canImport(MetalUISDLGPU)
/// The SDL renderer finds its shaders the way a shipped app does (MetalUI `docs/packaging.md` section 4a): the compiled directory, here
/// the target's resource bundle, holds every stage for the platform's driver, with its reflection.
struct ViewportShaderDirectoryTests {
    @Test func everyStageLoadsForThePlatformsDriver() throws {
        #expect(try SDLViewportShaders.verify() == 20)
        #expect(try ViewportShaderCheck.run() == "the viewport's 20 SDL_GPU shader stages were found")
    }
    /// `--self-test` asks the viewport whether its shaders were built. With no directory it fails, and the message says which directory
    /// it looked in, that the shaders are built and not checked in, and what to do (user decision U1(b)).
    @Test func aMissingDirectoryFailsTheSelfTestCheckWithAMessageThatSaysWhatToRun() {
        let nowhere = FileManager.default.temporaryDirectory.appending(path: "no-viewport-shaders-\(UUID().uuidString)")
        do {
            _ = try ViewportShaderCheck.run(sourceTree: nowhere, bundled: false)
            Issue.record("the check passed with no compiled shaders anywhere")
        } catch let failure as ViewportShaderCheck.Failure {
            #expect(failure.description.contains(nowhere.path), "it names the directory it looked in: \(failure)")
            #expect(failure.description.contains("METALUI_SHADERCROSS"), "it names the fix: \(failure)")
            #expect(failure.description.contains("SDL_shadercross"), "it names the tool the build needs: \(failure)")
            #expect(failure.description.contains("scripts/shadercross.env"), "it says where the pin is: \(failure)")
        } catch {
            Issue.record("the check threw \(error), not a ViewportShaderCheck.Failure")
        }
    }

    @Test func aStageThatIsMissingIsNamed() throws {
        let library = try SDLViewportShaders.library()
        #expect(throws: (any Error).self) { try library.vertex("no_such_shader", driver: SDLViewportShaders.platformDriver) }
    }
}
#endif
