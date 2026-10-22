import Foundation
import Testing

/// The COCCT shim (`Sources/COCCT/cocct_*.cpp`) must compile with GCC and Clang on Linux and with Clang targeting MSVC on
/// Windows (cross-platform spec section 3, plan xp-2). This Mac builds only the first and the Linux image only GCC-free
/// Clang, so the constructs that break a compiler we cannot run here are pinned by a scan of the sources. Each entry is a
/// construct that compiled on macOS and failed (or would fail) elsewhere.
struct ShimPortabilityTests {
    /// A construct the shim must not use, and what to write instead.
    struct Banned: Sendable, CustomTestStringConvertible {
        let token: String
        let instead: String
        var testDescription: String { token }
    }

    static let banned: [Banned] = [
        Banned(token: "M_PI", instead: "cocct::kPi (MSVC's <cmath> defines M_PI only under _USE_MATH_DEFINES)"),
        Banned(token: "<unistd.h>", instead: "nothing: POSIX only"),
        Banned(token: "<sys/", instead: "nothing: POSIX only"),
        Banned(token: "<dlfcn.h>", instead: "nothing: POSIX only"),
        Banned(token: "<pthread.h>", instead: "std::mutex or OCCT's Standard_Mutex"),
        Banned(token: "<mach", instead: "nothing: Apple only"),
        Banned(token: "__APPLE__", instead: "nothing: the shim has no platform branches"),
        Banned(token: "__attribute__", instead: "nothing: GCC and Clang only"),
        Banned(token: "__builtin_", instead: "the standard library"),
        Banned(token: "ssize_t", instead: "std::ptrdiff_t"),
        Banned(token: "std::filesystem", instead: "a path from Swift (it arrives as a UTF-8 const char *)"),
        Banned(token: "strcasecmp", instead: "nothing: POSIX only"),
        Banned(token: "alloca", instead: "std::vector"),
    ]

    @Test func theScanFindsTheShimsSources() throws {
        #expect(try Self.sources().count >= 9, "Sources/COCCT holds eight .cpp/.hpp files and cocct.h")
    }

    @Test(arguments: banned)
    func theShimAvoids(_ construct: Banned) throws {
        var offenders: [String] = []
        for (name, text) in try Self.sources() {
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.drop(while: { $0 == " " || $0 == "\t" })
                if !code.hasPrefix("//"), code.contains(construct.token) {
                    offenders.append("\(name):\(number + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "\(construct.token) at \(offenders.joined(separator: ", ")); use \(construct.instead)")
    }

    /// OCCT's headers pull in <windows.h> on Windows, whose `min` and `max` macros break `std::min(a, b)`.
    @Test func theManifestDefinesNOMINMAXOnWindows() throws {
        let manifest = try String(contentsOf: Self.repository.appending(path: "Package.swift"), encoding: .utf8)
        #expect(manifest.contains(#".define("NOMINMAX", .when(platforms: [.windows]))"#))
    }

    /// A debug build (`swift test`) links vcpkg's debug libraries and a release build its release ones, so the C runtime of the
    /// shim and of OpenCascade's DLLs is the same one in each (user decision 8). The workflow installs both sets (`CIPinTests`).
    @Test func theManifestLinksAWindowsDebugBuildAgainstTheDebugLibraries() throws {
        let manifest = try String(contentsOf: Self.repository.appending(path: "Package.swift"), encoding: .utf8)
        #expect(manifest.contains(#".unsafeFlags(["-L\(occtPrefix)/debug/lib"], .when(platforms: [.windows], configuration: .debug))"#))
        #expect(manifest.contains(#".unsafeFlags(["-L\(occtPrefix)/lib"], .when(platforms: [.windows], configuration: .release))"#))
    }

    /// `<repo>`, found from this file (`Tests/CreatorOCCTTests/ShimPortabilityTests.swift`).
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every C++ source and header of the shim, with its file name. Line endings are normalised: a Windows checkout that turned
    /// the files into "\r\n" would read as one line (Swift counts "\r\n" as one Character), and the scan would blame a comment's
    /// mention of a banned name. `.gitattributes` keeps the files LF; this keeps the test right if it ever does not.
    private static func sources() throws -> [(name: String, text: String)] {
        let directory = repository.appending(path: "Sources/COCCT")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { ["cpp", "hpp", "h"].contains(URL(filePath: $0).pathExtension) }
            .sorted()
        return try files.map {
            ($0, try String(contentsOf: directory.appending(path: $0), encoding: .utf8).replacing("\r\n", with: "\n"))
        }
    }
}
