import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// What a package with parts in other files is refused for (Task 11b), and the budget across parts.
extension ThreeMFProductionTests {
    // MARK: Refusals

    @Test func aPathInANonRootPartIsRefused() {
        let chained = Self.part(Self.wrapper(1, Self.component(7, path: "/3D/Objects/b.model")),
                                namespaces: "xmlns=\"\(Package.core)\" xmlns:p=\"\(Package.production)\"")
        let data = Self.package(root: Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2)),
                                parts: [("3D/Objects/a.model", chained),
                                        ("3D/Objects/b.model", Self.part(Package.object(id: 7, mesh: Self.cube))),
                                       ])
        guard case .malformedModel? = problem(data) else {
            Issue.record("a chained part")
            return
        }
        // Not even a path to itself, or to the root.
        let loop = Self.part(Self.wrapper(1, Self.component(7, path: "/3D/3dmodel.model")),
                             namespaces: "xmlns=\"\(Package.core)\" xmlns:p=\"\(Package.production)\"")
        let looped = Self.package(root: Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2)),
                                  parts: [("3D/Objects/a.model", loop)])
        guard case .malformedModel? = problem(looped) else {
            Issue.record("a path from a part to the root")
            return
        }
    }

    @Test func aMissingPartIsRefused() {
        let data = Self.simple(path: "/3D/Objects/gone.model")
        #expect(problem(data) == .malformedModel("it names the part 3D/Objects/gone.model, which the file doesn't have."))
        let long = "/3D/" + String(repeating: "n", count: 200) + ".model"
        guard case .malformedModel(let reason)? = problem(Self.simple(path: long)) else {
            Issue.record("a long missing name")
            return
        }
        #expect(reason.contains("3D/" + String(repeating: "n", count: 77) + "…") && !reason.contains(String(repeating: "n", count: 78)))
    }

    @Test func aMissingObjectInAPartIsRefused() {
        let root = Self.root(Self.wrapper(2, Self.component(9, path: "/3D/Objects/a.model")), Package.item(2))
        let data = Self.package(root: root, parts: [("3D/Objects/a.model", Self.part(Package.object(id: 1, mesh: Self.cube)))])
        #expect(problem(data) == .malformedModel("it refers to object 9, which it doesn't have."))
    }

    @Test func aDifferentUnitInAPartIsRefused() {
        let root = Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2))
        for unit in ["inch", "micron"] as [String?] {
            let part = Self.part(Package.object(id: 1, mesh: Self.cube), unit: unit)
            let data = Self.package(root: root, parts: [("3D/Objects/a.model", part)])
            guard case .malformedModel(let reason)? = problem(data) else {
                Issue.record("a part in \(unit ?? "nil")")
                continue
            }
            #expect(reason == "a part of the file uses a different unit from the model.")
        }
        // No unit at all is millimetres, which a millimetre root matches.
        let bare = Self.package(root: root, parts: [("3D/Objects/a.model", Self.part(Package.object(id: 1, mesh: Self.cube), unit: nil))])
        #expect(problem(bare) == nil)
    }

    @Test func aPartWithAnUnsupportedRequiredExtensionIsRefused() {
        let beams = Self.part(Package.object(id: 1, mesh: Self.cube),
                              namespaces: "xmlns=\"\(Package.core)\" xmlns:b=\"\(Package.beamLattice)\" requiredextensions=\"b\"")
        let data = Self.package(root: Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2)),
                                parts: [("3D/Objects/a.model", beams)])
        guard case .unsupportedExtension? = problem(data) else {
            Issue.record("a required extension in a part")
            return
        }
        let doctype = "<?xml version=\"1.0\"?><!DOCTYPE model []>" + Self.part(Package.object(id: 1, mesh: Self.cube))
        let second = Self.package(root: Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2)),
                                  parts: [("3D/Objects/a.model", doctype)])
        guard case .malformedModel? = problem(second) else {
            Issue.record("a DOCTYPE in a part")
            return
        }
    }

    @Test func partsTogetherOverTheByteBudgetAreRefused() {
        let part = Self.part(Package.object(id: 1, mesh: Self.cube))
        let names = (0..<3).map { "3D/Objects/\($0).model" }
        let wrappers = names.indices.map { Self.wrapper(10 + $0, Self.component(1, path: "/" + names[$0])) }.joined()
        let build = names.indices.map { Package.item(10 + $0) }.joined()
        let root = Self.root(wrappers, build)
        let data = Self.package(root: root, parts: names.map { ($0, part) })
        let exact = root.utf8.count + 3 * part.utf8.count
        #expect(problem(data, byteLimit: exact) == nil)
        #expect(problem(data, byteLimit: exact - 1) == .modelTooLarge)
    }

    @Test func partsTogetherOverTheTriangleBudgetAreRefused() {
        let names = (0..<3).map { "3D/Objects/\($0).model" }
        let wrappers = names.indices.map { Self.wrapper(10 + $0, Self.component(1, path: "/" + names[$0])) }.joined()
        let build = names.indices.map { Package.item(10 + $0) }.joined()
        let data = Self.package(root: Self.root(wrappers, build),
                                parts: names.map { ($0, Self.part(Package.object(id: 1, mesh: Self.cube))) })
        // Each part alone is under 30 triangles; together they are 36 stored.
        #expect(problem(data, triangleLimit: 36) == nil)
        #expect(problem(data, triangleLimit: 35) == .overTriangleLimit)
        // Records are shared too: three wrappers, three components, three items, three part objects.
        #expect(problem(data, recordLimit: 12) == nil)
        guard case .malformedModel? = problem(data, recordLimit: 11) else {
            Issue.record("records across parts")
            return
        }
    }

    @Test func tooManyPartsAreRefused() {
        let names = (0..<5).map { "3D/Objects/\($0).model" }
        let wrappers = names.indices.map { Self.wrapper(10 + $0, Self.component(1, path: "/" + names[$0])) }.joined()
        let build = names.indices.map { Package.item(10 + $0) }.joined()
        // None of the parts exists: the count is refused before any is looked for.
        let data = Self.package(root: Self.root(wrappers, build), parts: [])
        #expect(problem(data, partLimit: 4) == .tooManyParts)
        #expect(MeshImportProblem.tooManyParts.message == "This 3MF has too many parts.")
        #expect(problem(data, partLimit: 5) != .tooManyParts)
    }

    @Test func aZipBombPartIsRefusedBeforeAllocating() throws {
        var data = Self.simple()
        // Make the part's central directory entry declare 3 GB of model.
        let signature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        var found = 0
        var index = 0
        let bytes = [UInt8](data)
        while index + 46 < bytes.count {
            if Array(bytes[index..<index + 4]) == signature {
                let nameLength = Int(bytes[index + 28]) | Int(bytes[index + 29]) << 8
                let name = String(bytes: bytes[(index + 46)..<(index + 46 + nameLength)], encoding: .utf8)
                if name == "3D/Objects/a.model" {
                    let three = UInt32(3) << 30
                    for shift in 0..<4 { data[index + 24 + shift] = UInt8((three >> (8 * UInt32(shift))) & 0xFF) }
                    found += 1
                }
            }
            index += 1
        }
        #expect(found == 1)
        let problem = problem(data)
        #expect(problem == .modelTooLarge)
    }

    // MARK: Cancellation

    @Test func cancellationBetweenParts() {
        let names = (0..<4).map { "3D/Objects/\($0).model" }
        let wrappers = names.indices.map { Self.wrapper(10 + $0, Self.component(1, path: "/" + names[$0])) }.joined()
        let build = names.indices.map { Package.item(10 + $0) }.joined()
        let data = Self.package(root: Self.root(wrappers, build),
                                parts: names.map { ($0, Self.part(Package.object(id: 1, mesh: Self.cube))) })
        // Counted asks for the whole read, then cancelled at each later ask in turn: every one ends in a cancellation.
        let counter = ThreeMFReaderTests.Calls()
        _ = try? read(data, isCancelled: { _ = counter.next(); return false })
        #expect(counter.count >= names.count + 1, "asked \(counter.count) times")
        for stop in 1...counter.count {
            let calls = ThreeMFReaderTests.Calls()
            #expect(throws: CancellationError.self) { try read(data, isCancelled: { calls.next() >= stop }) }
        }
    }
}
