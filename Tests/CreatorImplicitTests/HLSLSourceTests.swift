import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// The HLSL the generator writes (plan xp-c, X-C1 "follow macOS"): the same walk as the Metal source, statement for statement; the Metal
/// source itself unchanged by the dialect; the HLSL rules of the Global Constraints.
struct HLSLSourceTests {
    static var fixtures: [(name: String, solid: ImplicitSolid)] { GPUFixtures.all + LatticeFixtures.everyMapped + ImplicitFixtures.all }

    /// FNV-1a 64 of the UTF-8 text, as hex: stable across processes, unlike `Hasher`.
    static func digest(_ text: String) -> String { KernelSource.fnv1a(text) }

    /// Run once with `XP_RECORD_MSL_DIGESTS=1` before the generator gains its dialect, and paste the printed table into
    /// `MetalSourceDigests.swift`.
    @Test(arguments: fixtures.map(\.name))
    func theMetalSourceIsTheOneRecordedBeforeTheDialect(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        guard let source = (try? ImplicitCompiler.compile(solid))?.source else { return }
        if ProcessInfo.processInfo.environment["XP_RECORD_MSL_DIGESTS"] == "1" {
            print("MSLDIGEST \"\(name)\": \"\(Self.digest(source))\",")
        }
        #expect(MetalSourceDigests.table[name] == Self.digest(source), "\(name): the Metal source changed")
    }

    /// The `sdf` body: the lines between the function's opening line and its `return`.
    static func body(_ source: String, opening: String) -> [String] {
        let lines = source.split(whereSeparator: \.isNewline).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(opening) }) else { return [] }
        let rest = lines[(start + 1)...]
        guard let end = rest.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("return ") }) else { return [] }
        return Array(rest[..<end]) + [rest[end]]
    }

    /// MSL's spellings turned into HLSL's: `e.P[k]` → `P(k)`, `e.I[k]` → `I(k)`, a library call's `(e, ` → `(`.
    static func normalized(_ line: String) -> String {
        line.replacing(/e\.P\[(\d+)\]/) { "P(\($0.1))" }
            .replacing(/e\.I\[(\d+)\]/) { "I(\($0.1))" }
            .replacing("(e, ", with: "(")
    }

    @Test(arguments: fixtures.map(\.name))
    func theHLSLSdfIsTheMetalSdfStatementForStatementWithTheSameBuffers(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        let metal = try? ImplicitCompiler.compile(solid)
        let hlsl = try? ImplicitCompiler.compileHLSL(solid)
        #expect((metal == nil) == (hlsl == nil), "\(name): one dialect refused what the other took")
        guard let metal, let hlsl else { return }
        let metalBody = Self.body(metal.source, opening: "inline float sdf(").map(Self.normalized)
        let hlslBody = Self.body(hlsl.source, opening: "float sdf(float3 p) {")
        #expect(!metalBody.isEmpty && metalBody == hlslBody, "\(name): the bodies differ")
        #expect(hlsl.parameters == metal.parameters && hlsl.integers == metal.integers && hlsl.tables == metal.tables
            && hlsl.pool == metal.pool && hlsl.images == metal.images, "\(name): the buffers differ")
        #expect(hlsl.language == .hlsl && metal.language == .msl && metal.kernels.isEmpty)
        #expect(hlsl.source == hlsl.kernels[.evaluate]?.text)
    }

    @Test func solidsOfOneShapeHaveOneSourceAndDifferOnlyInTheirNumbers() throws {
        let small = try ImplicitCompiler.compileHLSL(.sphere(radius: 5))
        let large = try ImplicitCompiler.compileHLSL(.sphere(radius: 25))
        #expect(small.source == large.source && small.kernels[.evaluate]?.digest == large.kernels[.evaluate]?.digest)
        #expect(small.parameters != large.parameters)
    }

    /// No reduced precision, no 64-bit integers, no buffer size query, no driver trigonometry, in any kernel of any fixture.
    @Test(arguments: fixtures.map(\.name))
    func theGeneratedHLSLKeepsThePrecisionAndPortabilityRules(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        guard let compiled = try? ImplicitCompiler.compileHLSL(solid) else { return }
        let forbidden = [#"\bhalf\d?\b"#, #"\bmin16float"#, #"\bdouble\b"#, #"\bu?int64_t\b"#, #"GetDimensions"#,
                         #"(?<![A-Za-z])(sin|cos|tan|atan|atan2|sincos)\s*\("#,
        ]
        for source in compiled.kernels.values {
            for line in source.text.split(whereSeparator: \.isNewline) where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for pattern in forbidden {
                    #expect(line.range(of: pattern, options: .regularExpression) == nil, "\(name), \(source.kernel.rawValue): \(line)")
                }
            }
        }
    }

    /// Each kernel's `register(tN, space0)` and `register(uN, space1)` run from 0 without a gap, as many as `bindings` says; one entry
    /// point.
    @Test(arguments: fixtures.map(\.name))
    func eachKernelDeclaresItsBuffersInOrder(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        guard let compiled = try? ImplicitCompiler.compileHLSL(solid) else { return }
        for source in compiled.kernels.values {
            func slots(_ letter: String, _ space: Int) -> [Int] {
                source.text.split(whereSeparator: \.isNewline).compactMap { line in
                    let pattern = #"register\("# + letter + #"(\d+), space\#(space)\)"#
                    guard let range = line.range(of: pattern, options: .regularExpression) else {
                        return nil
                    }
                    return Int(line[range].dropFirst(9 + letter.count).prefix { $0.isNumber })
                }
            }
            #expect(slots("t", 0) == Array(0..<source.kernel.bindings.readOnly), "\(name), \(source.kernel.rawValue): read-only")
            #expect(slots("u", 1) == Array(0..<source.kernel.bindings.readWrite), "\(name), \(source.kernel.rawValue): read-write")
            #expect(source.text.components(separatedBy: "[numthreads(64, 1, 1)]").count == 2 && source.text.contains("void main(uint3 id"))
            #expect(source.text.contains("cbuffer Params : register(b0, space2)"))
        }
    }

    /// DXC drops a declared buffer nothing reads, shifting the slots after it: in every kernel of every shape, including those whose
    /// `sdf` touches neither packed buffer, each declared buffer is read by a function `main` calls, and `main` calls it.
    @Test(arguments: fixtures.map(\.name) + ["sphere", "box", "cylinder", "emptyUnion"])
    func everyDeclaredBufferIsReadByTheKernel(_ name: String) throws {
        let solids: [String: ImplicitSolid] = [
            "sphere": .sphere(radius: 5), "box": .box(halfSize: Vector3(2, 2.5, 3), cornerRadius: 0),
            "cylinder": .cylinder(radius: 3, halfHeight: 4), "emptyUnion": .union([], blend: .constant(0)),
        ]
        guard let solid = solids[name] ?? Self.fixtures.first(where: { $0.name == name })?.solid,
              let compiled = try? ImplicitCompiler.compileHLSL(solid) else { return }
        for source in compiled.kernels.values {
            let lines = source.text.split(whereSeparator: \.isNewline).map(String.init)
            let declared = lines.compactMap { line -> String? in
                let name = #"\w+(?= : register)"#
                guard line.contains("StructuredBuffer<"), let range = line.range(of: name, options: .regularExpression) else { return nil }
                return String(line[range])
            }
            guard let keeper = lines.firstIndex(where: { $0.hasPrefix("bool buffersAreKept()") }) else {
                Issue.record("\(name), \(source.kernel.rawValue): no buffer keep-alive")
                continue
            }
            let keeperBody = lines[keeper...].prefix { !$0.hasPrefix("}") }.joined(separator: " ")
            for buffer in ["floats", "ints"] where declared.contains(buffer) {
                #expect(keeperBody.contains("\(buffer)["), "\(name), \(source.kernel.rawValue): \(buffer) is never read")
            }
            let main = lines[(lines.firstIndex { $0.contains("void main(uint3 id") } ?? 0)...].joined(separator: " ")
            #expect(main.contains("if (buffersAreKept()) { return; }"), "\(name), \(source.kernel.rawValue): main skips the keep-alive")
        }
    }

    @Test func theUniformBlockIsSixteenWords() {
        #expect(MemoryLayout<KernelParameters>.stride == 64 && KernelParameters().bytes.count == 64)
        let members = HLSLShaderLibrary.prelude.split(separator: ";").filter { $0.contains("uint g") || $0.contains("float g") }
        #expect(members.count == 16)
    }
}
