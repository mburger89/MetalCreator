# 7c-core join checklist (Task 13 onward / merge of lane B)

Committed copy of the restore note that lived only in the uncommitted task-9-report.md.

## Restore after Task 7 (ImplicitMesher, lane B) is merged

Two Task 9 tests were omitted from this lane because they need `ImplicitMesher`. Until they return, nothing checks GPU mesh
quality against CPU mesh quality through `ImplicitEvaluators.make`. Add them back verbatim, then run
`swift test --filter 'ImplicitEvaluatorsTests|MetalEvaluatorsTests'` (expect 2 more tests than this lane: 6 and 3).

- [ ] `ImplicitEvaluatorsTests.aMeshFromTheCPUEngineIsClosedAndManifold` (last test in the suite, Tests/CreatorImplicitTests/ImplicitEvaluatorsTests.swift)

```swift
@Test func aMeshFromTheCPUEngineIsClosedAndManifold() async throws {
    let solid = ImplicitFixtures.all[5].solid
    let selection = await ImplicitEvaluators.make(for: solid, choice: .cpu)
    let mesh = try await ImplicitMesher(evaluator: selection.evaluator).mesh(solid, resolution: 0.5, quality: .preview)
    #expect(MeshTopology(mesh).isClosedManifold)
}
```

- [ ] `MetalEvaluatorsTests.aMeshFromTheGPUIsAsGoodAsOneFromTheCPU` (last test in the Metal suite, same file)

```swift
@Test func aMeshFromTheGPUIsAsGoodAsOneFromTheCPU() async throws {
    let solid = ImplicitFixtures.all[5].solid
    let gpu = await ImplicitEvaluators.make(for: solid, choice: .automatic)
    #expect(gpu.evaluator.engineName == "Metal")
    let fromGPU = try await ImplicitMesher(evaluator: gpu.evaluator).mesh(solid, resolution: 0.5, quality: .preview)
    let fromCPU = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: 0.5, quality: .preview)
    #expect(MeshTopology(fromGPU).isClosedManifold)
    #expect(abs(Double(fromGPU.triangleCount - fromCPU.triangleCount)) / Double(fromCPU.triangleCount) < 0.01)
    #expect(abs(fromGPU.signedVolume - fromCPU.signedVolume) / fromCPU.signedVolume < 0.002)
}
```

They use `ImplicitMesher(evaluator:).mesh(_:resolution:quality:)`, `ImplicitFixtures.all[5]`, `MeshTopology`, `signedVolume`, `CPUBatchEvaluator`.
