import Foundation
import Testing
@testable import CreatorMCP

@MainActor struct FileToolTests {
    private func make() async throws -> (SessionFixture, FakeFileSession, MCPServerCore) {
        let fixture = try await SessionFixture()
        let fake = FakeFileSession(base: fixture.session)
        let core = MCPServerCore(session: fake, tools: MCPCatalogue.tools, resources: MCPCatalogue.resources, serverVersion: "test")
        return (fixture, fake, core)
    }

    private func call(_ core: MCPServerCore, _ tool: String, _ arguments: JSONValue, token: Bool = false) async throws
        -> (lines: [JSONValue], result: JSONValue, isError: Bool) {
        var params: [String: JSONValue] = ["name": .string(tool), "arguments": arguments]
        if token { params["_meta"] = .object(["progressToken": .string("t1")]) }
        let request = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .int(1), "method": .string("tools/call"), "params": .object(params),
        ])
        let sent = Collected()
        await core.handle(line: request.encoded()) { sent.add($0) }
        let lines = try sent.all.map { try JSONValue.parse($0) }
        let result = try #require(lines.last?["result"])
        let text = try #require(result["content"]?.array?.first?["text"]?.string)
        let isError = result["isError"]?.bool ?? false
        return (lines, isError ? .string(text) : try JSONValue.parse(Data(text.utf8)), isError)
    }

    @Test func openPassesDiscardFlag() async throws {
        let (_, fake, core) = try await make()
        let (_, result, isError) = try await call(core, "open_document", .object([
            "path": .string(absoluteTestPath("a.mcgraph")), "discard_unsaved": .bool(true),
        ]))
        #expect(!isError && result["done"]?.bool == true)
        #expect(fake.calls == [.open(URL(fileURLWithPath: absoluteTestPath("a.mcgraph")), discard: true)])
        _ = try await call(core, "open_document", .object(["path": .string(absoluteTestPath("b.mcgraph"))]))
        #expect(fake.calls.last == .open(URL(fileURLWithPath: absoluteTestPath("b.mcgraph")), discard: false))
    }

    @Test func newAndSavePassTheirFlags() async throws {
        let (_, fake, core) = try await make()
        fake.outcome = .done("Saved.")
        let (_, result, _) = try await call(core, "save_document", .object(["overwrite": .bool(true)]))
        #expect(result["message"]?.string == "Saved.")
        _ = try await call(core, "save_document", .object(["path": .string(absoluteTestPath("x.mcgraph"))]))
        _ = try await call(core, "new_document", .object([:]))
        #expect(fake.calls == [
            .save(nil, overwrite: true), .save(URL(fileURLWithPath: absoluteTestPath("x.mcgraph")), overwrite: false), .new(discard: false),
        ])
    }

    @Test func sessionRefusalIsRelayed() async throws {
        let (_, fake, core) = try await make()
        fake.outcome = .refused("The document has unsaved changes.")
        let (_, result, isError) = try await call(core, "new_document", .object([:]))
        #expect(isError && result.string == "The document has unsaved changes.")
    }

    @Test func relativePathsAreRefusedBeforeTheSession() async throws {
        let (_, fake, core) = try await make()
        for (tool, arguments) in [
            ("open_document", JSONValue.object(["path": .string("a.mcgraph")])),
            ("save_document", .object(["path": .string("a.mcgraph")])),
            ("export", .object(["kind": .string("stl"), "path": .string("out.stl")])),
        ] {
            let (_, result, isError) = try await call(core, tool, arguments)
            #expect(isError && result.string == "Paths must be absolute.")
        }
        #expect(fake.calls.isEmpty)
    }

    @Test func exportKindIsChecked() async throws {
        let (_, fake, core) = try await make()
        let (_, result, isError) = try await call(
            core, "export", .object(["kind": .string("obj"), "path": .string(absoluteTestPath("o.obj"))])
        )
        #expect(isError && result.string == "Export kinds are step, stl and 3mf.")
        #expect(fake.calls.isEmpty)
        let (_, ok, okError) = try await call(core, "export", .object([
            "kind": .string("3mf"), "path": .string(absoluteTestPath("o.3mf")), "overwrite": .bool(true),
        ]))
        #expect(!okError && ok["done"]?.bool == true)
        #expect(fake.calls == [.export("3mf", URL(fileURLWithPath: absoluteTestPath("o.3mf")), overwrite: true)])
    }

    @Test func exportForwardsProgressWhenATokenIsSent() async throws {
        let (_, fake, core) = try await make()
        fake.exportProgress = [0.5]
        let (lines, _, _) = try await call(
            core, "export", .object(["kind": .string("stl"), "path": .string(absoluteTestPath("o.stl"))]), token: true
        )
        try #require(lines.count == 2, "lines: \(lines)")
        #expect(lines[0]["method"]?.string == "notifications/progress")
        #expect(lines[0]["params"]?["progressToken"]?.string == "t1")
        #expect(lines[1]["result"] != nil)
        let (quiet, _, _) = try await call(core, "export", .object(["kind": .string("stl"), "path": .string(absoluteTestPath("o.stl"))]))
        #expect(quiet.count == 1)
    }
}

struct AbsolutePathTests {
    @Test func posixRootsAreAbsoluteEverywhereButWindows() {
        #if !os(Windows)
        #expect(AbsolutePath.isAbsolute("/tmp/a.mcgraph"))
        #expect(!AbsolutePath.isAbsolute("a.mcgraph"))
        #expect(!AbsolutePath.isAbsolute("a:b/x"), "a colon is not a drive off Windows")
        #expect(!AbsolutePath.isAbsolute("C:\\x"))
        #expect(!AbsolutePath.isAbsolute(""))
        #endif
    }

    @Test func windowsRulesHoldOnEveryPlatform() {
        #expect(AbsolutePath.isWindowsAbsolute("C:\\Users\\a.mcgraph"))
        #expect(AbsolutePath.isWindowsAbsolute("d:/a.mcgraph"))
        #expect(AbsolutePath.isWindowsAbsolute("\\\\server\\share\\a.mcgraph"))
        #expect(!AbsolutePath.isWindowsAbsolute("C:foo"))
        #expect(!AbsolutePath.isWindowsAbsolute("C:"))
        #expect(!AbsolutePath.isWindowsAbsolute("a:b/x"))
        #expect(!AbsolutePath.isWindowsAbsolute("\\\\server"))
        #expect(!AbsolutePath.isWindowsAbsolute("\\\\\\share"))
        #expect(!AbsolutePath.isWindowsAbsolute("foo\\bar"))
    }

    #if os(Windows)
    @Test func windowsAcceptsDrivesAndSharesAndRefusesDriveRelative() {
        #expect(AbsolutePath.isAbsolute("C:\\x"))
        #expect(AbsolutePath.isAbsolute("C:/x"))
        #expect(AbsolutePath.isAbsolute("\\\\server\\share\\x"))
        #expect(!AbsolutePath.isAbsolute("C:foo"))
        #expect(!AbsolutePath.isAbsolute("/x"))
    }
    #endif
}
