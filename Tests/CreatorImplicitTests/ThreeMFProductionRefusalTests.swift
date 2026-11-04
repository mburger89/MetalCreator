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
        #expect(problem(data) == .malformedModel("it refers to object 9 in the part /3D/Objects/a.model, which doesn't have it."))
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
            #expect(reason == "the part 3D/Objects/a.model uses a different unit from the model.")
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

    // MARK: Cancellation, lookup and the rest

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

    @Test func theReaderAsksBeforeInflatingEachPart() throws {
        // The second part cannot be parsed (it starts with a NUL, which the parser refuses before it asks anything), so only the
        // reader's own ask before it can answer a cancellation that comes right after the first part has been read: the ask after
        // the last one a file of the first part alone makes.
        func package(parts names: [String]) -> Data {
            let wrappers = names.indices.map { Self.wrapper(10 + $0, Self.component(1, path: "/" + names[$0])) }.joined()
            // No build items, so nothing is placed after the parts are read (placing asks too): the read ends in `noTriangles`.
            let root = Self.root(wrappers, "")
            let texts = [Self.part(Package.object(id: 1, mesh: Self.cube)), "\u{0}<model/>"]
            return Self.package(root: root, parts: Array(zip(names, texts)))
        }
        let calls = ThreeMFReaderTests.Calls()
        #expect(throws: MeshImportProblem.noTriangles) {
            try read(package(parts: ["3D/Objects/0.model"]), isCancelled: { _ = calls.next(); return false })
        }
        let stop = calls.count + 1
        let both = package(parts: ["3D/Objects/0.model", "3D/Objects/1.model"])
        #expect(problem(both) != nil)
        let cancelling = ThreeMFReaderTests.Calls()
        #expect(throws: CancellationError.self) { try read(both, isCancelled: { cancelling.next() >= stop }) }
    }

    @Test func lookingUpNamesAsksAboutCancellation() throws {
        // One part spelled 1,000 ways (by case): the lookups are a loop of their own, which asks every 256 names.
        let letters = Array("3d/objects/a.model")
        func spelling(_ bits: Int) -> String {
            var flips = 0
            return String(letters.map { character -> Character in
                guard character.isLetter else { return character }
                defer { flips += 1 }
                return bits >> flips & 1 == 1 ? Character(character.uppercased()) : character
            })
        }
        func package(spellings: Int) -> Data {
            let wrappers = (0..<spellings).map { Self.wrapper(10 + $0, Self.component(1, path: "/" + spelling($0))) }.joined()
            let build = (0..<spellings).map { Package.item(10 + $0) }.joined()
            let part = Self.part(Package.object(id: 1, mesh: Self.cube))
            return Self.package(root: Self.root(wrappers, build), parts: [("3D/Objects/a.model", part)])
        }
        func asks(_ data: Data) throws -> Int {
            let calls = ThreeMFReaderTests.Calls()
            let meshes = try read(data, isCancelled: { _ = calls.next(); return false })
            #expect(!meshes.isEmpty)
            return calls.count
        }
        let one = try asks(package(spellings: 1))
        let many = try asks(package(spellings: 1_000))
        #expect(many - one >= 3, "\(many) asks against \(one)")
    }

    @Test func aPartsBuildSectionIsNotRead() throws {
        // The Production specification: only the root's build section counts; a part's items, even bad ones, are ignored.
        let part = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: "<item objectid=\"99\"/><item/>")
        let root = Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2))
        let meshes = try read(Self.package(root: root, parts: [("3D/Objects/a.model", part)]))
        #expect(meshes.count == 1 && meshes[0].mesh.triangleCount == 12)
    }

    @Test func aDamagedPartIsNamed() {
        let root = Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2))
        let vertex = "<object id=\"1\"><mesh><vertices><vertex x=\"1\" y=\"1\"/></vertices></mesh></object>"
        let broken = Self.package(root: root, parts: [("3D/Objects/a.model", Self.part(vertex))])
        #expect(problem(broken) == .malformedModel("in the part 3D/Objects/a.model, a vertex is missing a coordinate."))
        let notXML = Self.package(root: root, parts: [("3D/Objects/a.model", "<html/>")])
        #expect(problem(notXML) == .malformedModel("in the part 3D/Objects/a.model, it isn't a 3MF model."))
        // A part cut to 80 characters.
        let long = "3D/" + String(repeating: "n", count: 120) + ".model"
        let named = Self.package(root: Self.root(Self.wrapper(2, Self.component(1, path: "/" + long)), Package.item(2)),
                                 parts: [(long, "<html/>")])
        guard case .malformedModel(let reason)? = problem(named) else {
            Issue.record("a long part name")
            return
        }
        #expect(reason.hasPrefix("in the part 3D/" + String(repeating: "n", count: 77) + "…, "))
    }

    @Test func anEncryptedPartIsRefused() {
        let root = Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2))
        let items: [ZipReaderForeignTests.Item] = [
            .init(name: "_rels/.rels", body: Data(Package.relationships().utf8)),
            .init(name: "3D/3dmodel.model", body: Data(root.utf8)),
            .init(name: "3D/Objects/a.model", body: Data(Self.part(Package.object(id: 1, mesh: Self.cube)).utf8), flags: 1),
        ]
        #expect(problem(ZipReaderForeignTests.build(items, zip64: false)) == .encrypted)
    }

    @Test func anEmptyPathIsRefusedInPlainWords() {
        for path in ["", "/"] {
            let data = Self.package(root: Self.root(Self.wrapper(2, Self.component(1, path: path)), Package.item(2)), parts: [])
            guard case .malformedModel(let reason)? = problem(data) else {
                Issue.record("path '\(path)'")
                continue
            }
            #expect(reason.contains("empty path") || reason.contains("no name"), "\(reason)")
        }
    }

    // MARK: Same id in two files, and cycles

    @Test func theSameIdInTheRootAndAPartIsTwoObjects() throws {
        let part = Self.part(Package.object(id: 1, mesh: Self.triangle))
        let root = Self.root(Package.object(id: 1, mesh: Self.cube), Package.item(1)
            + "<item p:path=\"/3D/Objects/a.model\" objectid=\"1\"/>")
        let meshes = try read(Self.package(root: root, parts: [("3D/Objects/a.model", part)]))
        // Through a path it is the part's object; without one, the root's.
        #expect(meshes.map(\.mesh.triangleCount) == [12, 1])
        // The same through a component, in either order.
        let wrapped = Self.root(Package.object(id: 1, mesh: Self.cube)
            + Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model") + "<component objectid=\"1\"/>"), Package.item(2))
        let both = try read(Self.package(root: wrapped, parts: [("3D/Objects/a.model", part)]))
        #expect(both.map(\.mesh.triangleCount) == [13])
    }

    @Test func aPartsOwnComponentsStayInThePart() throws {
        // The part's object 7 places its own object 1 (a triangle); the root has an object 1 (a cube) that must not be taken.
        let part = Self.part(Package.object(id: 1, mesh: Self.triangle) + Package.assembly(id: 7, [(1, nil)]))
        let root = Self.root(Package.object(id: 1, mesh: Self.cube)
            + Self.wrapper(8, Self.component(7, path: "/3D/Objects/a.model")), Package.item(8))
        let meshes = try read(Self.package(root: root, parts: [("3D/Objects/a.model", part)]))
        #expect(meshes.map(\.mesh.triangleCount) == [1])
    }

    @Test func aCycleThroughARootPathIsRefused() {
        let cycles = [
            Self.wrapper(2, Self.component(2, path: "/3D/3dmodel.model")),
            Self.wrapper(2, Self.component(3, path: "/3D/3dmodel.model")) + Self.wrapper(3, Self.component(2, path: "/3d/3DMODEL.MODEL")),
        ]
        for resources in cycles {
            let data = Self.package(root: Self.root(resources, Package.item(2)), parts: [])
            #expect(problem(data) == .malformedModel("a component contains itself."))
        }
        // A part that contains itself, by its own component.
        let part = Self.part("<object id=\"1\"><components><component objectid=\"1\"/></components></object>")
        let looped = Self.package(root: Self.root(Self.wrapper(9, Self.component(1, path: "/a.model")), Package.item(9)),
                                  parts: [("a.model", part)])
        #expect(problem(looped) == .malformedModel("a component contains itself."))
    }

}
