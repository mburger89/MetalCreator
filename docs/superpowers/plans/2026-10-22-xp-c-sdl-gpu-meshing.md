# xp-c: Implicit Evaluation and Meshing on SDL GPU Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Linux and Windows, 7c's implicit evaluation and marching-cubes meshing run on the GPU through MetalUI's SDL_GPU compute, built the way macOS's `MetalImplicitEngine` is: one generated kernel source per solid shape, compiled while the app runs, pipelines cached by source; held to the CPU reference by the same suites and tolerances as Metal. macOS is unchanged.

**Architecture:** `ImplicitCompiler.Generator` gains a dialect (`ShaderDialect.msl`, the default and byte-for-byte today's output, pinned by recorded digests; `.hlsl`), so one walk of the tree writes the Metal source and the HLSL source statement for statement, with the same five buffers. `HLSLShaderLibrary` and `HLSLMeshShaderLibrary` are the Swift-text HLSL twins of `ImplicitShaderLibrary` and `ImplicitMeshShaderLibrary` (line-for-line ports, plus SDL_GPU's needs: `mesh_clear` because SDL_GPU has no buffer fill, and a separate source per kernel because an SDL_GPU shader has one entry point). `HLSLImplicitEngine` is the portable actor mirroring `MetalImplicitEngine`: `prepare` makes the evaluation pipeline of a shape once, the six meshing pipelines are made on a shape's first mesh, pipelines are cached by source (64 kept, least recently used dropped), a solid's buffers by identity (8 kept), and evaluation and meshing are the same dispatches with the same tuning shape. It talks to an `ImplicitComputeBackend` that makes buffers, makes a pipeline from a `KernelSource`, and runs one batch at a time. `SDLComputeBackend` (Linux and Windows, an owned headless `SDLGPUDevice`) gets its shader bytes from a `SDLKernelProvider`: **at run time from MetalUI's compiler (gap XP-G25, which MetalUI is building on `feat/sdl-gpu-runtime-shaders`; tasks 11 and 12 wait for it)**, and, before that and in the tests, from kernels the build-time SDL_shadercross compiled offline in the Linux image (`scripts/linux-test.sh kernels`: every fixture's generated sources exported, compiled to SPIR-V, DXIL and MSL into `.build/generated-kernels`). So the generated HLSL is compiled by DXC and run against the CPU on lavapipe, and, through the MSL, on this Mac's GPU (`MSLComputeBackend`, test support), **before XP-G25 lands**. Until task 11 the app's engine off macOS stays the CPU (E7 holds); task 11 makes `HLSLImplicitEngine.sdl` the platform's engine, falling back to the CPU with the reason shown when the compiler library is missing or a source does not compile.

**Tech Stack:** Swift 6.4 strict concurrency, Swift Testing, MetalUI at the CI pin `ff0db06e9cdb8d11de8ee2210f695eb08da271fe` (`MetalUISDLGPU`; every name used before task 11 checked at the pin by task 0; the layer is the same at MetalUI master `63feea05`), then the commit that answers XP-G25 (task 11 bumps the pin), HLSL through SDL_shadercross commit `1ff05bec573988a98ef9e0260b4da44f512b8367` (`scripts/shadercross.env`, unchanged: the offline test compile now, MetalUI's run-time compiler later), Metal (macOS), Mesa lavapipe (Linux) and Direct3D 12 WARP (Windows) in CI.

**Spec:** `docs/superpowers/specs/2026-10-13-cross-platform-design.md` row XP-G2 ("Portable compute (SDL GPU compute) for 7c's implicit engine", after xp-3) and errata E1 to E7 (E7 ends "Implicit evaluation and meshing stay on the CPU off macOS (xp-c)"); `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §4.1 to §4.3, §6, §7 and Errata D11 (the CPU is a complete engine; GPU behind a protocol), D12 (export streams, bricks meshed in a fixed order), D13 (an SDL3 GPU compute implementation follows; CPU the reference and fallback; same topology, vertices within 1e-4 mm), D15 (mesher alone 1e-4 mm; whole pipeline surfaces 1e-4 mm, vertices 2e-3 mm), D17 (surface allowance 1e-4 mm ÷ |∇f|), D20 (the amended allowance, including 7× for the Face-mapped Voronoi struts on a cylinder, an open item); the parent spec with all its Errata. This plan adds erratum **E8** to the cross-platform spec and **D21** to the implicit spec (task 10; tasks 11 and 12 finish their last sentences).

**Branch:** `xp-c` (worktree `../MetalCreator-xp-c`), from master `7a010ec`. MetalUI is `../MetalUI`, **read-only**.

**Revision of 2026-10-22 (user rulings).** **X-C1 is decided: Linux and Windows follow macOS** — per-solid code generation and compilation while the app runs, an HLSL generator mirroring `ImplicitCompiler.Generator`, pipelines cached by source as on Metal. The bytecode interpreter of the first revision and its limits (32 values, 8 points, 4,096 steps) are gone. MetalUI gap **XP-G25** (a run-time HLSL compute compiler and pipelines from bytes) was sent by the coordinator; the tasks that need it are last and marked. **X-C3 is decided: exports byte-identical, as on macOS** — and macOS's exports already are: an export streams through `StreamingMesher`, which meshes on the CPU over the GPU's values in a fixed order and never calls `meshBricks` (D12; `StreamedExport.swift`: "the CPU mesher still builds the triangles"), so its bytes depend only on the values, which a GPU computes the same way every run. The interpreted engine's canonical sort is dropped; the new engine mirrors Metal exactly, its `meshBricks` order being the threads' (previews only), and no macOS byte changes. X-C5 is still pending. XP-G23 and XP-G24 are being built by MetalUI on `feat/sdl-gpu-device-info` (planned: `SDLGPUDevice.adapterName: String?`, `isSoftwareRasterizer: Bool`, a `limits` struct); MetalUI confirms `SDLGPUDevice.make(debug:preferring:)` is nonisolated, headless and owns its device, safe off the main thread once `SDLPlatform` has initialised video on the main thread (the app does; a headless test process makes its device without a platform, as xp-3's `SDLTestDevice` already does), and that nothing may block inside a surface draw (the engine never draws).

## User decisions

**X-C1. How a solid runs on SDL_GPU. DECIDED (2026-10-22): follow macOS.** Per-solid HLSL generated by the same walk as Metal's MSL, compiled at run time (MetalUI XP-G25), pipelines cached by source hash. The interpreter of the first revision is not built.

**X-C2. Where the HLSL runs in tests. Recommended (a), unchanged in spirit.**
- (a) **The generated HLSL is compiled offline by the build-time SDL_shadercross in the Linux image and runs against the CPU on lavapipe (SPIR-V) and on this Mac's GPU (its MSL, `MSLComputeBackend`, test support)**, from task 3 on; after XP-G25 Linux and Windows compile it at run time as the app does, and the offline path stays for the Mac. macOS's app keeps `MetalImplicitEngine`.
- (b) Wait for XP-G25 before running any generated HLSL: simpler, but the generator would be untested on a GPU until MetalUI lands.

**X-C3. Mesh order and export bytes. DECIDED (2026-10-22): byte-identical exports, the same as macOS.** What this plan pins, and what it cannot:
- **Same machine, same driver, same build: byte-identical, every run.** Exports stream through `StreamingMesher` (CPU triangles in the plan's fixed brick order over the engine's values) and `STLFileWriter`/`ThreeMFWriter`/`ZipWriter` (fixed dates); the GPU's values are the same bits every run (no atomics touch a value; a point's value does not depend on its batch, which `StreamingMesherGPUTests` already pins on Metal). Pinned on every engine by task 7's `exportingTheSameSolidTwiceGivesTheSameBytes`.
- **Across machines, drivers or backends: not promised.** Metal, Vulkan and Direct3D 12 compile the same arithmetic differently (fused multiply-adds, `sqrt` and division precision, the order a driver evaluates an expression in), so a value can differ in its last bit or two between a Mac and a Linux box, or between two Linux GPUs; a vertex then moves by up to D15's tolerances and the bytes differ. What holds across them is D11 and D15: the same topology, values within 1e-4 mm, vertices within 2e-3 mm. The CPU engine is the same bits wherever the same Swift build runs on the same architecture.
- `meshBricks` (the preview and the in-memory mesh the mesh tools read) keeps Metal's order: the set is fixed, the order is the threads' (D13), on both engines. No sort is added and no macOS byte changes.

**X-C4. What the person sees when the GPU engine cannot run. Recommended: (a), revised for run-time compilation.**
- (a) **No SDL_GPU device: the CPU, silently** (D11's machine without a GPU engine). **The compiler library missing (XP-G25's named error, listing the paths it tried) or a pipeline refused: the CPU with "Running on the CPU"**, the reason in the selection's diagnostic and in `--self-test`. **A solid whose generated source does not compile** (DXC's diagnostic text) **or has no GPU form** (a distance to a profile): the CPU with the warning, as on Metal. A request beyond the 128 MiB buffer cap or the 32-bit edge keys: that request on the CPU mesher, silently, as on Metal.
- (b) Silent CPU in every case.

**X-C5. Software devices (lavapipe, WARP). PENDING with the user. Recommended (a).**
- (a) Tests and CI run on them (`XP_REQUIRE_GPU=1`); the app uses whatever device SDL_GPU picks until XP-G23 is adopted (task 13), then prefers the CPU on a software device unless task 9's rows show lavapipe faster than the CPU engine.
- (b) Always use a software device.

**X-C6. Precision. Recommended (a).** Float only, never `half`; the HLSL library's own sine, cosine and arctangent (Cody–Waite, Cephes; Vulkan promises only 2^-11 absolute for `sin`, Metal's engine uses `precise::`), and the noise's 64-bit hash in 32-bit word pairs (`uint64_t` needs `shaderInt64`, which SDL_GPU neither enables nor reports). The tolerances are the 7c spec's, unchanged.

**X-C7. Performance budgets and compile cost. Recommended (a).**
- (a) No budget in CI (lavapipe and WARP are CPU rasterizers): rows x-1 (first pass, warm pipelines) and x-2 (a thickness edit: no recompile, as on Metal) per engine; **x-3, the compile cost of one new shape** (the evaluation pipeline, then the six meshing ones), and **x-4, the first-run latency** (a new shape's first preview pass, compile included) are recorded: offline shadercross times in task 9, MetalUI's run-time compiler in task 11. x-1h (the generated HLSL as MSL on this Mac's GPU) is held to i-1's 1 s. Human check XP-27 asks for i-1 and i-2 on a desktop GPU and records x-3 and x-4 there; **proposed** budget for x-4 on a desktop GPU: under 2 s (DXC compiles a kernel of about 1,000 lines in a few hundred milliseconds by MetalUI's estimate, to be measured), confirmed by the user when task 11's numbers exist.

**X-C8. Names a person sees.** The badge and inspector say "Vulkan" (Linux) and "Direct3D 12" (Windows), as "Metal" on a Mac; the device name is the adapter's once XP-G23 is adopted.

No saved file format, saved setting or document changes.

## Global Constraints

- **The base is master `7a010ec`**; rebase if master moves and take its counts as the baseline.
- **MetalUI is never modified** (no edit, checkout, stash, commit or build product in `../MetalUI`; its tools are built with `--scratch-path` outside it). A gap goes in `docs/metalui-gaps.md` and is never worked around: no raw `SDL_` call, no `dlopen` of shadercross by MetalCreator (XP-G25 owns loading it).
- Swift 6 strict concurrency; Swift Testing; one type per file; no force unwraps or force `try`; no GCD; no `String(format:)` or legacy formatters; `swiftlint lint --strict` clean before every commit.
- **macOS is unchanged in behaviour and in bytes.** `ImplicitCompiler`'s MSL output is the same text for every fixture (task 1 records digests before the generator changes and pins them); `MetalImplicitEngine`, `ImplicitShaderLibrary` and `ImplicitMeshShaderLibrary` are not edited; macOS builds no SDL and links no shadercross.
- **Portability:** no Metal outside `#if canImport(Metal)` files named `Metal*.swift` (the test backend `MSLComputeBackend.swift` likewise); no `MetalUISDLGPU` outside `Sources/CreatorImplicit/SDL/SDL*.swift`, each wholly under `#if canImport(MetalUISDLGPU)`; no `SDLGPU…` type named elsewhere (`ImplicitPortabilityTests`).
- **Generated HLSL rules** (`HLSLSourceTests`): no `half`, `min16float`, `double`, `uint64_t`, `int64_t`, `GetDimensions` or driver trigonometry (`sin`, `cos`, `tan`, `atan`, `atan2`); read-only storage `register(tN, space0)` and read-write `register(uN, space1)` from 0 without gaps in the order `ImplicitKernel.bindings` lists, every declared buffer used (DXC drops an unused one and the slots shift); one `cbuffer Params : register(b0, space2)`; entry point `main`, `[numthreads(64, 1, 1)]`.
- **SDL_GPU compute rules** (`SDL_gpu.h`, "A VERY IMPORTANT NOTE"): a dispatch that reads what an earlier one wrote is in a compute pass of its own (the backends give each dispatch its own pass); the engine never calls a blocking verb (`submitBatchSynchronously`, `waitBlocking`, `downloadSynchronously`, `waitForIdle`) and never runs inside a surface draw; at most 65,535 groups of 64 threads a dispatch, storage buffers of at most 128 MiB until XP-G24.
- **The Windows Swift 6.4 compiler** (xp-1, xp-2): heavy loops in synchronous helpers, never holding a loop's locals across an `await`; no typed-throws closures to generic helpers; every `async` method taking the `progress` closure is `@_optimize(none)` with a comment (master's `OccupancyGrid.fill(lipschitz:awaiting:)`); if an `async` loop still asserts, rewrite it as recursion over the index. Every task that changes code Windows compiles must pass CI's `swift build -c release` ("Build release (for the zip)"); the local check is `TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release` (it compiles what macOS compiles, so the `SDL*.swift` files are CI's).
- A full `swift test` passes only if it exits 0, no line says "recorded an issue" or "failed after", and there are **12 "Test run with" lines** on macOS, Linux and Windows (xp-c adds no test target; the kernel export of task 3 runs as its own filtered invocation, not counted).
- Linux: `scripts/linux-test.sh` with **`XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c`** on every call; Windows: CI on the pushed `xp-c` branch.
- **Processes:** never `pkill`, `killall` or `xargs kill` swift, swift-test, swift-build, swift-frontend or xctest; kill only PIDs you started; stop Docker only by this track's container names (`xp-c-linux`, `xp-c-linux-clean`).
- **Line endings:** split text a test reads with `split(whereSeparator: \.isNewline)`.
- **Third-party code:** before task 12, none added. Task 12 ships SDL_shadercross, DXC (and `dxil`), SPIRV-Cross and SPIRV-Tools shared libraries in the packages, as XP-G25's `packaging.md` §4a prescribes; that is new third-party code **in the app**, not only a build tool, and needs the user's yes (asked in task 12, step 1).

## Review Focus

1. **A solid whose generated HLSL DXC refuses** (a construct the MSL accepted, an identifier clash, a too-deep expression). It must run on the CPU with "Running on the CPU" and the diagnostic, never trap. Task 3 compiles every fixture's sources offline (a refusal fails `GeneratedKernelBuildTests` naming the fixture); task 11, `HLSLRuntimeCompileTests.aSourceTheCompilerRefusesRunsOnTheCPUWithItsDiagnostic`.
2. **A package without the compiler libraries.** The app runs, meshes on the CPU, says "Running on the CPU", and `--self-test` names the missing library and the paths tried. Task 11, `HLSLRuntimeCompileTests.aMissingCompilerLibraryIsBrokenAndNamesWhatItTried`; task 12's clean-Ubuntu and zip checks.
3. **The first preview of a new shape.** Compiling the evaluation pipeline, then the six meshing ones, is the user's wait: it must happen off the main actor, once per shape (an edit of a number never recompiles), and a second shape compiled meanwhile must not compile the first again. Task 4, `HLSLEngineTests.shapesShareOnePipelineAndANumberEditRecompilesNothing`; task 6, `meshingASecondTimeCompilesNoMeshPipeline`; task 11, x-4.
4. **A request past the buffer cap or the 32-bit keys, and a cancel during a long mesh.** The CPU mesher takes the request; a cancel ends at the next batch and the next mesh runs. Task 7's limit and cancel tests.
5. **The cut and the axis of a mapped lattice, and noise at negative lattice coordinates.** Task 4, `HLSLEngineTests.theAngleOnTheCutAndAtTheAxisAgreesWithTheCPU`; `GPUAgreementTests`' noise fixtures sample from -18 to 18 mm.
6. **The same export twice.** Byte-identical on one machine (X-C3). Task 7, `StreamingMesherGPUTests.exportingTheSameSolidTwiceGivesTheSameBytes`; human check XP-28.

---

## Shared files

| File | Edited by xp-c | The second merge must keep |
|---|---|---|
| `Package.swift` | `metalUISDL`, `metalUISDLGPU` for `CreatorImplicit` and its tests (task 5) | both sides' lists |
| `Sources/CreatorImplicit/Metal/ImplicitCompiler.swift`, `+Mapping.swift` | the dialect: `number`, `integer` and the environment argument spelled by `dialect` (task 1); MSL text unchanged, pinned | a 7c follow-up's new case writes through the dialect too |
| `Sources/CreatorImplicit/Metal/CompiledImplicit.swift` | `language`, `kernels` (task 1) | both |
| `scripts/linux-test.sh` | a `kernels` verb; `test` and `all` export and compile the kernels first (task 3) | every verb |
| `scripts/linux/Dockerfile`, `scripts/install-shadercross.ps1`, `.github/workflows/xp.yml`, packaging scripts, `docs/packaging.md` | task 12 only (after XP-G25) | xp-3's shadercross stage and caches |
| `Sources/CreatorApp/SelfTest.swift` | the implicit engine's check (task 8; MetalUI's `selfTest()` in task 12) | both checks |
| docs (gaps, human checks, performance, specs, `CLAUDE.md`) | tasks 0, 9, 10, 11, 12, 13 | both sides; next free: XP-G26, XP-30, E9, D22 |
| `GPUAgreementTests`, `GPUMeshAgreementTests`, `StreamingMesherGPUTests` | run over every engine (tasks 4, 7) | the fixtures and allowances |

## Key decisions (made by this plan)

- **One generator, two dialects.** `ShaderDialect` spells a parameter (`e.P[k]` / `P(k)`), an integer (`e.I[k]` / `I(k)`) and a library call's environment argument (`e, ` / nothing). Everything else the generator writes is valid in both languages (`float3`, `length`, `dot`, `max`, `abs`, `?:`, `1e30`), so the HLSL `sdf` is the MSL `sdf` statement for statement, which `HLSLSourceTests` checks after a mechanical normalisation.
- **One source per kernel, cached by digest.** SDL_GPU compiles one entry point per shader, so where Metal compiles a shape's one library with five kernels, the HLSL side writes one source per kernel: `implicit_evaluate`, `mesh_sample` and `mesh_place` contain the shape's `sdf`; `mesh_clear`, `mesh_classify`, `mesh_number` and `mesh_emit` do not call it, so their text is the same for every shape and the pipeline cache (keyed by a stable digest of the text) makes them once. The digest is FNV-1a 64 of the UTF-8 text (`KernelSource.digest`), stable across processes, so the offline export names its files by it.
- **The buffers are Metal's, packed in two.** floats = parameters ++ pool ++ images, ints = integers ++ tables, the bases in the uniform block, so `mesh_place` declares five read-only storage buffers, not eight.
- **One uniform block, `KernelParameters`** (16 four-byte words) for every kernel: Metal's `count` and `MeshParams` and the bases.
- **An owned, headless device, made on first use inside the engine** (never on the main actor); compile calls run where XP-G25's thread-safety notes allow, never inside a surface draw.
- **Until task 11 the app's engine off macOS is the CPU** (`platformDefault` stays `nil` there): the engine exists, is tested on lavapipe and the Mac, and is not shown to a person before it can compile at run time.

## File structure

**Portable, `Sources/CreatorImplicit`**

| File | Responsibility |
|---|---|
| `Metal/ShaderDialect.swift` | `.msl` / `.hlsl`: how the generator spells a parameter, an integer and the environment |
| `Metal/ImplicitCompiler.swift`, `+Mapping.swift` (changed) | the walk writes through the dialect; `compileHLSL(_:)` |
| `Metal/CompiledImplicit.swift` (changed) | `language`, `kernels` (the HLSL kernel sources by `ImplicitKernel`) |
| `HLSL/HLSLShaderLibrary.swift`, `+Math.swift`, `+Lattices.swift` | the HLSL twin of `ImplicitShaderLibrary` (text): prelude, accurate math, 64-bit words, core, lattices |
| `HLSL/HLSLMeshShaderLibrary.swift` | the HLSL twin of `ImplicitMeshShaderLibrary` plus `mesh_clear`, one source per kernel |
| `HLSL/HLSLKernels.swift` | builds a solid's seven `KernelSource`s |
| `Compute/ImplicitKernel.swift`, `KernelParameters.swift`, `KernelSource.swift` | the kernels and their bindings; the uniform block; a kernel's text and digest |
| `Compute/ImplicitComputeBackend.swift`, `ComputeBatch.swift`, `ComputeBytes.swift` | the backend protocol, batches, synchronous byte helpers |
| `Compute/HLSLImplicitEngine.swift`, `+Meshing.swift`, `HLSLMeshRun.swift` | the actor mirroring `MetalImplicitEngine` and its meshing |
| `GPU/ImplicitEngineAvailability.swift`, `ImplicitGPUEngine.swift`, `ImplicitEvaluators.swift`, `ImplicitGPUEngines.swift`, `ImplicitEngineCheck.swift` | availability, selection, the platform's engine, the self-test's question |

**SDL, `Sources/CreatorImplicit/SDL`** (wholly under `#if canImport(MetalUISDLGPU)`): `SDLComputeBackend.swift`, `SDLComputeRecording.swift`, `SDLComputeBuffer.swift`, `SDLComputePipeline.swift`, `SDLKernelProvider.swift` (the protocol and `SDLPrecompiledKernels`), `SDLRuntimeKernels.swift` (task 11), `SDLImplicitEngine.swift` (task 11).

**Tests, `Tests/CreatorImplicitTests`**: `MetalSourceDigests` (support, recorded), `HLSLSourceTests`, `GeneratedKernelExport`, `GeneratedKernelBuildTests`, `HLSLEngineTests`, `HLSLMeshingTests`, `SDLComputeBackendTests`, `ImplicitGPUAvailabilityTests`, `ImplicitEngineCheckTests`, `MetalEngineDispatchTests` (moved), `ImplicitBenchHLSL`, `HLSLRuntimeCompileTests` (task 11); support `GeneratedKernels.swift`, `MSLComputeBackend.swift`, `MSLComputeBuffer.swift`, `GPUEnginesUnderTest.swift`; changed `GPUAgreementTests`, `GPUMeshAgreementTests`, `StreamingMesherGPUTests`, `ImplicitEvaluatorsTests`, `GPUBatchEvaluatorTests`, `ImplicitPortabilityTests`, `StubGPUEngine`.

---

## Tasks

### Task 0: Baselines, the three MetalUI gaps, a check of the API used before XP-G25

**Files:** Modify `docs/metalui-gaps.md`.

**Interfaces:** Produces the baselines; gap numbers XP-G23, XP-G24, XP-G25.

- [ ] **Step 1: Branch and pin.**
```bash
cd /Users/maxburger/Developer/MetalCreator-xp-c
git log --oneline -3; grep -n "METALUI_COMMIT:" .github/workflows/xp.yml     # ff0db06e…
git -C ../MetalUI diff --stat ff0db06e 63feea05 -- Backends/SDL/Sources/MetalUISDLGPU Sources/MetalUIShaderCompile   # nothing
```
- [ ] **Step 2: The names used before task 11 exist at the pin** (each count ≥ 1; a 0 is a MetalUI change to report, not to work around):
```bash
cd ../MetalUI
for n in "static func make(debug" "func makeBuffer(size" "func makeTransferBuffer(size" "func compileComputePipeline" "func submitBatch(_ record" "lastFailure"; do
  git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUDevice.swift | grep -c "$n"; done
for n in "func beginComputePass(readWrite" "func copy(_ source: SDLGPUTransferBuffer" "func copy(_ source: SDLGPUBuffer, range" "func bind(readOnly" "func push(uniform" "func dispatch(x"; do
  git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUCompute.swift | grep -c "$n"; done
git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUShaderLibrary.swift | grep -c "public init(directory: URL) throws"
git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUFence.swift | grep -c "public func wait() async"
```
- [ ] **Step 3: Baselines.** `swift test 2>&1 | tee .build/xp-c-baseline-mac.log | grep -c "Test run with"` (12), the total and `CreatorImplicitTests`' count; `XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test 2>&1 | tail -3` (12). Record them in the commit message.
- [ ] **Step 4: Log the gaps.** Summary rows after XP-G22:
```markdown
| XP-G23 | The SDL_GPU adapter's name, and whether it is a software rasterizer | MetalUI (SDL GPU layer; `feat/sdl-gpu-device-info`) | 🔄 being built (planned `SDLGPUDevice.adapterName`, `isSoftwareRasterizer`); until adopted the implicit engine names the driver and uses a software device |
| XP-G24 | SDL_GPU compute limits: largest storage buffer binding, most thread groups | MetalUI (SDL GPU layer; `feat/sdl-gpu-device-info`) | 🔄 being built (planned `SDLGPUDevice.limits`); until adopted 128 MiB and 65,535 |
| XP-G25 | A run-time HLSL compute compiler (SDL_shadercross's library, DXC) and compute pipelines from bytes | MetalUI (SDL GPU layer; `feat/sdl-gpu-runtime-shaders`) | 🔄 being built; until adopted the implicit engine off macOS is tested on kernels compiled offline and the app evaluates on the CPU |
```
and a section at the end of the file:
```markdown
## Hit by implicit evaluation and meshing on SDL GPU (xp-c), 2026-10-22

Plan `docs/superpowers/plans/2026-10-22-xp-c-sdl-gpu-meshing.md`, MetalUI pin `ff0db06e` (its SDL_GPU layer equals master `63feea05`). XP-G2 (portable
compute, MetalUI S5) is what the engine dispatches on. The user ruled that Linux and Windows follow macOS: one generated source per solid shape, compiled
while the app runs, pipelines cached by source.

- **XP-G23. Adapter name, software rasterizer.** The inspector names the device that meshed (Metal: `MTLDevice.name`), and the app may prefer its CPU
  engine on lavapipe or WARP (xp-c X-C5, pending). `SDLGPUDevice` gives `driver` only; SDL 3.4 has `SDL_GetGPUDeviceProperties`
  (`SDL_PROP_GPU_DEVICE_NAME_STRING`, `…_DRIVER_NAME_STRING`, `…_DRIVER_INFO_STRING`). Asked: `adapterName: String?`, `isSoftwareRasterizer: Bool`.
- **XP-G24. Compute limits.** Metal's engine sizes its edge table by `maxBufferLength`; SDL_GPU reports nothing, so xp-c assumes Vulkan's guaranteed
  2^27-byte storage range and 65,535 groups (an edge table of at most 2^25 slots against Metal's 2^27). Asked: `SDLGPUDevice.limits`, or MetalUI's
  statement of the minimums every SDL_GPU backend guarantees.
- **XP-G25. Run-time HLSL compute compilation.** `MetalImplicitEngine` compiles each shape's MSL with `MTLDevice.makeLibrary(source:)` while the app runs;
  on SDL_GPU `SDLGPUShaderBlob` has no public initializer and loads only from a directory compiled at build time, so a generated source cannot become a
  pipeline. Asked (the coordinator's message to MetalUI, 2026-10-22): (1) a nonisolated API turning HLSL compute source (an entry point, defines) into
  the device's format (SPIR-V on Vulkan, DXIL on Direct3D 12, MSL on Metal) with compute reflection, over SDL_shadercross's library API and DXC; (2) a
  compute pipeline from those bytes; (3) compile errors thrown with DXC's text; (4) packaging notes for the shadercross, DXC, SPIRV-Cross and
  SPIRV-Tools shared libraries in a tarball, an AppImage and a zip, their licences, and a self-test hook; (5) compile times. MetalUI's planned shape
  (`feat/sdl-gpu-runtime-shaders`, names provisional): the library is loaded at run time (`dlopen`/`LoadLibrary`), an app without it builds and runs and
  a missing one throws a named error listing the paths tried; failures never trap; `packaging.md` §4a lists what to ship and adds `selfTest()`; compile
  times measured at about 200, 1,000 and 2,000 lines; nothing is published, apps build shadercross and DXC themselves; thread safety documented, calls
  serialized if needed. Meanwhile xp-c compiles the generated sources offline in tests only, and the app evaluates on the CPU off macOS.
```
- [ ] **Step 5: Commit** (`docs: log MetalUI gaps XP-G23 to XP-G25 for xp-c`, the baselines in the body, the two trailers below).

Every commit in this plan ends with:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS
```

---

### Task 1: One generator, two dialects; the HLSL library; the evaluation kernel's source

Portable; tested on every platform without a GPU.

**Files:**
- Create: `Sources/CreatorImplicit/Metal/ShaderDialect.swift`, `Sources/CreatorImplicit/HLSL/HLSLShaderLibrary.swift`, `HLSLShaderLibrary+Math.swift`, `HLSLShaderLibrary+Lattices.swift`, `Sources/CreatorImplicit/Compute/ImplicitKernel.swift`, `KernelParameters.swift`, `KernelSource.swift`
- Modify: `Sources/CreatorImplicit/Metal/ImplicitCompiler.swift`, `ImplicitCompiler+Mapping.swift`, `CompiledImplicit.swift`
- Test: `Tests/CreatorImplicitTests/Support/MetalSourceDigests.swift`, `Tests/CreatorImplicitTests/HLSLSourceTests.swift`

**Interfaces:**
- Produces: `enum ShaderDialect { case msl, hlsl }`; `ImplicitCompiler.compileHLSL(_ solid:) throws(ImplicitCompileError) -> CompiledImplicit` (`language == .hlsl`, `source` = the evaluation kernel's text, `kernels[.evaluate]` set; task 2 fills the rest); `public enum ShaderLanguage { case msl, hlsl }`, `CompiledImplicit.language`, `CompiledImplicit.kernels: [ImplicitKernel: KernelSource]`; `public enum ImplicitKernel: String, CaseIterable, Sendable` (`evaluate = "implicit_evaluate"`, `clear = "mesh_clear"`, `sample = "mesh_sample"`, `classify = "mesh_classify"`, `number = "mesh_number"`, `place = "mesh_place"`, `emit = "mesh_emit"`), `bindings` evaluate (3, 1), clear (0, 1), sample (4, 1), classify (3, 2), number (1, 2), place (5, 2), emit (5, 2), `usesSDF` (evaluate, sample, place), `threadsPerGroup = 64`; `public struct KernelParameters` (16 words, `bytes`); `public struct KernelSource: Sendable, Hashable { kernel, text, digest }`.

- [ ] **Step 1: Record the MSL digests before anything changes.**

`Tests/CreatorImplicitTests/HLSLSourceTests.swift`, first test only:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// The HLSL the generator writes (plan xp-c, X-C1 "follow macOS"): the same walk as the Metal source, statement for statement; the Metal source itself
/// unchanged by the dialect; the HLSL rules of the Global Constraints.
struct HLSLSourceTests {
    static var fixtures: [(name: String, solid: ImplicitSolid)] { GPUFixtures.all + LatticeFixtures.everyMapped + ImplicitFixtures.all }

    /// FNV-1a 64 of the UTF-8 text, as hex: stable across processes, unlike `Hasher`.
    static func digest(_ text: String) -> String { KernelSource.fnv1a(text) }

    /// Run once with `XP_RECORD_MSL_DIGESTS=1` before the generator gains its dialect, and paste the printed table into `MetalSourceDigests.swift`.
    @Test(arguments: fixtures.map(\.name))
    func theMetalSourceIsTheOneRecordedBeforeTheDialect(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        guard let source = (try? ImplicitCompiler.compile(solid))?.source else { return }
        if ProcessInfo.processInfo.environment["XP_RECORD_MSL_DIGESTS"] == "1" { print("MSLDIGEST \"\(name)\": \"\(Self.digest(source))\",") }
        #expect(MetalSourceDigests.table[name] == Self.digest(source), "\(name): the Metal source changed")
    }
}
```
Before step 1 can build, `KernelSource.fnv1a` must exist: write `Sources/CreatorImplicit/Compute/KernelSource.swift` (step 4) first, then run on the **unmodified** generator:
```bash
XP_RECORD_MSL_DIGESTS=1 swift test --filter "CreatorImplicitTests.HLSLSourceTests/theMetalSourceIsTheOneRecordedBeforeTheDialect" 2>&1 | grep MSLDIGEST | sed 's/.*MSLDIGEST //' | sort -u
```
and write `Tests/CreatorImplicitTests/Support/MetalSourceDigests.swift`:
```swift
/// The Metal source of every GPU fixture, as `KernelSource.fnv1a` digests, recorded on master `7a010ec`'s generator before plan xp-c gave it a
/// dialect (`HLSLSourceTests`): the MSL a Mac compiles must not change by a byte. A 7c change that alters the MSL on purpose records the table again.
enum MetalSourceDigests {
    static let table: [String: String] = [
        // the printed lines, pasted
    ]
}
```
Run the test again: PASS. Commit this step alone (`test(implicit): record the Metal source digests before the HLSL dialect`).

- [ ] **Step 2: Write the remaining failing tests.**

Add to `HLSLSourceTests`:
```swift
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
                         #"(?<![A-Za-z])(sin|cos|tan|atan|atan2|sincos)\s*\("#]
        for source in compiled.kernels.values {
            for line in source.text.split(whereSeparator: \.isNewline) where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for pattern in forbidden {
                    #expect(line.range(of: pattern, options: .regularExpression) == nil, "\(name), \(source.kernel.rawValue): \(line)")
                }
            }
        }
    }

    /// Each kernel's `register(tN, space0)` and `register(uN, space1)` run from 0 without a gap, as many as `bindings` says; one entry point.
    @Test(arguments: fixtures.map(\.name))
    func eachKernelDeclaresItsBuffersInOrder(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        guard let compiled = try? ImplicitCompiler.compileHLSL(solid) else { return }
        for source in compiled.kernels.values {
            func slots(_ letter: String, _ space: Int) -> [Int] {
                source.text.split(whereSeparator: \.isNewline).compactMap { line in
                    guard let range = line.range(of: #"register\("# + letter + #"(\d+), space\#(space)\)"#, options: .regularExpression) else {
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

    @Test func theUniformBlockIsSixteenWords() {
        #expect(MemoryLayout<KernelParameters>.stride == 64 && KernelParameters().bytes.count == 64)
        let members = HLSLShaderLibrary.prelude.split(separator: ";").filter { $0.contains("uint g") || $0.contains("float g") }
        #expect(members.count == 16)
    }
```
In this task only `.evaluate` exists in `kernels`; task 2 adds the others and these tests then cover them unchanged.

- [ ] **Step 3: Run to see them fail.** `swift test --filter CreatorImplicitTests.HLSLSourceTests 2>&1 | tail -3` — build failure ("type 'ImplicitCompiler' has no member 'compileHLSL'").

- [ ] **Step 4: The kernel types.**

`Sources/CreatorImplicit/Compute/KernelSource.swift`:
```swift
/// One kernel's HLSL text and its digest (plan xp-c): what a backend compiles to a pipeline and what the pipeline cache is keyed by, as Metal's is by
/// `ShapeKey`. The digest is FNV-1a 64 of the UTF-8 text in hex, stable across processes (the offline test compile names its files by it).
public struct KernelSource: Sendable, Hashable {
    public let kernel: ImplicitKernel
    public let text: String
    public let digest: String

    public init(kernel: ImplicitKernel, text: String) {
        self.kernel = kernel
        self.text = text
        digest = Self.fnv1a(text)
    }

    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    public static func == (lhs: KernelSource, rhs: KernelSource) -> Bool { lhs.digest == rhs.digest && lhs.text == rhs.text }
    public func hash(into hasher: inout Hasher) { hasher.combine(digest) }
}
```

`Sources/CreatorImplicit/Compute/ImplicitKernel.swift`:
```swift
/// The HLSL engine's compute kernels (plan xp-c), one source each (`HLSLKernels`): Metal's `evaluateImplicit` and the five meshing kernels of
/// `ImplicitMeshShaderLibrary`, plus `mesh_clear`, because SDL_GPU has no buffer fill. A `ComputeDispatch` lists the storage buffers in declaration order.
public enum ImplicitKernel: String, CaseIterable, Sendable {
    /// floats, ints, points → values.
    case evaluate = "implicit_evaluate"
    /// → keys (emptied over a range of slots).
    case clear = "mesh_clear"
    /// floats, ints, bricks, axes → samples.
    case sample = "mesh_sample"
    /// bricks, samples, cube table → keys, counters.
    case classify = "mesh_classify"
    /// keys → slot vertices, counters.
    case number = "mesh_number"
    /// floats, ints, axes, keys, slot vertices → positions, normals.
    case place = "mesh_place"
    /// bricks, samples, cube table, keys, slot vertices → counters, indices.
    case emit = "mesh_emit"

    public static let threadsPerGroup = 64

    public var bindings: (readOnly: Int, readWrite: Int) {
        switch self {
        case .evaluate: (3, 1)
        case .clear: (0, 1)
        case .sample: (4, 1)
        case .classify: (3, 2)
        case .number: (1, 2)
        case .place: (5, 2)
        case .emit: (5, 2)
        }
    }

    /// Whether the kernel calls the solid's `sdf`, so its source depends on the shape.
    public var usesSDF: Bool { self == .evaluate || self == .sample || self == .place }
}
```

`Sources/CreatorImplicit/Compute/KernelParameters.swift`:
```swift
/// The one uniform block every HLSL kernel reads (`cbuffer Params : register(b0, space2)`, `HLSLShaderLibrary.prelude`): Metal's `count` and
/// `MeshParams`, and where the pool, the pictures and the tables start in the two packed buffers. Sixteen four-byte words.
public struct KernelParameters: Sendable, Equatable {
    public var count: UInt32 = 0
    public var poolBase: UInt32 = 0
    public var imagesBase: UInt32 = 0
    public var tablesBase: UInt32 = 0
    public var firstBrick: UInt32 = 0
    public var brickCount: UInt32 = 0
    public var nx: UInt32 = 0
    public var ny: UInt32 = 0
    public var nz: UInt32 = 0
    public var mask: UInt32 = 0
    public var snap: UInt32 = 0
    public var resolution: Float = 0
    public var firstSlot: UInt32 = 0
    public var padding0: UInt32 = 0
    public var padding1: UInt32 = 0
    public var padding2: UInt32 = 0

    public init() {}

    /// The block as the GPU reads it, from an explicit word list (no reliance on Swift's struct layout).
    var bytes: [UInt8] {
        let words: [UInt32] = [count, poolBase, imagesBase, tablesBase, firstBrick, brickCount, nx, ny, nz, mask, snap, resolution.bitPattern,
                               firstSlot, padding0, padding1, padding2]
        return words.withUnsafeBytes { Array($0) }
    }
}
```

- [ ] **Step 5: The dialect, and the generator writing through it.**

`Sources/CreatorImplicit/Metal/ShaderDialect.swift`:
```swift
/// How `ImplicitCompiler.Generator` spells what differs between Metal and HLSL (plan xp-c): a float parameter, an integer parameter, and the
/// environment argument the library's functions take in MSL (`e`, the buffers) and do not in HLSL (the buffers are globals). Everything else the
/// generator writes is the same text in both.
enum ShaderDialect: Sendable {
    case msl
    case hlsl

    func parameter(_ slot: Int) -> String {
        switch self {
        case .msl: "e.P[\(slot)]"
        case .hlsl: "P(\(slot))"
        }
    }

    func integer(_ slot: Int) -> String {
        switch self {
        case .msl: "e.I[\(slot)]"
        case .hlsl: "I(\(slot))"
        }
    }

    /// Written first in a library call's arguments.
    var environment: String {
        switch self {
        case .msl: "e, "
        case .hlsl: ""
        }
    }
}
```
In `ImplicitCompiler.Generator` add `var dialect = ShaderDialect.msl` as its first stored property; make `number` return `dialect.parameter(parameters.count - 1)` and `integer` return `dialect.integer(integers.count - 1)`; and in the eight library calls replace the literal `(e, ` with `(\(dialect.environment)`: `bakedValue` (twice, in `solid` and `field`), `strutBody`, `voronoiBody`, `fieldNoise`, `imageValue` (in `ImplicitCompiler.swift`), `mapFace` and `bakedChannel` (in `+Mapping.swift`). Nothing else in the generator changes. Run `swift test --filter "CreatorImplicitTests.HLSLSourceTests/theMetalSourceIsTheOneRecordedBeforeTheDialect"`: PASS (the MSL text is unchanged).

Add to `ImplicitCompiler`:
```swift
    /// The same solid in HLSL (plan xp-c): the same walk with the HLSL dialect, so the `sdf` is the Metal one statement for statement and the
    /// buffers are identical; one source per kernel (`HLSLKernels`).
    public static func compileHLSL(_ solid: ImplicitSolid) throws(ImplicitCompileError) -> CompiledImplicit {
        var generator = Generator()
        generator.dialect = .hlsl
        let result = try generator.solid(solid, at: "p")
        let sdf = "float sdf(float3 p) {\n\(generator.lines.joined(separator: "\n"))\n    return \(result);\n}\n"
        let kernels = HLSLKernels.sources(sdf: sdf)
        return CompiledImplicit(source: kernels[.evaluate]?.text ?? "", parameters: generator.parameters, integers: generator.integers,
                                tables: generator.tables, pool: generator.pool, images: generator.images, language: .hlsl, kernels: kernels)
    }
```

In `CompiledImplicit.swift` add `public enum ShaderLanguage: Sendable { case msl, hlsl }` (its own file, `Metal/ShaderLanguage.swift`), the stored properties
```swift
    /// Which language `source` is in.
    public let language: ShaderLanguage
    /// The HLSL kernels' sources (plan xp-c), empty for Metal.
    public let kernels: [ImplicitKernel: KernelSource]
```
and initializer parameters `language: ShaderLanguage = .msl, kernels: [ImplicitKernel: KernelSource] = [:]` set in its body. `ImplicitCompiler.compile`'s call is unchanged.

- [ ] **Step 6: The HLSL library.**

`Sources/CreatorImplicit/HLSL/HLSLKernels.swift` (task 2 adds the meshing kernels):
```swift
/// A solid's HLSL kernel sources (plan xp-c): the prelude, then, for a kernel that calls `sdf`, the two packed buffers, the library and the shape's
/// `sdf`, then the kernel's own buffers and `main`. SDL_GPU compiles one entry point a shader, so where Metal compiles one library a shape, this is one
/// source a kernel; the kernels that do not call `sdf` have the same text for every shape and the pipeline cache makes them once.
enum HLSLKernels {
    static func sources(sdf: String) -> [ImplicitKernel: KernelSource] {
        let shape = HLSLShaderLibrary.withSDF(sdf)
        return [.evaluate: KernelSource(kernel: .evaluate, text: HLSLShaderLibrary.prelude + shape + HLSLShaderLibrary.evaluate)]
    }
}
```

`Sources/CreatorImplicit/HLSL/HLSLShaderLibrary.swift`:
```swift
/// The HLSL every compiled implicit shares (plan xp-c): the twin of `ImplicitShaderLibrary` (MSL), function for function, with the engine's own
/// trigonometry (`+Math`) and the lattices (`+Lattices`). Text only: it imports nothing and builds everywhere. The buffers are two globals, `floats`
/// (the parameters, then the pool, then the pictures) and `ints` (the integer parameters, then the tables), read through `P`, `I`, `POOL`, `IMAGES`
/// and `TABLES`, so the generated `sdf` names a parameter `P(k)` where Metal's names `e.P[k]`.
enum HLSLShaderLibrary {
    /// Every kernel's start: the constants the Swift side shares and the uniform block (`KernelParameters`, word for word).
    static let prelude = """
    #define THREADS 64
    #define EMPTY_KEY 0xFFFFFFFFu
    #define CUBE_STARTS \(MarchingCubesBuffers.startsOffset)u
    #define CUBE_LOWER \(MarchingCubesBuffers.lowerCornersOffset)u
    #define CUBE_UPPER \(MarchingCubesBuffers.upperCornersOffset)u
    #define CUBE_EDGES \(MarchingCubesBuffers.edgesOffset)u
    #define BRICK \(BrickPlan.brickSize)u
    #define SIDE \(BrickPlan.brickSize + 1)u
    #define CUBES \(BrickPlan.brickSize * BrickPlan.brickSize * BrickPlan.brickSize)u
    #define POINTS \((BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1))u
    #define PROBE_LIMIT \(ImplicitMeshShaderLibrary.probeLimit)u
    #define COUNTER_VERTICES \(ImplicitMeshShaderLibrary.Counter.vertices)u
    #define COUNTER_TRIANGLE_TOTAL \(ImplicitMeshShaderLibrary.Counter.triangleTotal)u
    #define COUNTER_TRIANGLE_CURSOR \(ImplicitMeshShaderLibrary.Counter.triangleCursor)u
    #define COUNTER_OVERFLOW \(ImplicitMeshShaderLibrary.Counter.overflow)u
    #define INFINITY_F asfloat(0x7F800000u)
    #define PI_F 3.14159265358979323846f
    #define HALF_PI_F 1.57079632679489661923f
    #define QUARTER_PI_F 0.78539816339744830962f

    cbuffer Params : register(b0, space2) {
        uint gCount;
        uint gPoolBase;
        uint gImagesBase;
        uint gTablesBase;
        uint gFirstBrick;
        uint gBrickCount;
        uint gNX;
        uint gNY;
        uint gNZ;
        uint gMask;
        uint gSnap;
        float gResolution;
        uint gFirstSlot;
        uint gPadding0;
        uint gPadding1;
        uint gPadding2;
    };

    """

    /// For a kernel that calls `sdf`: the packed buffers (always slots 0 and 1), the library and the shape's `sdf`.
    static func withSDF(_ sdf: String) -> String {
        """
        StructuredBuffer<float> floats : register(t0, space0);
        StructuredBuffer<int> ints : register(t1, space0);

        """ + math + "\n" + core + "\n" + lattices + "\n" + sdf
    }

    /// Metal's `evaluateImplicit`: the solid at a batch of points, three floats each.
    static let evaluate = """

    StructuredBuffer<float> points : register(t2, space0);
    RWStructuredBuffer<float> values : register(u0, space1);

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint index = id.x;
        if (index >= gCount) { return; }
        values[index] = sdf(float3(points[3u * index], points[3u * index + 1u], points[3u * index + 2u]));
    }
    """

    /// `ImplicitShaderLibrary.core`, ported: primitives, smooth minimum, baked blocks, field maths, simplex noise, pictures.
    static let core = """
    // The functions every compiled implicit shares (implicit spec §4.1): a port of ImplicitShaderLibrary.core (the MSL of the Metal engine), each a
    // line-for-line port of its CPU twin (CPUEvaluation, DistanceBlocks, FieldNoise, GreyImage). The kernel declares `floats` (the parameters, then the
    // pool, then the pictures) and `ints` (the integer parameters, then the tables) before it includes this; the bases are in Params.

    float P(int k) { return floats[k]; }
    float3 PV(int k) { return float3(floats[k], floats[k + 1], floats[k + 2]); }
    int I(int k) { return ints[k]; }
    int TABLES(int k) { return ints[int(gTablesBase) + k]; }
    float POOL(int k) { return floats[int(gPoolBase) + k]; }
    float IMAGES(int k) { return floats[int(gImagesBase) + k]; }

    float smoothMin(float a, float b, float k) {
        if (!(k > 0.0f)) { return min(a, b); }
        float blend = max(k - abs(a - b), 0.0f) / k;
        return min(a, b) - blend * blend * k * 0.25f;
    }

    float sdBox(float3 p, float3 halfSize, float r) {
        float3 q = abs(p) - (halfSize - r);
        return length(max(q, 0.0f)) + min(max(q.x, max(q.y, q.z)), 0.0f) - r;
    }

    float regionDistance(float3 p, float3 centre, float3 halfSize) {
        float3 q = abs(p - centre) - halfSize;
        return length(max(q, 0.0f)) + min(max(q.x, max(q.y, q.z)), 0.0f);
    }

    float sdCylinder(float3 p, float r, float halfHeight) {
        float across = length(p.xy) - r;
        float along = abs(p.z) - halfHeight;
        return min(max(across, along), 0.0f) + length(max(float2(across, along), 0.0f));
    }

    // MARK: baked distance blocks (DistanceBlocks)

    float bakedSample(int ioff, int i, int j, int k) {
        int nx = I(ioff + 3), ny = I(ioff + 4), nz = I(ioff + 5);
        i = clamp(i, 0, nx * 8 - 1);
        j = clamp(j, 0, ny * 8 - 1);
        k = clamp(k, 0, nz * 8 - 1);
        int block = ((k / 8) * ny + (j / 8)) * nx + (i / 8);
        int slot = TABLES(I(ioff) + block);
        if (slot < 0) { return POOL(I(ioff + 2) + block); }
        return POOL(I(ioff + 1) + slot * 512 + ((k % 8) * 8 + (j % 8)) * 8 + (i % 8));
    }

    float bakedTrilinear(int ioff, int poff, float3 held) {
        float3 origin = PV(poff);
        float spacing = P(poff + 3);
        float3 last = float3(I(ioff + 3) * 8 - 1, I(ioff + 4) * 8 - 1, I(ioff + 5) * 8 - 1);
        float3 grid = clamp((held - origin) / spacing, float3(0.0f, 0.0f, 0.0f), last);
        int ix = int(floor(grid.x)), iy = int(floor(grid.y)), iz = int(floor(grid.z));
        float tx = grid.x - float(ix), ty = grid.y - float(iy), tz = grid.z - float(iz);
        float x00 = lerp(bakedSample(ioff, ix, iy, iz), bakedSample(ioff, ix + 1, iy, iz), tx);
        float x10 = lerp(bakedSample(ioff, ix, iy + 1, iz), bakedSample(ioff, ix + 1, iy + 1, iz), tx);
        float x01 = lerp(bakedSample(ioff, ix, iy, iz + 1), bakedSample(ioff, ix + 1, iy, iz + 1), tx);
        float x11 = lerp(bakedSample(ioff, ix, iy + 1, iz + 1), bakedSample(ioff, ix + 1, iy + 1, iz + 1), tx);
        return lerp(lerp(x00, x10, ty), lerp(x01, x11, ty), tz);
    }

    float bakedValue(int ioff, int poff, float3 point) {
        float3 origin = PV(poff);
        float3 last = float3(I(ioff + 3) * 8 - 1, I(ioff + 4) * 8 - 1, I(ioff + 5) * 8 - 1);
        float3 held = clamp(point, origin, origin + last * P(poff + 3));
        return bakedTrilinear(ioff, poff, held) + length(point - held);
    }

    float bakedChannel(int ioff, int poff, float3 point) {
        float3 origin = PV(poff);
        float3 last = float3(I(ioff + 3) * 8 - 1, I(ioff + 4) * 8 - 1, I(ioff + 5) * 8 - 1);
        return bakedTrilinear(ioff, poff, clamp(point, origin, origin + last * P(poff + 3)));
    }

    // MARK: field maths

    float remapField(float x, float fromLow, float fromHigh, float toLow, float toHigh, int clamped) {
        if (fromHigh == fromLow) { return toLow; }
        float mapped = toLow + (x - fromLow) / (fromHigh - fromLow) * (toHigh - toLow);
        if (clamped == 0) { return mapped; }
        return min(max(mapped, min(toLow, toHigh)), max(toLow, toHigh));
    }

    // MARK: simplex noise (FieldNoise)

    static const float3 noiseGradients[12] = {
        float3(1, 1, 0), float3(-1, 1, 0), float3(1, -1, 0), float3(-1, -1, 0), float3(1, 0, 1), float3(-1, 0, 1),
        float3(1, 0, -1), float3(-1, 0, -1), float3(0, 1, 1), float3(0, -1, 1), float3(0, 1, -1), float3(0, -1, -1)
    };

    static const int3 noiseCorners[24] = {
        int3(0, 0, 0), int3(1, 0, 0), int3(1, 1, 0), int3(1, 1, 1),
        int3(0, 0, 0), int3(1, 0, 0), int3(1, 0, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 0, 1), int3(1, 0, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 0, 1), int3(0, 1, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 1, 0), int3(0, 1, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 1, 0), int3(1, 1, 0), int3(1, 1, 1)
    };

    U64 mix64(U64 value) {
        U64 z = value;
        z = u64Mul(u64Xor(z, u64Shr(z, 30u)), u64(0xBF58476Du, 0x1CE4E5B9u));
        z = u64Mul(u64Xor(z, u64Shr(z, 27u)), u64(0x94D049BBu, 0x133111EBu));
        return u64Xor(z, u64Shr(z, 31u));
    }

    float3 noiseGradient(int i, int j, int k, U64 start) {
        U64 packed = u64Or(u64Or(u64Shl(u64(0u, asuint(i) & 0x1FFFFFu), 42u), u64Shl(u64(0u, asuint(j) & 0x1FFFFFu), 21u)),
                           u64(0u, asuint(k) & 0x1FFFFFu));
        U64 draw = mix64(u64Add(start, u64Mul(u64Add(packed, u64(0u, 1u)), u64(0x9E3779B9u, 0x7F4A7C15u))));
        return noiseGradients[u64Shr(draw, 33u).lo % 12u];
    }

    float simplexOctave(float x, float y, float z, U64 start) {
        float skewed = (x + y + z) * (1.0f / 3.0f);
        int i = int(floor(x + skewed)), j = int(floor(y + skewed)), k = int(floor(z + skewed));
        float back = float(i + j + k) * (1.0f / 6.0f);
        float x0 = x - (float(i) - back), y0 = y - (float(j) - back), z0 = z - (float(k) - back);
        int ordering;
        if (x0 >= y0) {
            ordering = y0 >= z0 ? 0 : (x0 >= z0 ? 1 : 2);
        } else {
            ordering = y0 < z0 ? 3 : (x0 < z0 ? 4 : 5);
        }
        float sum = 0.0f;
        for (int step = 0; step < 4; step++) {
            int3 corner = noiseCorners[ordering * 4 + step];
            float shift = float(step) * (1.0f / 6.0f);
            float dx = x0 - float(corner.x) + shift, dy = y0 - float(corner.y) + shift, dz = z0 - float(corner.z) + shift;
            float falloff = 0.6f - dx * dx - dy * dy - dz * dz;
            if (falloff <= 0.0f) { continue; }
            float3 gradient = noiseGradient(i + corner.x, j + corner.y, k + corner.z, start);
            float weight = falloff * falloff;
            sum += weight * weight * dot(gradient, float3(dx, dy, dz));
        }
        return 32.0f * sum;
    }

    float fieldNoise(float3 p, float scale, int octaves, int seeds) {
        float sum = 0.0f, total = 0.0f, amplitude = 1.0f, size = scale;
        for (int octave = 0; octave < octaves; octave++) {
            U64 start = u64(asuint(TABLES(seeds + 2 * octave + 1)), asuint(TABLES(seeds + 2 * octave)));
            sum += amplitude * simplexOctave(p.x / size, p.y / size, p.z / size, start);
            total += amplitude;
            amplitude *= 0.5f;
            size *= 0.5f;
        }
        return clamp((sum / total + 1.0f) / 2.0f, 0.0f, 1.0f);
    }

    // MARK: pictures (GreyImage)

    void imageTaps(float position, int count, int edges, out int low, out int high, out float fraction) {
        float size = float(count);
        float held;
        if (edges == 0) {
            float folded = position - floor(position / size) * size;
            held = min(max(folded, 0.0f), asfloat(asuint(size) - 1u));
            low = int(floor(held));
            high = (low + 1) % count;
        } else {
            held = min(max(position, 0.0f), size - 1.0f);
            low = int(floor(held));
            high = min(low + 1, count - 1);
        }
        fraction = held - float(low);
    }

    float imageValue(int ioff, float u, float v) {
        int offset = I(ioff), width = I(ioff + 1), height = I(ioff + 2), edges = I(ioff + 3);
        float x = u * float(width) - 0.5f, y = v * float(height) - 0.5f;
        if (!isfinite(x) || !isfinite(y)) { return 0.0f; }
        int cl, ch, rl, rh;
        float cf, rf;
        imageTaps(x, width, edges, cl, ch, cf);
        imageTaps(y, height, edges, rl, rh, rf);
        float top = lerp(IMAGES(offset + rl * width + cl), IMAGES(offset + rl * width + ch), cf);
        float bottom = lerp(IMAGES(offset + rh * width + cl), IMAGES(offset + rh * width + ch), cf);
        return lerp(top, bottom, rf) / 65535.0f;
    }
    """
}
```

`Sources/CreatorImplicit/HLSL/HLSLShaderLibrary+Math.swift`:
```swift
/// Sine, cosine and arctangent to about one ulp on every driver, and unsigned 64-bit arithmetic in two words (plan xp-c, X-C6). Metal's engine uses
/// `precise::` and `ulong`; Vulkan promises only an absolute 2^-11 for `sin`, and `uint64_t` needs a device feature SDL_GPU does not report. The
/// reduction is Cody-Waite in three parts of pi/2; the polynomials are Cephes' sinf, cosf and atanf (Stephen L. Moshier, public domain).
extension HLSLShaderLibrary {
    static let math = """
    // Sine, cosine and arctangent to about one ulp on every driver (plan xp-c, user decision X-C6). Vulkan promises only an absolute 2^-11 for sin on
    // [-pi, pi] and Direct3D says less, while a TPMS wall is scaled by cell / 2pi: 2^-11 would be about 4e-4 mm at a 5 mm cell, against the 1e-4 mm the
    // GPU is held to. The reduction is Cody-Waite in three parts of pi/2 (the first two exact in a float product for |q| < 2^15); the polynomials are
    // Cephes' sinf, cosf and atanf (Stephen L. Moshier, public domain). The arguments the lattices give are under 13 (tpmsRaw's 2q), far inside that.

    void reduceQuarter(float x, out float y, out int quadrant) {
        float q = round(x * 0.636619772367581343f);
        y = ((x - q * 1.5703125f) - q * 4.837512969970703125e-4f) - q * 7.54978995489188216e-8f;
        quadrant = int(q);
    }

    float sinPolynomial(float y) {
        float z = y * y;
        return ((-1.9515295891e-4f * z + 8.3321608736e-3f) * z - 1.6666654611e-1f) * z * y + y;
    }

    float cosPolynomial(float y) {
        float z = y * y;
        return ((2.443315711809948e-5f * z - 1.388731625493765e-3f) * z + 4.166664568298827e-2f) * z * z - 0.5f * z + 1.0f;
    }

    float accSin(float x) {
        float y;
        int quadrant;
        reduceQuarter(x, y, quadrant);
        float s = sinPolynomial(y), c = cosPolynomial(y);
        int k = quadrant & 3;
        return k == 0 ? s : (k == 1 ? c : (k == 2 ? -s : -c));
    }

    float accCos(float x) {
        float y;
        int quadrant;
        reduceQuarter(x, y, quadrant);
        float s = sinPolynomial(y), c = cosPolynomial(y);
        int k = quadrant & 3;
        return k == 0 ? c : (k == 1 ? -s : (k == 2 ? -c : s));
    }

    float3 accSin3(float3 v) { return float3(accSin(v.x), accSin(v.y), accSin(v.z)); }
    float3 accCos3(float3 v) { return float3(accCos(v.x), accCos(v.y), accCos(v.z)); }

    float accAtan(float x) {
        float sign = x < 0.0f ? -1.0f : 1.0f;
        float t = abs(x);
        float offset = 0.0f;
        if (t > 2.414213562373095f) {
            offset = HALF_PI_F;
            t = -1.0f / t;
        } else if (t > 0.4142135623730950f) {
            offset = QUARTER_PI_F;
            t = (t - 1.0f) / (t + 1.0f);
        }
        float z = t * t;
        return sign * (offset + ((((8.05374449538e-2f * z - 1.38776856032e-1f) * z + 1.99777106478e-1f) * z - 3.33329491539e-1f) * z * t + t));
    }

    // atan2 as IEEE 754 and the CPU's Double have it, signed zeros included: atan2(+0, -1) = pi, atan2(-0, -1) = -pi, atan2(+-0, +0) = +-0.
    float accAtan2(float y, float x) {
        bool yNegative = (asuint(y) & 0x80000000u) != 0u;
        bool xNegative = (asuint(x) & 0x80000000u) != 0u;
        if (x == 0.0f) {
            if (y == 0.0f) { return xNegative ? (yNegative ? -PI_F : PI_F) : y; }
            return yNegative ? -HALF_PI_F : HALF_PI_F;
        }
        float angle = accAtan(y / x);
        if (xNegative) { angle += yNegative ? -PI_F : PI_F; }
        return angle;
    }

    // Unsigned 64-bit arithmetic in two 32-bit words (plan xp-c, user decision X-C6): the noise's SplitMix64 hash needs it, and uint64_t needs a device
    // feature (shaderInt64) SDL_GPU neither enables nor reports. Exact, so a draw is bit for bit FieldNoise's on the CPU.

    struct U64 {
        uint hi;
        uint lo;
    };

    U64 u64(uint hi, uint lo) {
        U64 value;
        value.hi = hi;
        value.lo = lo;
        return value;
    }

    U64 u64Add(U64 a, U64 b) {
        uint lo = a.lo + b.lo;
        return u64(a.hi + b.hi + (lo < a.lo ? 1u : 0u), lo);
    }

    U64 u64Xor(U64 a, U64 b) { return u64(a.hi ^ b.hi, a.lo ^ b.lo); }
    U64 u64Or(U64 a, U64 b) { return u64(a.hi | b.hi, a.lo | b.lo); }

    // 0 < shift < 64.
    U64 u64Shr(U64 a, uint shift) {
        if (shift >= 32u) { return u64(0u, a.hi >> (shift - 32u)); }
        return u64(a.hi >> shift, (a.lo >> shift) | (a.hi << (32u - shift)));
    }

    U64 u64Shl(U64 a, uint shift) {
        if (shift >= 32u) { return u64(a.lo << (shift - 32u), 0u); }
        return u64((a.hi << shift) | (a.lo >> (32u - shift)), a.lo << shift);
    }

    // The full 64-bit product of two 32-bit words, by 16-bit halves.
    U64 u64Product(uint a, uint b) {
        uint a0 = a & 0xFFFFu, a1 = a >> 16, b0 = b & 0xFFFFu, b1 = b >> 16;
        uint p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
        uint middle = (p00 >> 16) + (p01 & 0xFFFFu) + (p10 & 0xFFFFu);
        return u64(p11 + (p01 >> 16) + (p10 >> 16) + (middle >> 16), (p00 & 0xFFFFu) | (middle << 16));
    }

    // The low 64 bits of a 64 x 64 product, as UInt64's &* wraps.
    U64 u64Mul(U64 a, U64 b) {
        U64 low = u64Product(a.lo, b.lo);
        return u64(low.hi + a.hi * b.lo + a.lo * b.hi, low.lo);
    }
    """
}
```

`Sources/CreatorImplicit/HLSL/HLSLShaderLibrary+Lattices.swift`:
```swift
/// `ImplicitShaderLibrary.lattices`, ported (implicit spec §3.4, §3.5): TPMS, struts, Voronoi and the mappings, trigonometry through `accSin`,
/// `accCos` and `accAtan2`.
extension HLSLShaderLibrary {
    static let lattices = """
    // The lattices and their mappings (implicit spec §3.4, §3.5): a port of ImplicitShaderLibrary.lattices, trigonometry through accurate_math.hlsli.

    float tpmsRaw(int type, float3 q) {
        float3 s = accSin3(q), c = accCos3(q);
        if (type == 0) { return s.x * c.y + s.y * c.z + s.z * c.x; }
        if (type == 1) { return c.x + c.y + c.z; }
        if (type == 2) { return s.x * s.y * s.z + s.x * c.y * c.z + c.x * s.y * c.z + c.x * c.y * s.z; }
        if (type == 3) { return 3.0f * (c.x + c.y + c.z) + 4.0f * c.x * c.y * c.z; }
        float first = accSin(2.0f * q.x) * c.y * s.z + accSin(2.0f * q.y) * c.z * s.x + accSin(2.0f * q.z) * c.x * s.y;
        float second = accCos(2.0f * q.x) * accCos(2.0f * q.y) + accCos(2.0f * q.y) * accCos(2.0f * q.z)
            + accCos(2.0f * q.z) * accCos(2.0f * q.x);
        return 0.5f * first - 0.5f * second + 0.15f;
    }

    float tpmsBody(float3 m, float cell, float3 stretch, float thickness, int type, int form, float wallScale) {
        const float twoPi = 6.28318530717958647692f;
        float size = max(cell, 0.000001f);
        float3 u = m / (size * stretch);
        float3 q = twoPi * (u - floor(u));
        float core = tpmsRaw(type, q) * size / (twoPi * wallScale);
        float wall = max(thickness, 0.0f);
        return form == 0 ? abs(core) - wall * 0.5f : core - wall * 0.5f;
    }

    float segmentDistance(float3 p, float3 a, float3 b) {
        float3 along = b - a;
        float length2 = dot(along, along);
        float t = length2 > 0.0f ? clamp(dot(p - a, along) / length2, 0.0f, 1.0f) : 0.0f;
        return length(p - a - along * t);
    }

    float strutBody(int offset, int count, float3 m, float cell, float3 stretch, float radius, float blend) {
        float size = max(cell, 0.000001f);
        float3 edges = size * stretch;
        float3 index = floor(m / edges);
        float nearest = 1e30f;
        for (int dz = -1; dz <= 1; dz++) {
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    float3 base = index + float3(float(dx), float(dy), float(dz));
                    for (int s = 0; s < count; s++) {
                        int at = offset + 6 * s;
                        float3 start = (base + float3(POOL(at), POOL(at + 1), POOL(at + 2))) * edges;
                        float3 end = (base + float3(POOL(at + 3), POOL(at + 4), POOL(at + 5))) * edges;
                        nearest = smoothMin(nearest, segmentDistance(m, start, end), blend);
                    }
                }
            }
        }
        float reach = 0.85f * min(edges.x, min(edges.y, edges.z));
        return min(nearest, reach) - max(radius, 0.0f);
    }

    float3 seedAt(int pointsAt, int seed) {
        return float3(POOL(pointsAt + 3 * seed), POOL(pointsAt + 3 * seed + 1), POOL(pointsAt + 3 * seed + 2));
    }

    float voronoiBody(int ioff, int poff, float3 m, float thickness, int form, float strutScale) {
        int pointsAt = I(ioff), startsAt = I(ioff + 1), entriesAt = I(ioff + 2);
        int3 counts = int3(I(ioff + 3), I(ioff + 4), I(ioff + 5));
        float3 origin = PV(poff);
        float radius = P(poff + 3);
        float3 cellAt = clamp(floor((m - origin) / radius), float3(-2.0f, -2.0f, -2.0f), float3(counts) + 1.0f);
        int3 cell = int3(cellAt);
        float d1 = INFINITY_F, d2 = INFINITY_F, d3 = INFINITY_F;
        int nearest = -1;
        for (int dz = -1; dz <= 1; dz++) {
            int z = cell.z + dz;
            if (z < 0 || z >= counts.z) { continue; }
            for (int dy = -1; dy <= 1; dy++) {
                int y = cell.y + dy;
                if (y < 0 || y >= counts.y) { continue; }
                for (int dx = -1; dx <= 1; dx++) {
                    int x = cell.x + dx;
                    if (x < 0 || x >= counts.x) { continue; }
                    int index = (z * counts.y + y) * counts.x + x;
                    for (int k = TABLES(startsAt + index); k < TABLES(startsAt + index + 1); k++) {
                        int seed = TABLES(entriesAt + k);
                        float d = length(m - seedAt(pointsAt, seed));
                        if (d < d1) { d3 = d2; d2 = d1; d1 = d; nearest = seed; }
                        else if (d < d2) { d3 = d2; d2 = d; }
                        else if (d < d3) { d3 = d; }
                    }
                }
            }
        }
        float wall = max(thickness, 0.0f);
        float body;
        if (form == 0) {
            body = (min(d3, radius) - min(d1, radius)) / strutScale - wall * 0.5f;
        } else {
            float distance = max(0.0f, (radius - d1) * 0.5f);
            if (nearest >= 0) {
                float3 first = seedAt(pointsAt, nearest);
                for (int dz = -1; dz <= 1; dz++) {
                    int z = cell.z + dz;
                    if (z < 0 || z >= counts.z) { continue; }
                    for (int dy = -1; dy <= 1; dy++) {
                        int y = cell.y + dy;
                        if (y < 0 || y >= counts.y) { continue; }
                        for (int dx = -1; dx <= 1; dx++) {
                            int x = cell.x + dx;
                            if (x < 0 || x >= counts.x) { continue; }
                            int index = (z * counts.y + y) * counts.x + x;
                            for (int k = TABLES(startsAt + index); k < TABLES(startsAt + index + 1); k++) {
                                int seed = TABLES(entriesAt + k);
                                float3 position = seedAt(pointsAt, seed);
                                float3 across = position - first;
                                float length2 = length(across);
                                if (seed == nearest || length2 <= 0.000000001f) { continue; }
                                distance = min(distance, dot(across, (first + position) * 0.5f - m) / length2);
                            }
                        }
                    }
                }
            }
            body = distance - wall * 0.5f;
        }
        return body;
    }

    float3 mapCylindrical(float3 p, float3 origin, float3 reference, float3 side, float3 axis, float radius) {
        float3 offset = p - origin;
        float x = dot(offset, reference), y = dot(offset, side);
        return float3(accAtan2(y, x) * radius, dot(offset, axis), sqrt(x * x + y * y));
    }

    float singularCylindrical(float3 p, float3 origin, float3 reference, float3 side) {
        float3 offset = p - origin;
        float x = dot(offset, reference), y = dot(offset, side);
        return sqrt(x * x + y * y);
    }

    float3 mapSpherical(float3 p, float3 centre, float radius) {
        float3 offset = p - centre;
        float across = sqrt(offset.x * offset.x + offset.y * offset.y);
        return float3(accAtan2(offset.y, offset.x) * radius, accAtan2(offset.z, across) * radius, length(offset));
    }

    float singularSpherical(float3 p, float3 centre) {
        float3 offset = p - centre;
        return sqrt(offset.x * offset.x + offset.y * offset.y);
    }

    float3 mapFace(int h, float3 p, float firstRadius, float secondRadius) {
        int flags = I(h);
        float a = bakedChannel(I(h + 1), I(h + 2), p);
        if ((flags & 1) != 0) { a = accAtan2(bakedChannel(I(h + 3), I(h + 4), p), a) * firstRadius; }
        float b = bakedChannel(I(h + 5), I(h + 6), p);
        if ((flags & 2) != 0) { b = accAtan2(bakedChannel(I(h + 7), I(h + 8), p), b) * secondRadius; }
        return float3(a, b, bakedChannel(I(h + 9), I(h + 10), p));
    }

    float mappingJoin(float body, float singular, float exclusion, float fade) {
        float weight = clamp((singular - exclusion) / fade, 0.0f, 1.0f);
        float solid = singular - exclusion;
        if (weight >= 1.0f) { return body; }
        return weight <= 0.0f ? solid : weight * body + (1.0f - weight) * solid;
    }
    """
}
```
These are ports of `ImplicitShaderLibrary.core` and `.lattices` (`Sources/CreatorImplicit/Metal/ImplicitShaderLibrary*.swift`); before writing them, compare function by function with the branch's MSL and port the current text if a 7c follow-up changed one. Translation: `inline` dropped; the `const thread Env& e` parameter dropped and its fields read through `P`, `I`, `TABLES`, `POOL`, `IMAGES`; `mix` → `lerp`; `precise::sin`/`cos`/`atan2` → `accSin`/`accCos`/`accAtan2`; `as_type<float>(as_type<uint>(x) - 1u)` → `asfloat(asuint(x) - 1u)`; `INFINITY` → `INFINITY_F`; `thread int&` → `out int`; `ulong` → `U64`; `constant` arrays → `static const`; float literals with `f`.

- [ ] **Step 7: Run.** `swift test --filter CreatorImplicitTests.HLSLSourceTests 2>&1 | tail -3` — PASS; `swift test --filter CreatorImplicitTests 2>&1 | grep -E "Test run with|recorded an issue"` — one line, no issue (the Metal suites still pass: the MSL is the same bytes).

- [ ] **Step 8: Lint, commit** (`feat(implicit): the generator writes HLSL too, statement for statement with the MSL (xp-c task 1)`).

---

### Task 2: The meshing kernels' HLSL

**Files:**
- Create: `Sources/CreatorImplicit/HLSL/HLSLMeshShaderLibrary.swift`
- Modify: `Sources/CreatorImplicit/HLSL/HLSLKernels.swift`
- Test: `Tests/CreatorImplicitTests/HLSLSourceTests.swift` (one test added; task 1's tests now cover all seven kernels)

**Interfaces:**
- Consumes: `HLSLShaderLibrary.prelude`, `.withSDF(_:)` (task 1).
- Produces: `CompiledImplicit.kernels` holds all seven `ImplicitKernel`s for an HLSL solid; `clear`, `classify`, `number` and `emit` have the same `KernelSource` for every shape.

- [ ] **Step 1: The failing test.** Add to `HLSLSourceTests`:
```swift
    /// The kernels that do not call `sdf` are one text for every shape (the pipeline cache makes them once); the three that do differ by shape.
    @Test func theKernelsWithoutTheSolidAreTheSameForEveryShape() throws {
        let sphere = try ImplicitCompiler.compileHLSL(.sphere(radius: 5))
        let box = try ImplicitCompiler.compileHLSL(.box(halfSize: Vector3(1, 2, 3), cornerRadius: 0))
        #expect(Set(sphere.kernels.keys) == Set(ImplicitKernel.allCases))
        for kernel in ImplicitKernel.allCases {
            if kernel.usesSDF {
                #expect(sphere.kernels[kernel] != box.kernels[kernel], "\(kernel.rawValue) depends on the shape")
                #expect(sphere.kernels[kernel]?.text.contains("float sdf(float3 p) {") == true)
            } else {
                #expect(sphere.kernels[kernel] == box.kernels[kernel], "\(kernel.rawValue) is shape-independent")
                #expect(sphere.kernels[kernel]?.text.contains("sdf(") == false)
            }
        }
    }
```
Run: `swift test --filter CreatorImplicitTests.HLSLSourceTests 2>&1 | tail -3` — fails (only `.evaluate` exists).

- [ ] **Step 2: Write the meshing kernels.** `Sources/CreatorImplicit/HLSL/HLSLMeshShaderLibrary.swift`, the twin of `ImplicitMeshShaderLibrary.kernels` (compare them line by line): the same five steps, the same table and hash, the same Newton step. The differences are SDL_GPU's: a source per kernel, `gCount` guards (SDL dispatches whole groups of 64; Metal exact counts), a strong compare-and-swap (`InterlockedCompareExchange` cannot fail spuriously, so the weak CAS's retry branch goes), and `mesh_clear` (Metal blits 0xFF).
```swift
/// The meshing kernels in HLSL (plan xp-c; implicit spec §4.3, Errata D13): the twin of `ImplicitMeshShaderLibrary`, one source per kernel (SDL_GPU
/// compiles one entry point a shader), and `mesh_clear`, which empties the edge table because SDL_GPU has no buffer fill. The order of vertices and
/// triangles is the threads', as on Metal; the set is fixed.
enum HLSLMeshShaderLibrary {
    /// The table's hash and the lattice edge key (shared by classify, emit and place).
    static let common = """

    uint tableHash(uint key, uint mask) {
        uint h = key * 0x9E3779B1u;
        h ^= h >> 16;
        h *= 0x85EBCA6Bu;
        h ^= h >> 13;
        return h & mask;
    }

    uint edgeKeyOf(uint x, uint y, uint z, uint a, uint b) {
        uint lx = x + (a & 1u), ly = y + ((a >> 1) & 1u), lz = z + ((a >> 2) & 1u);
        uint axis = ((a ^ b) == 1u) ? 0u : (((a ^ b) == 2u) ? 1u : 2u);
        return ((lz * gNY + ly) * gNX + lx) * 3u + axis;
    }

    """

    /// A cube's corners and pattern (classify, emit; after `samples` is declared).
    static let cubes = """

    float cornerValue(uint base, uint x, uint y, uint z, uint corner) {
        return samples[base + ((z + (corner >> 2)) * SIDE + y + ((corner >> 1) & 1u)) * SIDE + x + (corner & 1u)];
    }

    uint cubePattern(uint base, uint x, uint y, uint z) {
        uint pattern = 0u;
        for (uint corner = 0u; corner < 8u; ++corner) {
            if (cornerValue(base, x, y, z, corner) < 0.0f) { pattern |= 1u << corner; }
        }
        return pattern;
    }

    """

    /// A lattice point at the CPU's coordinates (sample, place; after `axes` is declared).
    static let latticePoint = """

    float3 latticePoint(uint x, uint y, uint z) {
        return float3(axes[x], axes[gNX + y], axes[gNX + gNY + z]);
    }

    """

    static let clear = """

    RWStructuredBuffer<uint> keys : register(u0, space1);

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint slot = gFirstSlot + id.x;
        if (id.x >= gCount || slot > gMask) { return; }
        keys[slot] = EMPTY_KEY;
    }
    """

    static let sample = """

    StructuredBuffer<uint> bricks : register(t2, space0);
    StructuredBuffer<float> axes : register(t3, space0);
    RWStructuredBuffer<float> samples : register(u0, space1);
    """ + latticePoint + """

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint gid = id.x;
        if (gid >= gBrickCount * POINTS) { return; }
        uint b = gid / POINTS, r = gid % POINTS;
        uint x = r % SIDE, y = (r / SIDE) % SIDE, z = r / (SIDE * SIDE);
        uint at = (gFirstBrick + b) * 3u;
        samples[gid] = sdf(latticePoint(bricks[at] * BRICK + x, bricks[at + 1u] * BRICK + y, bricks[at + 2u] * BRICK + z));
    }
    """

    static let classify = """

    StructuredBuffer<uint> bricks : register(t0, space0);
    StructuredBuffer<float> samples : register(t1, space0);
    StructuredBuffer<uint> cubeTable : register(t2, space0);
    RWStructuredBuffer<uint> keys : register(u0, space1);
    RWStructuredBuffer<uint> counters : register(u1, space1);
    """ + common + cubes + """

    void claimSlot(uint key) {
        uint slot = tableHash(key, gMask);
        for (uint probe = 0u; probe < PROBE_LIMIT; ++probe) {
            uint original;
            InterlockedCompareExchange(keys[slot], EMPTY_KEY, key, original);
            if (original == EMPTY_KEY || original == key) { return; }
            slot = (slot + 1u) & gMask;
        }
        InterlockedOr(counters[COUNTER_OVERFLOW], 1u);
    }

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint gid = id.x;
        if (gid >= gBrickCount * CUBES) { return; }
        uint b = gid / CUBES, c = gid % CUBES;
        uint x = c % BRICK, y = (c / BRICK) % BRICK, z = c / (BRICK * BRICK);
        uint pattern = cubePattern(b * POINTS, x, y, z);
        uint begin = cubeTable[CUBE_STARTS + pattern], end = cubeTable[CUBE_STARTS + pattern + 1u];
        if (begin == end) { return; }
        InterlockedAdd(counters[COUNTER_TRIANGLE_TOTAL], (end - begin) / 3u);
        uint at = (gFirstBrick + b) * 3u;
        uint lx = bricks[at] * BRICK + x, ly = bricks[at + 1u] * BRICK + y, lz = bricks[at + 2u] * BRICK + z;
        for (uint edge = 0u; edge < 12u; ++edge) {
            uint low = cubeTable[CUBE_LOWER + edge], high = cubeTable[CUBE_UPPER + edge];
            if (((pattern >> low) & 1u) != ((pattern >> high) & 1u)) {
                claimSlot(edgeKeyOf(lx, ly, lz, low, high));
            }
        }
    }
    """

    static let number = """

    StructuredBuffer<uint> keys : register(t0, space0);
    RWStructuredBuffer<uint> slotVertex : register(u0, space1);
    RWStructuredBuffer<uint> counters : register(u1, space1);

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint slot = gFirstSlot + id.x;
        if (id.x >= gCount || slot > gMask || keys[slot] == EMPTY_KEY) { return; }
        uint vertexNumber;
        InterlockedAdd(counters[COUNTER_VERTICES], 1u, vertexNumber);
        slotVertex[slot] = vertexNumber;
    }
    """

    static let place = """

    StructuredBuffer<float> axes : register(t2, space0);
    StructuredBuffer<uint> keys : register(t3, space0);
    StructuredBuffer<uint> slotVertex : register(t4, space0);
    RWStructuredBuffer<float4> positions : register(u0, space1);
    RWStructuredBuffer<float4> normals : register(u1, space1);
    """ + latticePoint + """

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint slot = gFirstSlot + id.x;
        if (id.x >= gCount || slot > gMask) { return; }
        uint key = keys[slot];
        if (key == EMPTY_KEY) { return; }
        uint axis = key % 3u, index = key / 3u;
        uint x = index % gNX, y = (index / gNX) % gNY, z = index / (gNX * gNY);
        float3 low = latticePoint(x, y, z);
        float3 high = latticePoint(x + (axis == 0u ? 1u : 0u), y + (axis == 1u ? 1u : 0u), z + (axis == 2u ? 1u : 0u));
        float fa = sdf(low), fb = sdf(high);
        float t = fa / (fa - fb);
        float3 position = low;
        if (axis == 0u) {
            position.x = low.x + gResolution * t;
        } else if (axis == 1u) {
            position.y = low.y + gResolution * t;
        } else {
            position.z = low.z + gResolution * t;
        }
        float3 normal = float3(0.0f, 0.0f, 0.0f);
        if (gSnap != 0u) {
            float delta = gResolution / 4.0f, limit = gResolution / 2.0f;
            float value = sdf(position);
            float3 gradient = float3(
                (sdf(position + float3(delta, 0.0f, 0.0f)) - sdf(position - float3(delta, 0.0f, 0.0f))) / (2.0f * delta),
                (sdf(position + float3(0.0f, delta, 0.0f)) - sdf(position - float3(0.0f, delta, 0.0f))) / (2.0f * delta),
                (sdf(position + float3(0.0f, 0.0f, delta)) - sdf(position - float3(0.0f, 0.0f, delta))) / (2.0f * delta));
            float squared = dot(gradient, gradient);
            if (squared > 1e-12f) {
                normal = gradient / sqrt(squared);
                float3 move = gradient * (-value / squared);
                float moved = sqrt(dot(move, move));
                if (moved > limit) { move *= limit / moved; }
                position += move;
            }
        }
        uint vertexNumber = slotVertex[slot];
        positions[vertexNumber] = float4(position, 0.0f);
        normals[vertexNumber] = float4(normal, 0.0f);
    }
    """

    static let emit = """

    StructuredBuffer<uint> bricks : register(t0, space0);
    StructuredBuffer<float> samples : register(t1, space0);
    StructuredBuffer<uint> cubeTable : register(t2, space0);
    StructuredBuffer<uint> keys : register(t3, space0);
    StructuredBuffer<uint> slotVertex : register(t4, space0);
    RWStructuredBuffer<uint> counters : register(u0, space1);
    RWStructuredBuffer<uint> indices : register(u1, space1);
    """ + common + cubes + """

    uint vertexOfKey(uint key) {
        uint slot = tableHash(key, gMask);
        for (uint probe = 0u; probe <= gMask; ++probe) {
            if (keys[slot] == key) { return slotVertex[slot]; }
            slot = (slot + 1u) & gMask;
        }
        return 0u;
    }

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint gid = id.x;
        if (gid >= gBrickCount * CUBES) { return; }
        uint b = gid / CUBES, c = gid % CUBES;
        uint x = c % BRICK, y = (c / BRICK) % BRICK, z = c / (BRICK * BRICK);
        uint pattern = cubePattern(b * POINTS, x, y, z);
        uint begin = cubeTable[CUBE_STARTS + pattern], end = cubeTable[CUBE_STARTS + pattern + 1u];
        if (begin == end) { return; }
        uint at = (gFirstBrick + b) * 3u;
        uint lx = bricks[at] * BRICK + x, ly = bricks[at + 1u] * BRICK + y, lz = bricks[at + 2u] * BRICK + z;
        uint place;
        InterlockedAdd(counters[COUNTER_TRIANGLE_CURSOR], (end - begin) / 3u, place);
        for (uint corner = 0u; corner < end - begin; ++corner) {
            uint edge = cubeTable[CUBE_EDGES + begin + corner];
            indices[place * 3u + corner] = vertexOfKey(edgeKeyOf(lx, ly, lz, cubeTable[CUBE_LOWER + edge], cubeTable[CUBE_UPPER + edge]));
        }
    }
    """
}
```
`mesh_place` and `mesh_sample` declare their own buffers from slot 2 (the packed floats and ints are 0 and 1, declared by `withSDF`). `mesh_number` names its local `vertexNumber`: `number` is not reserved in HLSL, but it shadows nothing that way.

Replace `HLSLKernels.sources(sdf:)` with:
```swift
    static func sources(sdf: String) -> [ImplicitKernel: KernelSource] {
        let prelude = HLSLShaderLibrary.prelude
        let shape = HLSLShaderLibrary.withSDF(sdf)
        let texts: [ImplicitKernel: String] = [
            .evaluate: prelude + shape + HLSLShaderLibrary.evaluate,
            .sample: prelude + shape + HLSLMeshShaderLibrary.sample,
            .place: prelude + shape + HLSLMeshShaderLibrary.place,
            .clear: prelude + HLSLMeshShaderLibrary.clear,
            .classify: prelude + HLSLMeshShaderLibrary.classify,
            .number: prelude + HLSLMeshShaderLibrary.number,
            .emit: prelude + HLSLMeshShaderLibrary.emit,
        ]
        return texts.reduce(into: [:]) { $0[$1.key] = KernelSource(kernel: $1.key, text: $1.value) }
    }
```

- [ ] **Step 3: Run.** `swift test --filter CreatorImplicitTests.HLSLSourceTests 2>&1 | tail -3` — PASS (the register, rules and entry-point tests now check seven kernels per fixture).

- [ ] **Step 4: Lint, commit** (`feat(implicit): the meshing kernels in HLSL, a source per kernel (xp-c task 2)`).

---

### Task 3: Compile the generated HLSL now, offline, with the build-time SDL_shadercross

Proves DXC takes the generator's output before XP-G25 exists, and gives tasks 4 to 9 compiled kernels to run: SPIR-V on lavapipe, MSL on this Mac.

**Files:**
- Create: `Tests/CreatorImplicitTests/Support/GeneratedKernels.swift`, `Tests/CreatorImplicitTests/GeneratedKernelExport.swift`, `Tests/CreatorImplicitTests/GeneratedKernelBuildTests.swift`, `scripts/compile-generated-kernels.sh`
- Modify: `scripts/linux-test.sh` (a `kernels` verb; `test` and `all` run it first)

**Interfaces:**
- Consumes: `ImplicitCompiler.compileHLSL`, `KernelSource.digest` (tasks 1, 2).
- Produces: `.build/generated-kernels/source/<digest>.comp.hlsl` and `.build/generated-kernels/compiled/<digest>.comp.{spv,dxil,msl,json}` in the worktree (git-ignored by `/.build`); `GeneratedKernels.compiled: URL`, `.sources(for:) -> [KernelSource]`, `.solids` (every solid any GPU test or bench compiles, by shape).

- [ ] **Step 1: The list of shapes and the export.**

`Tests/CreatorImplicitTests/Support/GeneratedKernels.swift`:
```swift
import CreatorGeometry
import Foundation
@testable import CreatorImplicit

/// The HLSL kernels the tests run before MetalUI's run-time compiler exists (plan xp-c, task 3; gap XP-G25): every shape a GPU test or bench uses,
/// its seven sources exported as `<digest>.comp.hlsl` and compiled offline in the Linux image by the build-time SDL_shadercross
/// (`scripts/linux-test.sh kernels`) into `.build/generated-kernels/compiled`. A shape not in `solids` has no compiled kernel and its test fails
/// naming the script: add the shape here.
enum GeneratedKernels {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/generated-kernels")
    static let source = root.appending(path: "source")
    static let compiled = root.appending(path: "compiled")
    static let remedy = "run XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh kernels"

    /// Every solid whose shape a GPU test or bench compiles (numbers do not matter: a shape is its source).
    static var solids: [(name: String, solid: ImplicitSolid)] {
        let ball = ImplicitSolid.sphere(radius: 10)
        let move = RigidMove(origin: Vector3(4_000, -3_000, 2_500), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        return GPUFixtures.all + LatticeFixtures.everyMapped + ImplicitFixtures.all + [
            ("sphere", ball), ("moved sphere", .moved(ball, move)), ("box", .box(halfSize: Vector3(1, 1, 1), cornerRadius: 0)),
            ("bench sheet", ImplicitBenchHLSL.sheet(wall: 3)),
        ]
    }

    /// The distinct kernel sources of `solids`.
    static var sources: [KernelSource] {
        var seen: Set<String> = []
        var all: [KernelSource] = []
        for (_, solid) in solids {
            guard let compiled = try? ImplicitCompiler.compileHLSL(solid) else { continue }
            for kernel in ImplicitKernel.allCases {
                guard let source = compiled.kernels[kernel], seen.insert(source.digest).inserted else { continue }
                all.append(source)
            }
        }
        return all
    }
}
```
`ImplicitBenchHLSL.sheet(wall:)` is task 9's; until then leave that line out and add it in task 9 step 1.

`Tests/CreatorImplicitTests/GeneratedKernelExport.swift`:
```swift
import Foundation
import Testing
@testable import CreatorImplicit

/// Writes `GeneratedKernels.sources` to `.build/generated-kernels/source` (only with `XP_EXPORT_KERNELS=1`: `scripts/linux-test.sh kernels` runs
/// it), each `<digest>.comp.hlsl`. A file that exists with the same name is the same text (the name is its digest) and is left alone.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XP_EXPORT_KERNELS"] == "1", "set XP_EXPORT_KERNELS=1"))
struct GeneratedKernelExport {
    @Test func exportEveryKernelSource() throws {
        try FileManager.default.createDirectory(at: GeneratedKernels.source, withIntermediateDirectories: true)
        for source in GeneratedKernels.sources {
            let file = GeneratedKernels.source.appending(path: "\(source.digest).comp.hlsl")
            if !FileManager.default.fileExists(atPath: file.path) { try Data(source.text.utf8).write(to: file) }
        }
    }
}
```

- [ ] **Step 2: The offline compile.** `scripts/compile-generated-kernels.sh`:
```bash
#!/bin/bash
# Compiles the implicit engine's generated HLSL kernels offline (plan xp-c, task 3), until MetalUI's run-time compiler (gap XP-G25) compiles them
# while the app runs: the sources GeneratedKernelExport wrote to .build/generated-kernels/source become SPIR-V, DXIL, MSL and reflection JSON in
# .build/generated-kernels/compiled, through MetalUI's MetalUICompileShaders and the pinned SDL_shadercross (scripts/shadercross.env), as
# scripts/build-shaders.sh compiles the viewport's. Only the sources not compiled yet are compiled (a name is its text's digest). Run in the Linux image
# by scripts/linux-test.sh kernels. A source DXC refuses stops the script naming it: that is a generator bug, never a test to skip.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
. scripts/shadercross.env
SHADERCROSS=${SHADERCROSS:-/opt/shadercross/bin/shadercross}
[ -x "$SHADERCROSS" ] || { echo "scripts/compile-generated-kernels.sh: SDL_shadercross ($SHADERCROSS_COMMIT) was not found at $SHADERCROSS" >&2; exit 69; }
METALUI=$(cd "$ROOT/../MetalUI" && pwd -P)
SCRATCH=${METALUI_TOOLS_SCRATCH:-$ROOT/.build/metalui-tools}
KERNELS=$ROOT/.build/generated-kernels
STAGE=$KERNELS/stage
mkdir -p "$KERNELS/compiled"
rm -rf "$STAGE" && mkdir -p "$STAGE"
shopt -s nullglob
for source in "$KERNELS"/source/*.comp.hlsl; do
    stem=$(basename "$source" .hlsl)
    [ -s "$KERNELS/compiled/$stem.json" ] || cp "$source" "$STAGE/"
done
count=$(find "$STAGE" -name '*.comp.hlsl' | wc -l | tr -d ' ')
if [ "$count" = 0 ]; then echo "The generated kernels are compiled."; exit 0; fi
echo "Compiling $count generated kernels..."
start=$(date +%s.%N)
swift run --package-path "$METALUI" --scratch-path "$SCRATCH" MetalUICompileShaders --no-marker \
    --shadercross "$SHADERCROSS" --source "$STAGE" --out "$STAGE/out"
end=$(date +%s.%N)
cp "$STAGE"/out/* "$KERNELS/compiled/"
echo "COMPILE-TIME $count kernels in $(echo "$end - $start" | bc) s"
```
`MetalUICompileShaders` takes `--no-marker` (MetalUI `packaging.md` §4a): the merged directory has no `SOURCE.sha256`, and `SDLGPUShaderLibrary(directory:)` accepts it by its reflection files (ruling `BS-E`).

In `scripts/linux-test.sh`: add to the usage comment `#     kernels exports the implicit engine's generated HLSL kernels and compiles them offline into .build/generated-kernels (plan xp-c; until MetalUI XP-G25)`; add
```bash
# The implicit engine's generated kernels, compiled offline for the tests (plan xp-c, task 3): export them with the test target, then compile the new ones.
compile_kernels() {
    in_container 'XP_EXPORT_KERNELS=1 swift test --scratch-path /build --filter GeneratedKernelExport >/dev/null \
        && METALUI_TOOLS_SCRATCH=/build/metalui-tools scripts/compile-generated-kernels.sh'
}
```
after `compile_shaders`; call `compile_kernels || return 1` after `compile_shaders` in `do_test` (before the counted run) and add `kernels) compile_shaders && compile_kernels ;;` to the `case`, and `kernels` to the usage and error lines.

- [ ] **Step 3: The build check.** `Tests/CreatorImplicitTests/GeneratedKernelBuildTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorImplicit

/// Every generated kernel of every test shape compiled offline (plan xp-c, task 3): DXC took the generator's output, and each reflection has the
/// buffers `ImplicitKernel.bindings` says. Required on Linux (the test step compiles them first); on a Mac where `scripts/linux-test.sh kernels` ran.
struct GeneratedKernelBuildTests {
    @Test func everyGeneratedKernelCompiledWithItsBindings() throws {
        #if canImport(MetalUISDLGPU)
        let required = true
        #else
        let required = false
        #endif
        guard required || FileManager.default.fileExists(atPath: GeneratedKernels.compiled.path) else { return }
        for source in GeneratedKernels.sources {
            let stem = GeneratedKernels.compiled.appending(path: "\(source.digest).comp")
            for blob in ["spv", "dxil", "msl"] {
                let size = (try? Data(contentsOf: stem.appendingPathExtension(blob)).count) ?? 0
                #expect(size > 0, "\(source.kernel.rawValue) \(source.digest).\(blob) is missing: \(GeneratedKernels.remedy)")
            }
            let reflection = (try? JSONSerialization.jsonObject(with: Data(contentsOf: stem.appendingPathExtension("json")))) as? [String: Int]
            #expect(reflection?["readonly_storage_buffers"] == source.kernel.bindings.readOnly, "\(source.kernel.rawValue): a read-only buffer was dropped")
            #expect(reflection?["readwrite_storage_buffers"] == source.kernel.bindings.readWrite, "\(source.kernel.rawValue): a read-write buffer was dropped")
            #expect(reflection?["uniform_buffers"] == 1 && reflection?["threadcount_x"] == ImplicitKernel.threadsPerGroup)
        }
    }
}
```

- [ ] **Step 4: Run.**
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh kernels 2>&1 | tail -3     # COMPILE-TIME N kernels in S s
ls .build/generated-kernels/compiled | wc -l                                                  # 4 files a kernel
swift test --filter CreatorImplicitTests.GeneratedKernelBuildTests 2>&1 | tail -2
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter GeneratedKernelBuildTests 2>&1 | tail -2
```
Expected: PASS. A DXC error names the `<digest>.comp.hlsl`; open it in `.build/generated-kernels/source`, find the line, fix the generator or the library (never the test). Keep the `COMPILE-TIME` line for task 9 (x-3o).

- [ ] **Step 5: Lint, commit** (`test(implicit): compile every generated HLSL kernel offline with the pinned shadercross (xp-c task 3)`).

---

### Task 4: The compute backend, `HLSLImplicitEngine`'s evaluation and pipeline cache, and the Mac's MSL backend

**Files:**
- Create: `Sources/CreatorImplicit/GPU/ImplicitEngineAvailability.swift`, `Sources/CreatorImplicit/Compute/ImplicitComputeBackend.swift`, `ComputeBatch.swift`, `ComputeBytes.swift`, `HLSLImplicitEngine.swift`, `HLSLImplicitEngine+Meshing.swift` (a placeholder until task 6)
- Modify: `Sources/CreatorImplicit/GPU/ImplicitGPUEngine.swift` (`availability`)
- Create (tests): `Support/MSLComputeBackend.swift`, `Support/MSLComputeBuffer.swift`, `Support/MSLComputePipeline.swift`, `Support/GPUEnginesUnderTest.swift`, `HLSLEngineTests.swift`, `MetalEngineDispatchTests.swift` (moved)
- Modify (tests): `GPUAgreementTests.swift`

**Interfaces:**
- Consumes: `ImplicitCompiler.compileHLSL`, `CompiledImplicit.kernels`, `KernelSource`, `KernelParameters`, `ImplicitKernel` (tasks 1, 2); `GeneratedKernels.compiled` (task 3).
- Produces:
  - `public protocol ComputeBuffer: AnyObject, Sendable { var length: Int { get } }`; `public protocol ComputePipeline: AnyObject, Sendable {}`.
  - `public protocol ImplicitComputeBackend: Sendable { var name: String; var deviceName: String; var largestBuffer: Int; func makeBuffer(length:) throws -> any ComputeBuffer; func makePipeline(_ source: KernelSource) async throws -> any ComputePipeline; func run(_ batch: ComputeBatch) async throws -> [[UInt8]] }`.
  - `public enum ComputeBackendState { ready(any ImplicitComputeBackend), absent(String), broken(String) }`; `ComputeUpload`, `ComputeDispatch { kernel, pipeline, parameters, readOnly, readWrite, threads }`, `ComputeDownload`, `ComputeBatch`.
  - `public enum ImplicitEngineAvailability { available, absent(String), broken(String) }`; `ImplicitGPUEngine.availability { get async }` (default `.available`).
  - `public actor HLSLImplicitEngine: ImplicitGPUEngine` — `init(name:backend:dispatchSize:)`, `pointsPerDispatch = 1 << 20`, `pipelineLimit = 64`, `compileCount`, `setAfterDispatch(_:)`, `backend()`, `pipeline(for:)`, `buffers(for:on:) -> Prepared { floats, ints, parameters, used }`, `epoch`, `meshesMade`.
  - Tests: `GPUEnginesUnderTest.names`, `.engine(_:)`, `.hlsl`, `.makeHLSL(dispatchSize:)`, `.hlslName`, `.hlslState`, `.unavailableReason`.

- [ ] **Step 1: The failing tests.**

Move the Metal-only tests out of `GPUAgreementTests` unchanged into `Tests/CreatorImplicitTests/MetalEngineDispatchTests.swift` (`shapesShareOnePipeline`, `aBatchLargerThanOneDispatchIsAnswered`, `anEmptyBatchAndACancelledOneAreHandled`, `cancelEndsABatchAtItsNextDispatchAndNotTheOnesAfter`, `aBatchOfSeveralSmallDispatchesIsAnsweredInOrder`), inside `#if canImport(Metal)`, `@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device")) struct MetalEngineDispatchTests`, with its imports (`CreatorGeometry`, `Synchronization`, `Testing`, `@testable import CreatorImplicit`).

Replace `GPUAgreementTests.swift` with the suite over every engine:
```swift
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Every GPU engine this machine has against the CPU reference (implicit spec §4.1, §7, Errata D11, D21): every node and every field kind on a fixed
/// point set, within 1e-4 mm. Engines: Metal (a Mac with a device); the HLSL engine as "Metal (HLSL)" on a Mac where `scripts/linux-test.sh kernels`
/// compiled the generated kernels, as "Vulkan" on Linux and "Direct3D 12" on Windows over SDL_GPU. With none the suite is skipped, by name.
@Suite(.enabled(if: !GPUEnginesUnderTest.names.isEmpty, "needs a GPU engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct GPUAgreementTests {
    static let tolerance = 1e-4

    @Test(arguments: GPUEnginesUnderTest.names, GPUFixtures.all.map(\.name))
    func theGPUAgreesWithTheCPU(_ engineName: String, _ name: String) async throws {
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid))
        let gpu = try await evaluator.evaluate(GPUFixtures.points)
        let cpu = solid.signedDistances(at: GPUFixtures.points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        #expect(gpu.count == cpu.count)
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < Self.tolerance, "\(engineName), \(name): the largest difference is \(worst) mm")
        #expect(evaluator.engineName == engine.name)
    }

    @Test(arguments: GPUEnginesUnderTest.names, LatticeFixtures.everyMapped.map(\.name))
    func mappedLatticesAgreeNextToTheSingularSetAndTheCut(_ engineName: String, _ name: String) async throws {
        let solid = try #require(LatticeFixtures.everyMapped.first { $0.name == name }?.solid)
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let centre = LatticeFixtures.crossing
        let random = SeededRandom(seed: 17, stream: 6)
        var points: [SIMD3<Float>] = (0..<400).map { index in
            SIMD3(Float(centre.x + 6 * random.unit(at: 3 * index) - 3), Float(centre.y + 6 * random.unit(at: 3 * index + 1) - 3),
                  Float(28 * random.unit(at: 3 * index + 2) - 14))
        }
        points += (0..<200).map { index in
            SIMD3(Float(centre.x) - 0.5 - Float(index) * 0.05, Float(centre.y) + (index % 2 == 0 ? 1e-3 : -1e-3), Float(index % 20) - 10)
        }
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid))
        let gpu = try await evaluator.evaluate(points)
        let cpu = solid.signedDistances(at: points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < Self.tolerance, "\(engineName), \(name): the largest difference is \(worst) mm")
    }
}
```
(The Metal cases run exactly as before: `engine.compile(solid)` is `ImplicitCompiler.compile` for Metal.)

`Tests/CreatorImplicitTests/HLSLEngineTests.swift` (mirrors `MetalEngineDispatchTests` for the HLSL engine):
```swift
import CreatorGeometry
import Synchronization
import Testing
@testable import CreatorImplicit

/// The HLSL engine's dispatching and pipeline cache (plan xp-c), the same code over every backend; skipped, by name, where there is none.
@Suite(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs the HLSL engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct HLSLEngineTests {
    /// Review Focus 3: one pipeline a shape, and a number edit compiles nothing.
    @Test func shapesShareOnePipelineAndANumberEditRecompilesNothing() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        let first = try ImplicitCompiler.compileHLSL(.sphere(radius: 5))
        let second = try ImplicitCompiler.compileHLSL(.sphere(radius: 25))
        try await engine.prepare(first)
        try await engine.prepare(second)
        #expect(await engine.compileCount == 1)
        let values = try await GPUBatchEvaluator(engine: engine, program: second).evaluate([SIMD3(30, 0, 0)])
        #expect(abs(values[0] - 5) < 1e-5, "the numbers still differ")
        try await engine.prepare(try ImplicitCompiler.compileHLSL(.box(halfSize: Vector3(1, 1, 1), cornerRadius: 0)))
        #expect(await engine.compileCount == 2)
    }

    @Test func aBatchOfSeveralSmallDispatchesIsAnsweredInOrder() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL(dispatchSize: 1_000))
        let program = try await engine.compile(.sphere(radius: 5))
        let points = (0..<2_500).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let values = try await engine.evaluate(program, at: points)
        #expect(values.count == points.count)
        for index in [0, 999, 1_000, 2_499] { #expect(abs(values[index] - Float(index % 100 - 5)) < 1e-5) }
    }

    @Test func anEmptyBatchAndACancelledOneAreHandled() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(.sphere(radius: 5)))
        #expect(try await evaluator.evaluate([]).isEmpty)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await evaluator.evaluate([SIMD3(1, 2, 3)])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancelEndsABatchAtItsNextDispatchAndNotTheOnesAfter() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL(dispatchSize: 1_000))
        let program = try await engine.compile(.sphere(radius: 5))
        let points = (0..<3_500).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let dispatches = Mutex(0)
        await engine.setAfterDispatch { count in
            dispatches.withLock { $0 = count }
            if count == 1 { await engine.cancel() }
        }
        await #expect(throws: CancellationError.self) { _ = try await engine.evaluate(program, at: points) }
        #expect(dispatches.withLock { $0 } == 1, "the second dispatch did not run")
        await engine.setAfterDispatch(nil)
        let whole = try await engine.evaluate(program, at: points)
        #expect(whole.count == points.count && abs(whole[3_499] - Float(3_499 % 100 - 5)) < 1e-5)
    }

    @Test func aMetalCompiledSolidIsNotThisEngines() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        await #expect(throws: ImplicitCompileError.self) { try await engine.prepare(try ImplicitCompiler.compile(.sphere(radius: 1))) }
    }

    /// Review Focus 5: the angle exactly on a mapping's cut and at its axis.
    @Test(arguments: LatticeFixtures.mappedAll.map(\.name))
    func theAngleOnTheCutAndAtTheAxisAgreesWithTheCPU(_ name: String) async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let solid = try #require(LatticeFixtures.mappedAll.first { $0.name == name }?.solid)
        let centre = LatticeFixtures.crossing
        var points: [SIMD3<Float>] = []
        for step in 0..<40 {
            let along = Float(step) * 0.25 - 5
            points.append(SIMD3(Float(centre.x) + along, Float(centre.y), Float(step % 9) - 4))
            points.append(SIMD3(Float(centre.x), Float(centre.y), along))
        }
        let gpu = try await GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid)).evaluate(points)
        let cpu = solid.signedDistances(at: points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < GPUAgreementTests.tolerance, "\(name): the largest difference is \(worst) mm")
    }
}
```
Run: `swift test --filter "CreatorImplicitTests.(GPUAgreementTests|HLSLEngineTests|MetalEngineDispatchTests)" 2>&1 | tail -3` — build failure.

- [ ] **Step 2: The protocol, the batch and the bytes.**

`Sources/CreatorImplicit/GPU/ImplicitEngineAvailability.swift`:
```swift
/// Whether a GPU engine can run here (plan xp-c, X-C4), asked by `ImplicitEvaluators.make` before it compiles.
public enum ImplicitEngineAvailability: Sendable, Equatable {
    case available
    /// No GPU for it: the CPU runs and nobody is told, as on a machine with no GPU engine.
    case absent(String)
    /// It should run and cannot (the compiler library is missing, a pipeline was refused): the CPU runs and the person is told, with the reason.
    case broken(String)
}
```
In `ImplicitGPUEngine.swift`: add `var availability: ImplicitEngineAvailability { get async }` to the protocol (documented "Whether this engine can run here (plan xp-c); asked before `compile`; the default is `.available`") and `public var availability: ImplicitEngineAvailability { .available }` to its extension; in the doc comment say `MetalImplicitEngine` is macOS's and `HLSLImplicitEngine` Linux's and Windows' (xp-c).

`Sources/CreatorImplicit/Compute/ImplicitComputeBackend.swift`:
```swift
/// A GPU buffer a backend made.
public protocol ComputeBuffer: AnyObject, Sendable {
    var length: Int { get }
}

/// A compiled kernel a backend made from a `KernelSource`.
public protocol ComputePipeline: AnyObject, Sendable {}

/// What `HLSLImplicitEngine` needs from a GPU API (plan xp-c): buffers, pipelines from kernel sources, and one batch at a time. SDL_GPU on Linux and
/// Windows (`SDLComputeBackend`); in the tests on a Mac, Metal running the MSL of the same HLSL (`MSLComputeBackend`). Nothing here blocks a thread.
public protocol ImplicitComputeBackend: Sendable {
    /// The engine's name for the badge: "Vulkan", "Direct3D 12", "Metal (HLSL)".
    var name: String { get }
    var deviceName: String { get }
    /// The largest storage buffer, in bytes, the engine may make.
    var largestBuffer: Int { get }
    /// A storage buffer of at least `length` bytes; `ImplicitCompileError.unsupported` past `largestBuffer` (that request is the CPU's).
    func makeBuffer(length: Int) throws -> any ComputeBuffer
    /// `source` compiled for this device. Throws `ImplicitCompileError.engine` with the compiler's or the driver's text.
    func makePipeline(_ source: KernelSource) async throws -> any ComputePipeline
    /// The batch in one command buffer: its uploads, each dispatch in a compute pass of its own (SDL_GPU does not synchronize dispatches within one
    /// pass), its downloads; awaits the GPU and returns each download's bytes in order.
    func run(_ batch: ComputeBatch) async throws -> [[UInt8]]
}

/// A backend, or why there is none.
public enum ComputeBackendState: Sendable, CustomStringConvertible {
    case ready(any ImplicitComputeBackend)
    case absent(String)
    case broken(String)

    public var description: String {
        switch self {
        case .ready(let backend): "ready: \(backend.name) on \(backend.deviceName)"
        case .absent(let why): "absent: \(why)"
        case .broken(let why): "broken: \(why)"
        }
    }
}
```

`Sources/CreatorImplicit/Compute/ComputeBatch.swift`:
```swift
public struct ComputeUpload: Sendable {
    public var bytes: [UInt8]
    public var buffer: any ComputeBuffer
    public var offset: Int

    public init(bytes: [UInt8], buffer: any ComputeBuffer, offset: Int = 0) {
        self.bytes = bytes
        self.buffer = buffer
        self.offset = offset
    }
}

/// One kernel over `threads` threads (rounded up to groups of 64; the kernels ignore the extra ones), its storage buffers in declaration order.
public struct ComputeDispatch: Sendable {
    public var kernel: ImplicitKernel
    public var pipeline: any ComputePipeline
    public var parameters: KernelParameters
    public var readOnly: [any ComputeBuffer]
    public var readWrite: [any ComputeBuffer]
    public var threads: Int

    public init(kernel: ImplicitKernel, pipeline: any ComputePipeline, parameters: KernelParameters, readOnly: [any ComputeBuffer],
                readWrite: [any ComputeBuffer], threads: Int) {
        self.kernel = kernel
        self.pipeline = pipeline
        self.parameters = parameters
        self.readOnly = readOnly
        self.readWrite = readWrite
        self.threads = threads
    }
}

public struct ComputeDownload: Sendable {
    public var buffer: any ComputeBuffer
    public var length: Int

    public init(buffer: any ComputeBuffer, length: Int) {
        self.buffer = buffer
        self.length = length
    }
}

/// One command buffer's work.
public struct ComputeBatch: Sendable {
    public var uploads: [ComputeUpload]
    public var dispatches: [ComputeDispatch]
    public var downloads: [ComputeDownload]

    public init(uploads: [ComputeUpload] = [], dispatches: [ComputeDispatch] = [], downloads: [ComputeDownload] = []) {
        self.uploads = uploads
        self.dispatches = dispatches
        self.downloads = downloads
    }

    /// Every dispatch lists the buffers its kernel declares and fits in 65,535 groups (the backends check before they record).
    var isWellFormed: Bool {
        dispatches.allSatisfy { dispatch in
            dispatch.readOnly.count == dispatch.kernel.bindings.readOnly && dispatch.readWrite.count == dispatch.kernel.bindings.readWrite
                && (dispatch.threads + ImplicitKernel.threadsPerGroup - 1) / ImplicitKernel.threadsPerGroup <= ComputeBytes.maximumGroups
        }
    }
}
```

`Sources/CreatorImplicit/Compute/ComputeBytes.swift`:
```swift
/// The engine's synchronous byte work: packing for an upload, reading back, cutting a count into ranges. Synchronous on purpose (the Windows Swift 6.4
/// compiler asserts on an `async` function that holds a loop's locals across an `await`).
enum ComputeBytes {
    /// The most thread groups one dispatch has (Vulkan's guaranteed `maxComputeWorkGroupCount`; gap XP-G24).
    static let maximumGroups = 65_535

    static func bytes<Value>(of values: [Value]) -> [UInt8] {
        values.withUnsafeBytes { Array($0) }
    }

    /// Points as three floats each (`SIMD3<Float>` is 16 bytes; Metal's kernel reads `packed_float3`).
    static func packed(_ points: ArraySlice<SIMD3<Float>>) -> [UInt8] {
        var flat: [Float] = []
        flat.reserveCapacity(points.count * 3)
        for point in points {
            flat.append(point.x)
            flat.append(point.y)
            flat.append(point.z)
        }
        return bytes(of: flat)
    }

    static func values<Value: BitwiseCopyable>(_ bytes: [UInt8], as type: Value.Type) -> [Value] {
        let count = bytes.count / MemoryLayout<Value>.stride
        return [Value](unsafeUninitializedCapacity: count) { buffer, initialized in
            bytes.withUnsafeBytes { raw in
                UnsafeMutableRawBufferPointer(buffer).copyMemory(from: UnsafeRawBufferPointer(rebasing: raw[0..<(count * MemoryLayout<Value>.stride)]))
            }
            initialized = count
        }
    }

    static func ranges(count: Int, size: Int) -> [Range<Int>] {
        stride(from: 0, to: count, by: max(1, size)).map { $0..<min($0 + max(1, size), count) }
    }
}
```

- [ ] **Step 3: The engine, mirroring `MetalImplicitEngine`.** `Sources/CreatorImplicit/Compute/HLSLImplicitEngine.swift`:
```swift
import Foundation

/// The GPU engine of Linux and Windows (plan xp-c; cross-platform erratum E8, implicit erratum D21), built as `MetalImplicitEngine` is: a solid's HLSL
/// (`ImplicitCompiler.compileHLSL`, the Metal walk in the HLSL dialect) is compiled while the app runs, one pipeline per kernel source, cached by the
/// source's digest (the least recently used of 64 dropped, as Metal's); a few compiled solids keep their buffers. The backend is made on first use,
/// inside the actor, so the device is never made on the main actor.
public actor HLSLImplicitEngine: ImplicitGPUEngine {
    /// A solid's uploaded buffers (the five of Metal's, packed in two) and the uniform block's solid-specific words.
    struct Prepared: Sendable {
        var floats: any ComputeBuffer
        var ints: any ComputeBuffer
        var parameters: KernelParameters
        var used: Int
    }

    public nonisolated let name: String
    private let makeBackend: @Sendable () -> ComputeBackendState
    private var state: ComputeBackendState?
    private var pipelines: [String: (pipeline: any ComputePipeline, used: Int)] = [:]
    private var prepared: [UUID: Prepared] = [:]
    private var clock = 0

    private static let preparedLimit = 8
    /// How many evaluation pipelines are kept (Metal's `pipelineLimit`).
    static let pipelineLimit = 64
    /// The most points one dispatch takes (Metal's is 2^22; an SDL dispatch has at most 65,535 groups of 64).
    public static let pointsPerDispatch = 1 << 20

    /// Evaluation pipelines compiled (a cache hit doesn't count), as `MetalImplicitEngine.compileCount`.
    public private(set) var compileCount = 0
    /// The meshing pipelines by digest (`+Meshing`), kept like Metal's mesh pipelines; the four that do not call `sdf` are shared by every shape.
    var meshPipelineCache: [String: any ComputePipeline] = [:]
    public internal(set) var meshCompileCount = 0
    public internal(set) var meshesMade = 0
    var meshTuning = MeshTuning()
    var epoch = 0
    let dispatchSize: Int
    private var afterDispatch: (@Sendable (Int) async -> Void)?

    public init(name: String, backend: @escaping @Sendable () -> ComputeBackendState, dispatchSize: Int = pointsPerDispatch) {
        self.name = name
        makeBackend = backend
        self.dispatchSize = max(1, min(dispatchSize, Self.pointsPerDispatch))
    }

    func setAfterDispatch(_ hook: (@Sendable (Int) async -> Void)?) {
        afterDispatch = hook
    }

    private func resolvedState() -> ComputeBackendState {
        if let state { return state }
        let made = makeBackend()
        state = made
        return made
    }

    func backend() throws(ImplicitCompileError) -> any ImplicitComputeBackend {
        switch resolvedState() {
        case .ready(let backend): return backend
        case .absent(let why): throw .unsupported(why)
        case .broken(let why): throw .engine(why)
        }
    }

    public var availability: ImplicitEngineAvailability {
        switch resolvedState() {
        case .ready: .available
        case .absent(let why): .absent(why)
        case .broken(let why): .broken(why)
        }
    }

    public var deviceName: String {
        if case .ready(let backend) = resolvedState() { return backend.deviceName }
        return name
    }

    public func compile(_ solid: ImplicitSolid) async throws(ImplicitCompileError) -> CompiledImplicit {
        let program = try ImplicitCompiler.compileHLSL(solid)
        try await prepare(program)
        return program
    }

    /// Compiles `program`'s evaluation kernel if no solid of its shape has been.
    public func prepare(_ program: CompiledImplicit) async throws(ImplicitCompileError) {
        _ = try await evaluationPipeline(for: program)
    }

    private func evaluationPipeline(for program: CompiledImplicit) async throws(ImplicitCompileError) -> any ComputePipeline {
        guard program.language == .hlsl, let source = program.kernels[.evaluate] else {
            throw .unsupported("a solid compiled for Metal, not HLSL")
        }
        clock += 1
        if let known = pipelines[source.digest] {
            pipelines[source.digest] = (known.pipeline, clock)
            return known.pipeline
        }
        let backend = try backend()
        let made: any ComputePipeline
        do {
            made = try await backend.makePipeline(source)
        } catch let error as ImplicitCompileError {
            throw error
        } catch {
            throw .engine(String(describing: error))
        }
        // A second compile of the same shape that finished first is the one kept, and only the one kept is counted (as Metal's).
        if let raced = pipelines[source.digest] { return raced.pipeline }
        compileCount += 1
        clock += 1
        pipelines[source.digest] = (made, clock)
        if pipelines.count > Self.pipelineLimit, let oldest = pipelines.min(by: { $0.value.used < $1.value.used })?.key {
            pipelines[oldest] = nil
        }
        return made
    }

    public func evaluate(_ program: CompiledImplicit, at points: [SIMD3<Float>]) async throws -> [Float] {
        try Task.checkCancellation()
        guard !points.isEmpty else { return [] }
        let started = epoch
        let pipeline = try await evaluationPipeline(for: program)
        let backend = try backend()
        let solid = try await buffers(for: program, on: backend)
        let size = min(points.count, dispatchSize)
        let input = try backend.makeBuffer(length: size * 12)
        let output = try backend.makeBuffer(length: size * 4)
        var values: [Float] = []
        values.reserveCapacity(points.count)
        let ranges = ComputeBytes.ranges(count: points.count, size: dispatchSize)
        for index in ranges.indices {
            try Task.checkCancellation()
            if epoch != started { throw CancellationError() }
            let read = try await backend.run(Self.evaluation(points[ranges[index]], pipeline, solid, input, output))
            values += read.first.map { ComputeBytes.values($0, as: Float.self) } ?? []
            await afterDispatch?(index + 1)
        }
        return values
    }

    private static func evaluation(_ points: ArraySlice<SIMD3<Float>>, _ pipeline: any ComputePipeline, _ solid: Prepared,
                                   _ input: any ComputeBuffer, _ output: any ComputeBuffer) -> ComputeBatch {
        var parameters = solid.parameters
        parameters.count = UInt32(points.count)
        return ComputeBatch(
            uploads: [ComputeUpload(bytes: ComputeBytes.packed(points), buffer: input)],
            dispatches: [ComputeDispatch(kernel: .evaluate, pipeline: pipeline, parameters: parameters, readOnly: [solid.floats, solid.ints, input],
                                         readWrite: [output], threads: points.count)],
            downloads: [ComputeDownload(buffer: output, length: points.count * 4)])
    }

    public func cancel() {
        epoch += 1
    }

    /// The solid's buffers, uploaded on first use; the least recently used solid's are dropped past `preparedLimit`.
    func buffers(for program: CompiledImplicit, on backend: any ImplicitComputeBackend) async throws -> Prepared {
        clock += 1
        if var known = prepared[program.id] {
            known.used = clock
            prepared[program.id] = known
            return known
        }
        let floats = program.parameters + program.pool + program.images
        let ints = program.integers + program.tables
        var parameters = KernelParameters()
        parameters.poolBase = UInt32(program.parameters.count)
        parameters.imagesBase = UInt32(program.parameters.count + program.pool.count)
        parameters.tablesBase = UInt32(program.integers.count)
        let entry = Prepared(floats: try backend.makeBuffer(length: floats.count * 4), ints: try backend.makeBuffer(length: ints.count * 4),
                             parameters: parameters, used: clock)
        _ = try await backend.run(ComputeBatch(uploads: [
            ComputeUpload(bytes: ComputeBytes.bytes(of: floats), buffer: entry.floats),
            ComputeUpload(bytes: ComputeBytes.bytes(of: ints), buffer: entry.ints),
        ]))
        prepared[program.id] = entry
        if prepared.count > Self.preparedLimit, let oldest = prepared.min(by: { $0.value.used < $1.value.used })?.key {
            prepared[oldest] = nil
        }
        return entry
    }
}
```
Until task 6, `HLSLImplicitEngine+Meshing.swift` holds only `extension HLSLImplicitEngine { struct MeshTuning: Sendable {} }`. A zero-byte upload is skipped by the backends; `makeBuffer` makes at least 16 bytes.

- [ ] **Step 4: The Mac's backend over the offline MSL, and the engines under test.**

`Tests/CreatorImplicitTests/Support/MSLComputeBuffer.swift` and `MSLComputePipeline.swift` (both wholly under `#if canImport(Metal)`, `@preconcurrency import Metal`, `@testable import CreatorImplicit`):
```swift
/// A Metal buffer as a `ComputeBuffer` (test support). `@unchecked`: an `MTLBuffer` may cross threads; the engine touches its contents only between
/// batches it awaited.
final class MSLComputeBuffer: ComputeBuffer, @unchecked Sendable {
    let buffer: any MTLBuffer
    var length: Int { buffer.length }
    init(_ buffer: any MTLBuffer) { self.buffer = buffer }
}
```
```swift
/// A Metal compute pipeline as a `ComputePipeline` (test support). `MTLComputePipelineState` is thread-safe.
final class MSLComputePipeline: ComputePipeline, @unchecked Sendable {
    let state: any MTLComputePipelineState
    init(_ state: any MTLComputePipelineState) { self.state = state }
}
```

`Tests/CreatorImplicitTests/Support/MSLComputeBackend.swift`:
```swift
#if canImport(Metal)
import Foundation
@preconcurrency import Metal
@testable import CreatorImplicit

/// The HLSL engine on this Mac's GPU, for the tests (plan xp-c, X-C2): a kernel source's MSL, made offline from the generated HLSL by the Linux image's
/// SDL_shadercross (`GeneratedKernels.compiled/<digest>.comp.msl`), bound as SDL_GPU's Metal driver binds it (the uniform block at `[[buffer(0)]]`,
/// then the read-only, then the read-write storage buffers). Absent when the kernels were not compiled; a source not compiled throws, naming the script.
final class MSLComputeBackend: ImplicitComputeBackend, @unchecked Sendable {
    static let state: ComputeBackendState = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return .absent("no Metal device") }
        guard FileManager.default.fileExists(atPath: GeneratedKernels.compiled.path) else {
            return .absent("the generated kernels were not compiled on this Mac: \(GeneratedKernels.remedy)")
        }
        return .ready(MSLComputeBackend(device: device, queue: queue))
    }()

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let name = "Metal (HLSL)"
    /// The SDL backends' cap (gap XP-G24), so the tests reach the same limits.
    let largestBuffer = 1 << 27
    var deviceName: String { device.name }

    private init(device: any MTLDevice, queue: any MTLCommandQueue) {
        self.device = device
        self.queue = queue
    }

    func makeBuffer(length: Int) throws -> any ComputeBuffer {
        guard length <= largestBuffer, let buffer = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else {
            throw ImplicitCompileError.unsupported("a GPU buffer of \(length) bytes")
        }
        return MSLComputeBuffer(buffer)
    }

    func makePipeline(_ source: KernelSource) async throws -> any ComputePipeline {
        let stem = GeneratedKernels.compiled.appending(path: "\(source.digest).comp")
        guard let text = try? String(contentsOf: stem.appendingPathExtension("msl"), encoding: .utf8) else {
            throw ImplicitCompileError.unsupported("\(source.kernel.rawValue) \(source.digest) was not compiled offline: \(GeneratedKernels.remedy)")
        }
        let reflection = (try? JSONSerialization.jsonObject(with: Data(contentsOf: stem.appendingPathExtension("json")))) as? [String: Int]
        guard reflection?["readonly_storage_buffers"] == source.kernel.bindings.readOnly,
              reflection?["readwrite_storage_buffers"] == source.kernel.bindings.readWrite else {
            throw ImplicitCompileError.engine("\(source.digest).comp.json does not match \(source.kernel.rawValue)'s bindings")
        }
        do {
            let library = try await device.makeLibrary(source: text, options: nil)
            guard let function = library.makeFunction(name: "main0") else { throw ImplicitCompileError.engine("\(source.digest): no main0") }
            return MSLComputePipeline(try await device.makeComputePipelineState(function: function))
        } catch let error as ImplicitCompileError {
            throw error
        } catch {
            throw ImplicitCompileError.engine(error.localizedDescription)
        }
    }

    func run(_ batch: ComputeBatch) async throws -> [[UInt8]] {
        guard batch.isWellFormed, let commands = queue.makeCommandBuffer() else { throw ImplicitCompileError.engine("a malformed batch") }
        try record(batch, into: commands)
        await withCheckedContinuation { continuation in
            commands.addCompletedHandler { _ in continuation.resume() }
            commands.commit()
        }
        if let error = commands.error { throw ImplicitCompileError.engine(error.localizedDescription) }
        return batch.downloads.map { download in
            guard let buffer = download.buffer as? MSLComputeBuffer else { return [] }
            return Array(UnsafeRawBufferPointer(start: buffer.buffer.contents(), count: download.length))
        }
    }

    private func record(_ batch: ComputeBatch, into commands: any MTLCommandBuffer) throws {
        for upload in batch.uploads where !upload.bytes.isEmpty {
            guard let buffer = upload.buffer as? MSLComputeBuffer else { throw ImplicitCompileError.engine("a foreign buffer") }
            upload.bytes.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { (buffer.buffer.contents() + upload.offset).copyMemory(from: base, byteCount: bytes.count) }
            }
        }
        for dispatch in batch.dispatches where dispatch.threads > 0 {
            guard let pipeline = dispatch.pipeline as? MSLComputePipeline, let encoder = commands.makeComputeCommandEncoder() else {
                throw ImplicitCompileError.engine("a foreign pipeline")
            }
            encoder.setComputePipelineState(pipeline.state)
            dispatch.parameters.bytes.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setBytes(base, length: bytes.count, index: 0)
            }
            for (slot, buffer) in (dispatch.readOnly + dispatch.readWrite).enumerated() {
                encoder.setBuffer((buffer as? MSLComputeBuffer)?.buffer, offset: 0, index: 1 + slot)
            }
            let groups = (dispatch.threads + ImplicitKernel.threadsPerGroup - 1) / ImplicitKernel.threadsPerGroup
            encoder.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: ImplicitKernel.threadsPerGroup, height: 1, depth: 1))
            encoder.endEncoding()
        }
    }
}
#endif
```

`Tests/CreatorImplicitTests/Support/GPUEnginesUnderTest.swift`:
```swift
import Foundation
@testable import CreatorImplicit

/// The GPU engines this machine can test, by name (plan xp-c): "Metal" on a Mac with a device; the HLSL engine as "Metal (HLSL)" on a Mac where the
/// generated kernels were compiled offline, as "Vulkan" (Linux) and "Direct3D 12" (Windows) over SDL_GPU: on kernels compiled offline until task 11,
/// then compiled at run time as the app does.
enum GPUEnginesUnderTest {
    static let hlslState: ComputeBackendState = {
        #if canImport(MetalUISDLGPU)
        return SDLComputeBackend.make(kernels: SDLPrecompiledKernels(directory: GeneratedKernels.compiled))
        #elseif canImport(Metal)
        return MSLComputeBackend.state
        #else
        return .absent("no backend for the HLSL engine on this platform")
        #endif
    }()

    static var hlslName: String {
        if case .ready(let backend) = hlslState { return backend.name }
        return "HLSL"
    }

    /// A fresh HLSL engine over the shared backend (its own caches, hooks, tuning and epoch), or `nil`.
    static func makeHLSL(dispatchSize: Int = HLSLImplicitEngine.pointsPerDispatch) -> HLSLImplicitEngine? {
        guard case .ready = hlslState else { return nil }
        let state = hlslState
        return HLSLImplicitEngine(name: hlslName, backend: { state }, dispatchSize: dispatchSize)
    }

    static let hlsl: HLSLImplicitEngine? = makeHLSL()

    static let names: [String] = {
        var names: [String] = []
        #if canImport(Metal)
        if MetalImplicitEngine.shared != nil { names.append("Metal") }
        #endif
        if hlsl != nil { names.append(hlslName) }
        return names
    }()

    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    static func engine(_ name: String) throws -> any ImplicitGPUEngine {
        #if canImport(Metal)
        if name == "Metal", let engine = MetalImplicitEngine.shared { return engine }
        #endif
        if name == hlslName, let hlsl { return hlsl }
        throw Missing(description: "no engine named \(name) here")
    }

    static var unavailableReason: String { hlslState.description }
}
```
`SDLComputeBackend` and `SDLPrecompiledKernels` are task 5's: until then write that branch as `#if canImport(MetalUISDLGPU) && false` and drop `&& false` in task 5.

- [ ] **Step 5: Run on the Mac** (the kernels from task 3 must be compiled):
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh kernels
swift test --filter "CreatorImplicitTests.(GPUAgreementTests|HLSLEngineTests|MetalEngineDispatchTests)" 2>&1 | tail -5
```
Expected: PASS, every agreement case for "Metal" and "Metal (HLSL)". A wrong value for one fixture: diff that op's HLSL against `ImplicitShaderLibrary*.swift`; every value 0: a binding order. Then with `.build/generated-kernels` moved aside: the Metal cases pass, `HLSLEngineTests` skips naming the script. `swift test --filter CreatorImplicitTests` — one line, no issue.

- [ ] **Step 6: Asserts toolchain, lint, commit** (`TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release`; `feat(implicit): HLSLImplicitEngine evaluates generated kernels; the Mac runs them over their MSL (xp-c task 4)`).

---

### Task 5: The SDL_GPU backend over kernels compiled offline; availability and the fallbacks

The backend the app will use, with its source of shader bytes behind a protocol: offline-compiled kernels now (lavapipe in the Linux image runs the generated HLSL against the CPU), MetalUI's run-time compiler in task 11. The app's engine off macOS stays the CPU until then.

**Files:**
- Create: `Sources/CreatorImplicit/SDL/SDLComputeBackend.swift`, `SDLComputeRecording.swift`, `SDLComputeBuffer.swift`, `SDLComputePipeline.swift`, `SDLKernelProvider.swift`
- Modify: `Package.swift`, `Sources/CreatorImplicit/GPU/ImplicitEvaluators.swift`
- Modify (tests): `Support/GPUEnginesUnderTest.swift` (drop `&& false`), `Support/StubGPUEngine.swift`, `ImplicitEvaluatorsTests.swift`, `ImplicitPortabilityTests.swift`
- Create (tests): `SDLComputeBackendTests.swift`, `ImplicitGPUAvailabilityTests.swift`

**Interfaces:**
- Produces: `protocol SDLKernelProvider: Sendable { func blob(for source: KernelSource, device: SDLGPUDevice) throws -> SDLGPUShaderBlob }`; `struct SDLPrecompiledKernels: SDLKernelProvider { init(directory: URL) }`; `SDLComputeBackend.make(kernels: any SDLKernelProvider) -> ComputeBackendState`; `SDLComputeBackend.platformName` ("Vulkan" / "Direct3D 12"); `ImplicitEvaluators.make` reads `availability`.

- [ ] **Step 1: The failing tests.**

`StubGPUEngine`: add an `availability: ImplicitEngineAvailability = .available` initializer parameter (last, with its default), stored, and `var availability: ImplicitEngineAvailability { reported }`.

Add to `ImplicitEvaluatorsTests`:
```swift
    /// No device for the engine: the CPU, and nobody is told (X-C4).
    @Test func anAbsentEngineRunsOnTheCPUSilently() async {
        let engine = StubGPUEngine(availability: .absent("no SDL_GPU device"))
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.sphere, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == nil)
        #expect(await engine.prepared == 0, "an absent engine is not asked to compile")
    }

    /// The engine should run and cannot (the compiler library is missing, a pipeline was refused): the CPU with the warning and the reason (X-C4).
    @Test func aBrokenEngineRunsOnTheCPUWithTheWarningAndTheReason() async {
        let engine = StubGPUEngine(availability: .broken("the shader compiler library was not found in /opt/x, ./lib"))
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.sphere, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == ImplicitEvaluators.cpuWarning)
        #expect(selection.diagnostic?.contains("the shader compiler library was not found") == true)
    }
```

`Tests/CreatorImplicitTests/SDLComputeBackendTests.swift`:
```swift
#if canImport(MetalUISDLGPU)
import Foundation
import Testing
@testable import CreatorImplicit

/// The SDL_GPU backend itself (Linux and Windows): a kernel missing from a provider, and a batch's order.
struct SDLComputeBackendTests {
    @Test(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs an SDL_GPU device"))
    func aKernelTheProviderDoesNotHaveIsUnsupportedNamingTheScript() async throws {
        guard case .ready(let backend) = SDLComputeBackend.make(kernels: SDLPrecompiledKernels(directory: FileManager.default.temporaryDirectory))
        else { return }
        let source = try #require(try ImplicitCompiler.compileHLSL(.sphere(radius: 1)).kernels[.evaluate])
        await #expect { _ = try await backend.makePipeline(source) } throws: { String(describing: $0).contains("scripts/linux-test.sh kernels") }
    }

    /// A dispatch sees what the uploads before it wrote, and the download sees what it wrote: each in its own pass.
    @Test(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs an SDL_GPU device"))
    func aBatchsUploadsDispatchesAndDownloadsRunInOrder() async throws {
        guard case .ready(let backend) = GPUEnginesUnderTest.hlslState else { return }
        let program = try ImplicitCompiler.compileHLSL(.sphere(radius: 2))
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        let solid = try await engine.buffers(for: program, on: backend)
        let pipeline = try await backend.makePipeline(try #require(program.kernels[.evaluate]))
        let input = try backend.makeBuffer(length: 24)
        let output = try backend.makeBuffer(length: 8)
        var parameters = solid.parameters
        parameters.count = 2
        let read = try await backend.run(ComputeBatch(
            uploads: [ComputeUpload(bytes: ComputeBytes.bytes(of: [Float](arrayLiteral: 5, 0, 0, 0, 0, 1)), buffer: input)],
            dispatches: [ComputeDispatch(kernel: .evaluate, pipeline: pipeline, parameters: parameters, readOnly: [solid.floats, solid.ints, input],
                                         readWrite: [output], threads: 2)],
            downloads: [ComputeDownload(buffer: output, length: 8)]))
        let values = ComputeBytes.values(try #require(read.first), as: Float.self)
        #expect(values.count == 2 && abs(values[0] - 3) < 1e-6 && abs(values[1] + 1) < 1e-6)
    }
}
#endif
```

`Tests/CreatorImplicitTests/ImplicitGPUAvailabilityTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorImplicit

/// Where the environment promises a GPU (`XP_REQUIRE_GPU=1`: the Linux image's lavapipe, the Windows job's WARP) the HLSL engine must have a backend,
/// so a runner that lost its driver cannot pass the agreement suites by skipping them.
struct ImplicitGPUAvailabilityTests {
    @Test func theHLSLEngineAnswersWhereTheEnvironmentPromisesAGPU() {
        guard ProcessInfo.processInfo.environment["XP_REQUIRE_GPU"] == "1" else { return }
        #if canImport(MetalUISDLGPU) && !os(Windows)
        #expect(GPUEnginesUnderTest.hlsl != nil, "XP_REQUIRE_GPU=1 but \(GPUEnginesUnderTest.unavailableReason)")
        #endif
    }
}
```
Windows is left out (`&& !os(Windows)`) until task 11: the offline kernels are compiled only in the Linux image, so Windows CI has none and its HLSL cases skip by name; task 11 removes it once Windows compiles at run time.

Add to `ImplicitPortabilityTests`:
```swift
    /// SDL_GPU is reached only from `SDL*.swift` files, each wholly under `#if canImport(MetalUISDLGPU)`, and no other file names an `SDLGPU` type.
    @Test func onlyTheSDLFilesReachSDLGPU() {
        for (name, lines) in Self.sources {
            let code = lines.filter { !$0.isEmpty && !$0.hasPrefix("//") }
            if name.hasPrefix("SDL") {
                #expect(code.first == "#if canImport(MetalUISDLGPU)" && code.last == "#endif", "\(name) must be wrapped in #if canImport(MetalUISDLGPU)")
            } else {
                #expect(!code.contains { Self.imports($0) == "MetalUISDLGPU" }, "\(name) imports MetalUISDLGPU")
                for line in code {
                    #expect(line.range(of: #"\bSDLGPU\w*"#, options: .regularExpression) == nil, "\(name) names an SDL_GPU type: \(line)")
                }
            }
        }
    }
```

Run on the Mac (`swift test --filter "CreatorImplicitTests.(ImplicitEvaluatorsTests|ImplicitPortabilityTests)"`): the two availability tests fail. On Linux the build fails (`SDLComputeBackend`).

- [ ] **Step 2: The dependency.** In `Package.swift`, `CreatorImplicit` and `CreatorImplicitTests` gain `metalUISDL, metalUISDLGPU` (both `.when(platforms: [.linux, .windows])` already); update the comment above `CreatorImplicit` ("…the SDL_GPU backend, `Sources/CreatorImplicit/SDL`, plan xp-c, with `#if canImport(MetalUISDLGPU)`") and `metalUISDLGPU`'s ("A dependency of `CreatorViewport`, `CreatorImplicit` and their tests").

- [ ] **Step 3: The backend.**

`Sources/CreatorImplicit/SDL/SDLComputeBuffer.swift`:
```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

final class SDLComputeBuffer: ComputeBuffer {
    let buffer: SDLGPUBuffer
    var length: Int { buffer.size }
    init(_ buffer: SDLGPUBuffer) { self.buffer = buffer }
}
#endif
```
`Sources/CreatorImplicit/SDL/SDLComputePipeline.swift`:
```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

final class SDLComputePipeline: ComputePipeline {
    let pipeline: SDLGPUComputePipeline
    init(_ pipeline: SDLGPUComputePipeline) { self.pipeline = pipeline }
}
#endif
```
`Sources/CreatorImplicit/SDL/SDLKernelProvider.swift`:
```swift
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// Where a kernel source's device bytes come from (plan xp-c): MetalUI's run-time compiler in the app (`SDLRuntimeKernels`, task 11, gap XP-G25),
/// and, before it and in the tests, the generated kernels compiled offline (`SDLPrecompiledKernels`).
protocol SDLKernelProvider: Sendable {
    /// Whether this provider can give anything here; `nil` when it can, else why not (`.absent` or `.broken` of the backend).
    var unavailability: ComputeBackendState? { get }
    func pipeline(for source: KernelSource, device: SDLGPUDevice) async throws -> SDLGPUComputePipeline
}

/// The generated kernels compiled offline by `scripts/linux-test.sh kernels` (task 3): `<digest>.comp.{spv,dxil,msl,json}` in one directory.
struct SDLPrecompiledKernels: SDLKernelProvider {
    let directory: URL

    var unavailability: ComputeBackendState? {
        FileManager.default.fileExists(atPath: directory.path) ? nil : .absent("the generated kernels were not compiled (\(directory.path))")
    }

    func pipeline(for source: KernelSource, device: SDLGPUDevice) async throws -> SDLGPUComputePipeline {
        let blob: SDLGPUShaderBlob
        do {
            blob = try SDLGPUShaderLibrary(directory: directory).compute("\(source.digest)", for: device)
        } catch {
            throw ImplicitCompileError.unsupported("\(source.kernel.rawValue) \(source.digest) was not compiled offline "
                + "(run XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh kernels): \(error)")
        }
        guard blob.readOnlyStorageBuffers == source.kernel.bindings.readOnly, blob.readWriteStorageBuffers == source.kernel.bindings.readWrite else {
            throw ImplicitCompileError.engine("\(source.digest)'s reflection does not match \(source.kernel.rawValue)'s bindings")
        }
        do {
            return try device.compileComputePipeline(blob)
        } catch {
            throw ImplicitCompileError.engine("\(source.kernel.rawValue): \(error)")
        }
    }
}
#endif
```
`SDLGPUShaderLibrary.compute(_:for:)` loads `NAME.comp.<format>` with `NAME.comp.json`; the file stem is `<digest>.comp`, so the name is the digest.

`Sources/CreatorImplicit/SDL/SDLComputeRecording.swift`:
```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU
import Synchronization

/// Whether a batch's recording on the worker thread failed (a compute pass refused).
final class SDLRecordingFailure: Sendable {
    let failed = Mutex(false)
}

/// One `ComputeBatch` made ready for the device's worker thread: uploads already in transfer buffers, each dispatch's buffers, uniform bytes and
/// group count worked out, the download transfer buffers made. Built and read synchronously; only `record` runs on the worker, in `submitBatch`.
struct SDLComputeRecording: Sendable {
    struct Upload: Sendable {
        let transfer: SDLGPUTransferBuffer
        let buffer: SDLGPUBuffer
        let offset: Int
        let size: Int
    }

    struct Dispatch: Sendable {
        let pipeline: SDLGPUComputePipeline
        let readOnly: [SDLGPUBuffer]
        let readWrite: [SDLGPUBuffer]
        let uniform: [UInt8]
        let groups: Int
    }

    struct Download: Sendable {
        let buffer: SDLGPUBuffer
        let length: Int
        let transfer: SDLGPUTransferBuffer
    }

    let uploads: [Upload]
    let dispatches: [Dispatch]
    let downloads: [Download]
    let failure = SDLRecordingFailure()

    init(_ batch: ComputeBatch, device: SDLGPUDevice) throws {
        guard batch.isWellFormed else { throw ImplicitCompileError.engine("a dispatch with buffers its kernel does not declare, or too many groups") }
        func sdl(_ buffer: any ComputeBuffer) throws -> SDLGPUBuffer {
            guard let buffer = buffer as? SDLComputeBuffer else { throw ImplicitCompileError.engine("a buffer of another backend") }
            return buffer.buffer
        }
        var uploads: [Upload] = []
        for upload in batch.uploads where !upload.bytes.isEmpty {
            guard let transfer = device.makeTransferBuffer(size: upload.bytes.count, direction: .upload), let memory = transfer.map() else {
                throw ImplicitCompileError.engine("SDL_GPU refused a transfer buffer of \(upload.bytes.count) bytes")
            }
            upload.bytes.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { memory.copyMemory(from: base, byteCount: bytes.count) }
            }
            transfer.unmap()
            uploads.append(Upload(transfer: transfer, buffer: try sdl(upload.buffer), offset: upload.offset, size: upload.bytes.count))
        }
        var dispatches: [Dispatch] = []
        for dispatch in batch.dispatches where dispatch.threads > 0 {
            guard let pipeline = dispatch.pipeline as? SDLComputePipeline else { throw ImplicitCompileError.engine("a pipeline of another backend") }
            dispatches.append(Dispatch(pipeline: pipeline.pipeline, readOnly: try dispatch.readOnly.map(sdl), readWrite: try dispatch.readWrite.map(sdl),
                                       uniform: dispatch.parameters.bytes,
                                       groups: (dispatch.threads + ImplicitKernel.threadsPerGroup - 1) / ImplicitKernel.threadsPerGroup))
        }
        var downloads: [Download] = []
        for download in batch.downloads {
            guard download.length > 0, let transfer = device.makeTransferBuffer(size: download.length, direction: .download) else {
                throw ImplicitCompileError.engine("SDL_GPU refused a transfer buffer of \(download.length) bytes")
            }
            downloads.append(Download(buffer: try sdl(download.buffer), length: download.length, transfer: transfer))
        }
        self.uploads = uploads
        self.dispatches = dispatches
        self.downloads = downloads
    }

    /// On the worker thread: the uploads, each dispatch in a compute pass of its own, the downloads.
    func record(into commandBuffer: SDLGPUCommandBuffer) {
        for upload in uploads {
            commandBuffer.copy(upload.transfer, to: upload.buffer, destinationOffset: upload.offset, size: upload.size)
        }
        for dispatch in dispatches {
            guard let pass = commandBuffer.beginComputePass(readWrite: dispatch.readWrite) else {
                failure.failed.withLock { $0 = true }
                continue
            }
            pass.bind(dispatch.pipeline)
            if !dispatch.readOnly.isEmpty { pass.bind(readOnly: dispatch.readOnly) }
            pass.push(uniform: dispatch.uniform, at: 0)
            pass.dispatch(x: dispatch.groups, y: 1, z: 1)
            pass.end()
        }
        for download in downloads {
            commandBuffer.copy(download.buffer, range: 0..<download.length, to: download.transfer)
        }
    }

    /// After the fence: each download's bytes.
    func read() -> [[UInt8]] {
        downloads.map { download in
            guard let memory = download.transfer.map() else { return [] }
            defer { download.transfer.unmap() }
            return Array(UnsafeRawBufferPointer(start: memory, count: download.length))
        }
    }

    var hasFailed: Bool { failure.failed.withLock { $0 } }
}
#endif
```

`Sources/CreatorImplicit/SDL/SDLComputeBackend.swift`:
```swift
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// The HLSL engine over MetalUI's SDL_GPU compute (MetalUI S5; plan xp-c): an owned, headless device (MetalUI: `make` is nonisolated, safe off the
/// main thread once `SDLPlatform` has initialised video, which the app does first), pipelines from a `SDLKernelProvider`, one `submitBatch` per batch,
/// its fence awaited so no thread blocks. No raw `SDL_` call.
final class SDLComputeBackend: ImplicitComputeBackend {
    static var platformName: String {
        #if os(Windows)
        "Direct3D 12"
        #else
        "Vulkan"
        #endif
    }

    let device: SDLGPUDevice
    let kernels: any SDLKernelProvider
    let name = SDLComputeBackend.platformName
    /// The driver's name until XP-G23 is adopted (task 13).
    var deviceName: String { name }
    /// Vulkan's guaranteed `maxStorageBufferRange` until XP-G24 is adopted (task 13).
    let largestBuffer = 1 << 27

    private init(device: SDLGPUDevice, kernels: any SDLKernelProvider) {
        self.device = device
        self.kernels = kernels
    }

    /// `.absent` without a device; the provider's own reason when it cannot give kernels here.
    static func make(kernels: any SDLKernelProvider) -> ComputeBackendState {
        if let unavailable = kernels.unavailability { return unavailable }
        guard let device = SDLGPUDevice.make() else { return .absent("no SDL_GPU device: \(SDLGPUDevice.lastFailure)") }
        return .ready(SDLComputeBackend(device: device, kernels: kernels))
    }

    func makeBuffer(length: Int) throws -> any ComputeBuffer {
        guard length <= largestBuffer,
              let buffer = device.makeBuffer(size: max(length, 16), usage: [.computeStorageRead, .computeStorageWrite]) else {
            throw ImplicitCompileError.unsupported("a GPU buffer of \(length) bytes")
        }
        return SDLComputeBuffer(buffer)
    }

    func makePipeline(_ source: KernelSource) async throws -> any ComputePipeline {
        SDLComputePipeline(try await kernels.pipeline(for: source, device: device))
    }

    func run(_ batch: ComputeBatch) async throws -> [[UInt8]] {
        let recording = try SDLComputeRecording(batch, device: device)
        let fence = try await device.submitBatch { commandBuffer in recording.record(into: commandBuffer) }
        await fence.wait()
        if recording.hasFailed { throw ImplicitCompileError.engine("SDL_GPU refused a compute pass") }
        return recording.read()
    }
}
#endif
```

- [ ] **Step 4: The selection reads availability.** In `ImplicitEvaluators.make`, after its `guard choice == .automatic, let engine else { … }`:
```swift
        switch await engine.availability {
        case .available:
            break
        case .absent(let why):
            // No GPU for this engine: like a machine with no GPU engine, the CPU is all there is (plan xp-c, X-C4).
            return Selection(evaluator: cpu, warning: nil, diagnostic: "no GPU engine: \(why)")
        case .broken(let why):
            // A GPU engine that should run and cannot (its compiler library is missing, a pipeline was refused): the person is told.
            return Selection(evaluator: cpu, warning: cpuWarning, diagnostic: "the GPU engine cannot run: \(why)")
        }
```
A compile error (DXC's diagnostic in `ImplicitCompileError.engine`) already takes the existing `catch` (warning plus "the GPU compiler failed: …"), as on Metal. `ImplicitGPUEngines.platformDefault` is **not** changed here (it stays `nil` off macOS until task 11). In `Support/GPUEnginesUnderTest.swift` drop the `&& false`.

- [ ] **Step 5: Run.** Mac: `swift test --filter CreatorImplicitTests 2>&1 | grep -E "Test run with|recorded an issue"`. Linux: `XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter CreatorImplicitTests 2>&1 | tail -3` — PASS, with `GPUAgreementTests` running "Vulkan" over lavapipe on the offline kernels; then `scripts/linux-test.sh all` (12 lines). Note the Linux `CreatorImplicitTests` time.

- [ ] **Step 6: Lint, commit, push, read the Windows job** (`feat(implicit): the SDL_GPU compute backend runs the generated kernels; engines report availability (xp-c task 5)`; `git push origin xp-c`; the Windows debug build, tests, and "Build release (for the zip)" must pass).

---

### Task 6: Meshing on the HLSL engine, mirroring `MetalImplicitEngine+Meshing`

**Files:**
- Modify: `Sources/CreatorImplicit/Compute/HLSLImplicitEngine+Meshing.swift`
- Create: `Sources/CreatorImplicit/Compute/HLSLMeshRun.swift`
- Test: `Tests/CreatorImplicitTests/HLSLMeshingTests.swift`

**Interfaces:**
- Consumes: `HLSLImplicitEngine` (task 4); `CompiledImplicit.kernels`; `BrickLattice`, `BrickMeshRequest`, `BrickMesh`, `MarchingCubesBuffers.words`, `ImplicitMeshShaderLibrary.Counter`.
- Produces: `meshBricks(_:_:progress:)`; `struct MeshTuning { batchBricks = 1024, slotsPerBrick = 256, largestTable = 1 << 25, slotsPerDispatch = 1 << 18, afterBatch }`; `tune(_:)`; `meshCompileCount`.

- [ ] **Step 1: The failing tests.** `Tests/CreatorImplicitTests/HLSLMeshingTests.swift`:
```swift
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Meshing on the HLSL engine (plan xp-c; Errata D13): the basics, as `MetalMeshingTests` for Metal. Agreement with the CPU is `GPUMeshAgreementTests`.
@Suite(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs the HLSL engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct HLSLMeshingTests {
    static func request(_ solid: ImplicitSolid, resolution: Double, snap: Bool = true) async throws -> BrickMeshRequest {
        BrickMeshRequest(plan: try await BrickPlan.build(for: solid, resolution: resolution, using: CPUBatchEvaluator(solid)), snap: snap)
    }

    @Test func aSphereMeshedOnTheGPUIsAClosedManifoldWithTheRightVolume() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let solid = ImplicitSolid.sphere(radius: 10)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == engine.name)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator).meshReportingPath(solid, resolution: 0.53, quality: .export)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 1000
        #expect(abs(mesh.signedVolume - exact) / exact < 0.005)
        #expect(mesh.normals.count == mesh.positions.count && mesh.normals.allSatisfy { abs(($0 * $0).sum() - 1) < 1e-4 })
    }

    @Test func withoutTheSnapTheNormalsAreZeroAndTheVerticesAreOnTheLattice() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let program = try await engine.compile(ImplicitFixtures.sphere)
        let request = try await Self.request(ImplicitFixtures.sphere, resolution: 0.53, snap: false)
        let mesh = try await engine.meshBricks(program, request) { _ in }
        #expect(mesh.isConsistent && !mesh.triangles.isEmpty && mesh.normals.allSatisfy { $0 == .zero })
        let step = Float(request.resolution)
        for position in mesh.positions {
            let onLattice = (0..<3).filter { axis in
                let units = (position[axis] - Float(request.origin[axis])) / step
                return abs(units - units.rounded()) < 1e-3
            }
            #expect(onLattice.count >= 2, "\(position) is on a lattice edge")
        }
    }

    /// Review Focus 3: a shape's meshing pipelines are made once; a second shape makes only its three that call `sdf` (the four others are shared).
    @Test func meshingASecondTimeCompilesNoMeshPipeline() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        let sphere = try await engine.compile(.sphere(radius: 3))
        let request = try await Self.request(.sphere(radius: 3), resolution: 0.5)
        _ = try await engine.meshBricks(sphere, request) { _ in }
        #expect(await engine.meshCompileCount == 6)
        _ = try await engine.meshBricks(try await engine.compile(.sphere(radius: 4)), request) { _ in }
        #expect(await engine.meshCompileCount == 6, "the same shape")
        let box = try await engine.compile(.box(halfSize: Vector3(2, 2, 2), cornerRadius: 0))
        _ = try await engine.meshBricks(box, try await Self.request(.box(halfSize: Vector3(2, 2, 2), cornerRadius: 0), resolution: 0.5)) { _ in }
        #expect(await engine.meshCompileCount == 8, "sample and place for the box; clear, classify, number and emit shared")
    }
}
```
(Six, not seven: the evaluation pipeline is `compileCount`'s; meshing makes `clear`, `sample`, `classify`, `number`, `place`, `emit`.)

- [ ] **Step 2: Run to see it fail** (`swift test --filter CreatorImplicitTests.HLSLMeshingTests`: `meshBricks` is the protocol's default, "unsupported").

- [ ] **Step 3: The meshing, step for step Metal's.** `Sources/CreatorImplicit/Compute/HLSLMeshRun.swift`:
```swift
/// The six meshing pipelines of one shape.
struct HLSLMeshPipelines: Sendable {
    var clear: any ComputePipeline
    var sample: any ComputePipeline
    var classify: any ComputePipeline
    var number: any ComputePipeline
    var place: any ComputePipeline
    var emit: any ComputePipeline
}

/// What one mesh needs that does not change from attempt to attempt (Metal's `MeshJob`).
struct HLSLMeshJob: Sendable {
    var pipelines: HLSLMeshPipelines
    var solid: HLSLImplicitEngine.Prepared
    var bricks: any ComputeBuffer
    var axes: any ComputeBuffer
    var cube: any ComputeBuffer
    var parameters: KernelParameters
    var brickCount: Int
    var started: Int
    var tuning: HLSLImplicitEngine.MeshTuning
}

/// One attempt at one table size (Metal's `MeshRun` and `MeshBuffers`), and the synchronous builders of its batches.
struct HLSLMeshRun: Sendable {
    var job: HLSLMeshJob
    var samples: any ComputeBuffer
    var keys: any ComputeBuffer
    var slotVertex: any ComputeBuffer
    var counters: any ComputeBuffer
    var positions: any ComputeBuffer
    var normals: any ComputeBuffer
    var indices: any ComputeBuffer
    let slots: Int

    init(_ job: HLSLMeshJob, slots: Int, on backend: any ImplicitComputeBackend) throws {
        self.job = job
        self.slots = slots
        samples = try backend.makeBuffer(length: job.tuning.batchBricks * 729 * 4)
        keys = try backend.makeBuffer(length: slots * 4)
        slotVertex = try backend.makeBuffer(length: slots * 4)
        counters = try backend.makeBuffer(length: ImplicitMeshShaderLibrary.Counter.count * 4)
        positions = try backend.makeBuffer(length: 16)
        normals = try backend.makeBuffer(length: 16)
        indices = try backend.makeBuffer(length: 16)
        self.job.parameters.mask = UInt32(slots - 1)
    }

    /// The counters zeroed and the table emptied (Metal: a blit of 0xFF), in ranges of at most 2^20 slots.
    func clearing() -> ComputeBatch {
        var batch = ComputeBatch(uploads: [ComputeUpload(bytes: [UInt8](repeating: 0, count: ImplicitMeshShaderLibrary.Counter.count * 4),
                                                         buffer: counters)])
        for range in ComputeBytes.ranges(count: slots, size: 1 << 20) {
            var parameters = job.parameters
            (parameters.firstSlot, parameters.count) = (UInt32(range.lowerBound), UInt32(range.count))
            batch.dispatches.append(ComputeDispatch(kernel: .clear, pipeline: job.pipelines.clear, parameters: parameters, readOnly: [],
                                                    readWrite: [keys], threads: range.count))
        }
        return batch
    }

    /// Steps 1 and 2, or 1 and 5, for one batch of bricks, each in its own pass.
    func brickBatch(_ range: Range<Int>, emitting: Bool) -> ComputeBatch {
        var parameters = job.parameters
        (parameters.firstBrick, parameters.brickCount) = (UInt32(range.lowerBound), UInt32(range.count))
        let sample = ComputeDispatch(kernel: .sample, pipeline: job.pipelines.sample, parameters: parameters,
                                     readOnly: [job.solid.floats, job.solid.ints, job.bricks, job.axes], readWrite: [samples],
                                     threads: range.count * 729)
        let second = emitting
            ? ComputeDispatch(kernel: .emit, pipeline: job.pipelines.emit, parameters: parameters,
                              readOnly: [job.bricks, samples, job.cube, keys, slotVertex], readWrite: [counters, indices], threads: range.count * 512)
            : ComputeDispatch(kernel: .classify, pipeline: job.pipelines.classify, parameters: parameters,
                              readOnly: [job.bricks, samples, job.cube], readWrite: [keys, counters], threads: range.count * 512)
        return ComputeBatch(dispatches: [sample, second])
    }

    /// Step 3 or 4 over one range of table slots.
    func slotBatch(_ range: Range<Int>, placing: Bool) -> ComputeBatch {
        var parameters = job.parameters
        (parameters.firstSlot, parameters.count) = (UInt32(range.lowerBound), UInt32(range.count))
        let dispatch = placing
            ? ComputeDispatch(kernel: .place, pipeline: job.pipelines.place, parameters: parameters,
                              readOnly: [job.solid.floats, job.solid.ints, job.axes, keys, slotVertex], readWrite: [positions, normals],
                              threads: range.count)
            : ComputeDispatch(kernel: .number, pipeline: job.pipelines.number, parameters: parameters, readOnly: [keys],
                              readWrite: [slotVertex, counters], threads: range.count)
        return ComputeBatch(dispatches: [dispatch])
    }

    func readingCounters() -> ComputeBatch {
        ComputeBatch(downloads: [ComputeDownload(buffer: counters, length: ImplicitMeshShaderLibrary.Counter.count * 4)])
    }

    func readingMesh(vertices: Int, triangles: Int) -> ComputeBatch {
        ComputeBatch(downloads: [
            ComputeDownload(buffer: counters, length: ImplicitMeshShaderLibrary.Counter.count * 4),
            ComputeDownload(buffer: positions, length: vertices * 16), ComputeDownload(buffer: normals, length: vertices * 16),
            ComputeDownload(buffer: indices, length: triangles * 12),
        ])
    }

    /// The mesh from `readingMesh`'s bytes; throws when the GPU emitted another count than it counted (Metal's check).
    static func mesh(from read: [[UInt8]], triangles: Int) throws -> BrickMesh {
        let counters = ComputeBytes.values(read[0], as: UInt32.self)
        guard counters[ImplicitMeshShaderLibrary.Counter.triangleCursor] == UInt32(triangles) else {
            throw ImplicitCompileError.engine("the GPU emitted a different number of triangles than it counted")
        }
        func points(_ bytes: [UInt8]) -> [SIMD3<Float>] {
            ComputeBytes.values(bytes, as: SIMD4<Float>.self).map { SIMD3($0.x, $0.y, $0.z) }
        }
        return BrickMesh(positions: points(read[1]), normals: points(read[2]), triangles: ComputeBytes.values(read[3], as: UInt32.self))
    }
}
```

Replace `Sources/CreatorImplicit/Compute/HLSLImplicitEngine+Meshing.swift` with:
```swift
/// Marching cubes on the HLSL engine (implicit spec §4.3, Errata D13; plan xp-c): `MetalImplicitEngine+Meshing`, step for step, over the HLSL
/// kernels; the batches are built synchronously (`HLSLMeshRun`) and only run here (the Windows Swift 6.4 rules).
extension HLSLImplicitEngine {
    /// Metal's `MeshTuning`, with batch sizes for an SDL dispatch (65,535 groups of 64) and Windows' 2-second GPU watchdog.
    struct MeshTuning: Sendable {
        var batchBricks = 1024
        var slotsPerBrick = 256
        /// 2^25 slots of 4 bytes is the 128 MiB buffer cap (gap XP-G24); Metal's is 2^27.
        var largestTable = 1 << 25
        var slotsPerDispatch = 1 << 18
        var afterBatch: (@Sendable (Int) async -> Void)?
    }

    func tune(_ tuning: MeshTuning) {
        meshTuning = tuning
    }

    @_optimize(none) // Windows Swift 6.4 release: keeps the closure-specialised coroutine clones (compiler crash) from being made.
    public func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                           progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
        try Task.checkCancellation()
        guard !request.bricks.isEmpty else { return BrickMesh(positions: [], normals: [], triangles: []) }
        guard let lattice = BrickLattice(request.bricks), lattice.fitsEdgeKeys else {
            throw ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")
        }
        let backend = try backend()
        let job = try await startJob(program, request, lattice, on: backend)
        let largest = min(job.tuning.largestTable, backend.largestBuffer / 4)
        var slots = 1 << max(12, Int.bitWidth - (request.bricks.count * job.tuning.slotsPerBrick - 1).leadingZeroBitCount)
        while true {
            guard slots <= largest else { throw ImplicitCompileError.unsupported("the edge table would pass \(largest) slots") }
            if let mesh = try await attempt(job, slots: slots, on: backend, progress: progress) {
                meshesMade += 1
                return mesh
            }
            slots *= 2
        }
    }

    /// The six meshing pipelines of `program`'s shape, made once each (a pipeline whose text another shape shares is not made again).
    private func meshPipelines(for program: CompiledImplicit, on backend: any ImplicitComputeBackend) async throws -> HLSLMeshPipelines {
        func pipeline(_ kernel: ImplicitKernel) async throws -> any ComputePipeline {
            guard let source = program.kernels[kernel] else { throw ImplicitCompileError.unsupported("a solid compiled for Metal, not HLSL") }
            if let known = meshPipelineCache[source.digest] { return known }
            let made = try await backend.makePipeline(source)
            if let raced = meshPipelineCache[source.digest] { return raced }
            meshCompileCount += 1
            meshPipelineCache[source.digest] = made
            return made
        }
        return HLSLMeshPipelines(clear: try await pipeline(.clear), sample: try await pipeline(.sample), classify: try await pipeline(.classify),
                                 number: try await pipeline(.number), place: try await pipeline(.place), emit: try await pipeline(.emit))
    }

    private func startJob(_ program: CompiledImplicit, _ request: BrickMeshRequest, _ lattice: BrickLattice,
                          on backend: any ImplicitComputeBackend) async throws -> HLSLMeshJob {
        let started = epoch
        let pipelines = try await meshPipelines(for: program, on: backend)
        let solid = try await buffers(for: program, on: backend)
        let brickWords = lattice.relativeBricks(request.bricks)
        let axisValues = lattice.axisCoordinates(origin: request.origin, resolution: request.resolution)
        let bricks = try backend.makeBuffer(length: brickWords.count * 4)
        let axes = try backend.makeBuffer(length: axisValues.count * 4)
        let cube = try backend.makeBuffer(length: MarchingCubesBuffers.words.count * 4)
        _ = try await backend.run(ComputeBatch(uploads: [
            ComputeUpload(bytes: ComputeBytes.bytes(of: brickWords), buffer: bricks),
            ComputeUpload(bytes: ComputeBytes.bytes(of: axisValues), buffer: axes),
            ComputeUpload(bytes: ComputeBytes.bytes(of: MarchingCubesBuffers.words), buffer: cube),
        ]))
        var parameters = solid.parameters
        let size = lattice.points
        (parameters.nx, parameters.ny, parameters.nz) = (UInt32(size.x), UInt32(size.y), UInt32(size.z))
        parameters.snap = request.snap ? 1 : 0
        parameters.resolution = Float(request.resolution)
        return HLSLMeshJob(pipelines: pipelines, solid: solid, bricks: bricks, axes: axes, cube: cube, parameters: parameters,
                           brickCount: request.bricks.count, started: started, tuning: meshTuning)
    }

    /// One run of the steps with a table of `slots`; `nil` when the table proved too small (Metal's `meshAttempt`).
    @_optimize(none) // Windows Swift 6.4 release: takes the progress closure; see `meshBricks`.
    private func attempt(_ job: HLSLMeshJob, slots: Int, on backend: any ImplicitComputeBackend,
                         progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        var run = try HLSLMeshRun(job, slots: slots, on: backend)
        _ = try await backend.run(run.clearing())
        try await sweep(run, emitting: false, from: 0, to: 0.4, on: backend, progress: progress)
        var counts = ComputeBytes.values(try await backend.run(run.readingCounters())[0], as: UInt32.self)
        if counts[ImplicitMeshShaderLibrary.Counter.overflow] != 0 { return nil }
        let triangles = Int(counts[ImplicitMeshShaderLibrary.Counter.triangleTotal])
        try await sweepSlots(run, placing: false, on: backend)
        counts = ComputeBytes.values(try await backend.run(run.readingCounters())[0], as: UInt32.self)
        let vertices = Int(counts[ImplicitMeshShaderLibrary.Counter.vertices])
        guard vertices > 0, triangles > 0 else { return BrickMesh(positions: [], normals: [], triangles: []) }
        run.positions = try backend.makeBuffer(length: vertices * 16)
        run.normals = try backend.makeBuffer(length: vertices * 16)
        run.indices = try backend.makeBuffer(length: triangles * 12)
        try await sweepSlots(run, placing: true, on: backend)
        progress(0.55)
        try await sweep(run, emitting: true, from: 0.55, to: 0.95, on: backend, progress: progress)
        return try HLSLMeshRun.mesh(from: try await backend.run(run.readingMesh(vertices: vertices, triangles: triangles)), triangles: triangles)
    }

    @_optimize(none) // Windows Swift 6.4 release: takes the progress closure; see `meshBricks`.
    private func sweep(_ run: HLSLMeshRun, emitting: Bool, from: Double, to: Double, on backend: any ImplicitComputeBackend,
                       progress: @Sendable (Double) -> Void) async throws {
        let batches = ComputeBytes.ranges(count: run.job.brickCount, size: run.job.tuning.batchBricks)
        for index in batches.indices {
            _ = try await backend.run(run.brickBatch(batches[index], emitting: emitting))
            await run.job.tuning.afterBatch?(index + 1)
            try checkRunning(run.job)
            progress(from + (to - from) * Double(batches[index].upperBound) / Double(run.job.brickCount))
        }
    }

    private func sweepSlots(_ run: HLSLMeshRun, placing: Bool, on backend: any ImplicitComputeBackend) async throws {
        let ranges = ComputeBytes.ranges(count: run.slots, size: run.job.tuning.slotsPerDispatch)
        for index in ranges.indices {
            _ = try await backend.run(run.slotBatch(ranges[index], placing: placing))
            try checkRunning(run.job)
        }
    }

    private func checkRunning(_ job: HLSLMeshJob) throws {
        try Task.checkCancellation()
        if epoch != job.started { throw CancellationError() }
    }
}
```
`meshPipelines` takes a nested `async` function; if the Windows compiler objects, make `pipeline(_:)` a private method of the extension taking `program` and `backend`.

- [ ] **Step 4: Run** (Mac after `scripts/linux-test.sh kernels`; Linux): `swift test --filter CreatorImplicitTests.HLSLMeshingTests`, `XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter HLSLMeshingTests` — PASS. A mesh that is not closed: a dispatch read another's output inside one pass, or a binding order (task 3's reflection check names it).

- [ ] **Step 5: Asserts toolchain, lint, commit, push, read Windows CI** (`feat(implicit): marching cubes on the HLSL engine, as on Metal (xp-c task 6)`).

---

### Task 7: The mesh agreement, the streamed export's bytes and the limits, over every engine

**Files:**
- Modify (tests): `GPUMeshAgreementTests.swift`, `StreamingMesherGPUTests.swift` (both stop being Metal-only), `HLSLMeshingTests.swift` (the limits)

**Interfaces:**
- Consumes: `GPUEnginesUnderTest` (task 4), `HLSLImplicitEngine.meshBricks`, `MeshTuning`, `tune(_:)` (task 6); `SamplesOnlyEvaluator`, `MeshComparison`, `GPUFixtures.meshAllowanceFactor`, `.singularSetAllowanceFactor`, `.nearSingularSet`, `ProgressLog` (in `ImplicitMesherTests.swift`), `CollectingSink`, `STLFileWriter`.
- Produces: the measured Face-mapped Voronoi figure and the lavapipe suite time that D21 quotes (task 10).

- [ ] **Step 1: The mesh agreement over every engine.** In `GPUMeshAgreementTests.swift`: drop the outer `#if canImport(Metal)`/`#endif`; the suite attribute becomes `@Suite(.enabled(if: !GPUEnginesUnderTest.names.isEmpty, "needs a GPU engine: \(GPUEnginesUnderTest.unavailableReason)"))`; each of its three tests takes `GPUEnginesUnderTest.names` as its first argument list (`@Test(arguments: GPUEnginesUnderTest.names, names)`, `(…, GPUFixtures.singularSetNames)`, `(…, ["sphere", "box", "smooth union", "graded offset"])`), a first parameter `_ engineName: String`, and `let engine = try GPUEnginesUnderTest.engine(engineName)` in place of `let engine = try #require(MetalImplicitEngine.shared)`; every message gains the prefix `"\(engineName), "`. The tolerances and allowance factors are unchanged (X-C6).

- [ ] **Step 2: The streamed export over every engine, and its bytes twice (X-C3).** In `StreamingMesherGPUTests.swift`: drop the `#if`, take the same suite attribute, give both tests `(arguments: GPUEnginesUnderTest.names)` and `_ engineName: String`, and select with `ImplicitEvaluators.make(for: solid, choice: .automatic, engine: try GPUEnginesUnderTest.engine(engineName))`. Add:
```swift
    /// Review Focus 6, X-C3: an export streams through the CPU mesher over the engine's values, in the plan's order, so the same solid exported twice
    /// on one machine is the same bytes, on every engine (Metal's today, and the HLSL engine's). Across machines or backends the values may differ in a
    /// last bit and the bytes with them; D15's tolerances are what holds there.
    @Test(arguments: GPUEnginesUnderTest.names)
    func exportingTheSameSolidTwiceGivesTheSameBytes(_ engineName: String) async throws {
        let solid = LatticeFixtures.tpmsAll[0].solid
        let engine = try GPUEnginesUnderTest.engine(engineName)
        func export() async throws -> Data {
            let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
            let url = FileManager.default.temporaryDirectory.appending(path: "xp-c-\(UUID().uuidString).stl")
            defer { try? FileManager.default.removeItem(at: url) }
            var sink = try STLFileWriter(destination: url)
            _ = try await StreamingMesher(evaluator: selection.evaluator, windowBricks: 40, bricksPerBatch: 50)
                .stream(solid, resolution: 0.5, into: &sink)
            try sink.finish()
            return try Data(contentsOf: url)
        }
        let first = try await export()
        #expect(!first.isEmpty && first == (try await export()), "\(engineName): two exports differ")
    }
```
(`STLFileWriter(destination:)` and `finish()` are its API; `stream(_:resolution:into:)` takes the sink `inout`.)

- [ ] **Step 3: The limits on the HLSL engine.** Add to `HLSLMeshingTests` (as `MetalMeshingLimitsTests` for Metal; the comparisons are of sets, the order being the threads' on both engines):
```swift
    struct Job {
        let engine: HLSLImplicitEngine
        let program: CompiledImplicit
        let request: BrickMeshRequest

        init(_ solid: ImplicitSolid = .sphere(radius: 10), resolution: Double = 0.53,
             tuning: HLSLImplicitEngine.MeshTuning = HLSLImplicitEngine.MeshTuning()) async throws {
            guard let engine = GPUEnginesUnderTest.makeHLSL() else { throw ImplicitCompileError.engine("no HLSL engine") }
            await engine.tune(tuning)
            self.engine = engine
            program = try await engine.compile(solid)
            request = try await HLSLMeshingTests.request(solid, resolution: resolution)
        }

        func mesh() async throws -> BrickMesh { try await engine.meshBricks(program, request) { _ in } }
    }

    static func sameSet(_ a: BrickMesh, _ b: BrickMesh) -> Bool {
        let comparison = MeshComparison(reference: a.triangleMesh, candidate: b.triangleMesh)
        return comparison.unmatched == 0 && comparison.farthest < 1e-6 && a.positions.count == b.positions.count && a.triangles.count == b.triangles.count
    }

    @Test func manySmallBatchesMakeTheMeshOneBigBatchDoes() async throws {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.batchBricks = 7
        let small = try await Job(tuning: tuning)
        #expect(small.request.bricks.count > 50)
        #expect(Self.sameSet(try await small.mesh(), try await Job().mesh()))
    }

    @Test func aTableThatIsTooSmallIsDoubledUntilItFits() async throws {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        let mesh = try await Job(tuning: tuning).mesh()
        #expect(mesh.positions.count > 4096 && Self.sameSet(mesh, try await Job().mesh()))
    }

    @Test func aMeshOfSeveralRangesOfSlotsIsTheMeshOneRangeMakes() async throws {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.slotsPerDispatch = 1_000
        let ranges = try await Job(tuning: tuning).mesh()
        #expect(ranges.positions.count > 1_000 && Self.sameSet(ranges, try await Job().mesh()))
    }

    /// Review Focus 4.
    @Test func aMeshBeyondTheLargestTableIsLeftToTheCPU() async throws {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        tuning.largestTable = 4096
        let job = try await Job(tuning: tuning)
        await #expect(throws: ImplicitCompileError.self) { _ = try await job.mesh() }
        let (mesh, path) = try await ImplicitMesher(evaluator: GPUBatchEvaluator(engine: job.engine, program: job.program))
            .meshReportingPath(.sphere(radius: 10), resolution: 0.53, quality: .preview)
        #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
    }

    /// Review Focus 4: past the 128 MiB buffer cap (2^25 slots), whatever `largestTable` allows.
    @Test func aTablePastTheBufferCapIsUnsupportedBeforeAnyGPUWork() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.largestTable = 1 << 30
        tuning.slotsPerBrick = 1 << 25
        await engine.tune(tuning)
        let program = try await engine.compile(.sphere(radius: 10))
        let request = BrickMeshRequest(origin: .zero, resolution: 0.5, bricks: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)], snap: true)
        await #expect(throws: ImplicitCompileError.unsupported("the edge table would pass \(1 << 25) slots")) {
            _ = try await engine.meshBricks(program, request) { _ in }
        }
    }

    @Test func bricksTooFarApartForThirtyTwoBitKeysAreUnsupported() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let program = try await engine.compile(.sphere(radius: 10))
        let request = BrickMeshRequest(origin: .zero, resolution: 0.5, bricks: [SIMD3(0, 0, 0), SIMD3(1_200, 1_200, 1_200)], snap: true)
        await #expect(throws: ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")) {
            _ = try await engine.meshBricks(program, request) { _ in }
        }
    }

    @Test func aPartFarFromTheOriginIsMeshedInASmallWindow() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let move = RigidMove(origin: Vector3(4_000, -3_000, 2_500), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let far = ImplicitSolid.moved(.sphere(radius: 10), move)
        let selection = await ImplicitEvaluators.make(for: far, choice: .automatic, engine: engine)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator).meshReportingPath(far, resolution: 0.53, quality: .preview)
        #expect(path == .gpu && MeshTopology(mesh).isClosedManifold)
        let bounds = try #require(mesh.bounds)
        #expect(abs(bounds.min.x - 3_990) < 1 && abs(bounds.max.z - 2_510) < 1)
    }

    static func manyBatches() async throws -> Job {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        let job = try await Job(.sphere(radius: 20), resolution: 0.4, tuning: tuning)
        #expect(job.request.bricks.count > 40)
        return job
    }

    static func expectTheNextMeshRuns(_ engine: HLSLImplicitEngine) async throws {
        let small = try await request(.sphere(radius: 3), resolution: 0.5)
        let after = try await engine.meshBricks(try await engine.compile(.sphere(radius: 3)), small) { _ in }
        #expect(MeshTopology(after.triangleMesh).isClosedManifold)
    }

    @Test func cancellingTheTaskEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        let seen = ProgressLog()
        let running = Task {
            try await job.engine.meshBricks(job.program, job.request) { fraction in
                seen.append(fraction)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await running.value }
        #expect(seen.values.count == 1)
        try await Self.expectTheNextMeshRuns(job.engine)
    }

    @Test func anEngineCancelEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        tuning.afterBatch = { [engine = job.engine] batch in
            if batch == 1 { await engine.cancel() }
        }
        await job.engine.tune(tuning)
        let seen = ProgressLog()
        await #expect(throws: CancellationError.self) { _ = try await job.engine.meshBricks(job.program, job.request) { seen.append($0) } }
        #expect(seen.values.isEmpty)
        tuning.afterBatch = nil
        await job.engine.tune(tuning)
        try await Self.expectTheNextMeshRuns(job.engine)
    }
```
The solids above are `GeneratedKernels.solids`' shapes (a sphere, a moved sphere, the TPMS fixture): no new shape needs offline compiling.

- [ ] **Step 4: Run and measure.**
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh kernels
swift test --filter "CreatorImplicitTests.(GPUMeshAgreementTests|StreamingMesherGPUTests|HLSLMeshingTests)" 2>&1 | tee .build/xp-c-mesh-mac.log | tail -5
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter "GPUMeshAgreementTests|StreamingMesherGPUTests|HLSLMeshingTests" 2>&1 | tee .build/xp-c-mesh-linux.log | tail -3
```
Expected: PASS, the HLSL engine held to Metal's tolerances. Record: (1) **D20's open item 3**: with a temporary `print("XPC-MEASURE \(engineName) \(name) \(pipeline.worstScaledSurface)")` in `theGPUMeshAgreesAwayFromTheSingularSet`, the figure for "voronoi struts, face of a cylinder" on Metal, "Metal (HLSL)" and "Vulkan" (remove the print before committing). About 6 on all: Float sensitivity of the face chart's map, not Metal's; within 1 on HLSL: specific to Metal's compiled code. The factor is not changed either way. (2) the three suites' time on lavapipe; over 10 minutes, cut `GPUMeshAgreementTests.resolution(of:)`'s 60 voxels across to 40 for `engineName == "Vulkan"` only, and say so. Never loosen a tolerance.

- [ ] **Step 5: Full suites, lint, commit with the figures, push, read Windows CI** (`swift test` 12 lines; `scripts/linux-test.sh all`; `test(implicit): mesh agreement, export bytes and limits over every GPU engine (xp-c task 7)`, the measured figures in the body).

---

### Task 8: `--self-test` reports the implicit engine (interim, before XP-G25)

**Files:** Create `Sources/CreatorImplicit/GPU/ImplicitEngineCheck.swift`; modify `Sources/CreatorApp/SelfTest.swift`, `docs/packaging.md`; test `Tests/CreatorImplicitTests/ImplicitEngineCheckTests.swift`.

**Interfaces:** Produces `public enum ImplicitEngineCheck { public static func run() async -> String }` — the engine and its availability, for the self-test's detail; task 12 adds MetalUI's `selfTest()` to it.

- [ ] **Step 1: The failing test.**
```swift
import Testing
@testable import CreatorImplicit

/// What `--self-test` says about the implicit engine (plan xp-c): which engine runs, or why it is the CPU.
struct ImplicitEngineCheckTests {
    @Test func theCheckNamesTheEngineOrWhyItIsTheCPU() async {
        let text = await ImplicitEngineCheck.run()
        #if canImport(Metal)
        #expect(text.hasPrefix("Metal") || text.hasPrefix("the CPU"))
        #else
        #expect(text.hasPrefix("the CPU") || text.hasPrefix("Vulkan") || text.hasPrefix("Direct3D 12"), "\(text)")
        #endif
    }
}
```
- [ ] **Step 2: Implement.** `Sources/CreatorImplicit/GPU/ImplicitEngineCheck.swift`:
```swift
/// `MetalCreator --self-test`'s line about the implicit engine (plan xp-c): the platform's engine and its device, or why evaluation is on the CPU. It
/// never fails the self-test by itself: a machine without a GPU engine is a supported machine (D11). Task 12 adds MetalUI's compiler self-test, which
/// does fail a package that ships without the compiler libraries.
public enum ImplicitEngineCheck {
    public static func run() async -> String {
        guard let engine = ImplicitGPUEngines.platformDefault else {
            return "the CPU (no GPU engine on this platform yet: SDL_GPU run-time compilation waits for MetalUI XP-G25)"
        }
        switch await engine.availability {
        case .available: return "\(engine.name) on \(await engine.deviceName)"
        case .absent(let why): return "the CPU (\(why))"
        case .broken(let why): return "the CPU, with a warning (\(why))"
        }
    }
}
```
In `SelfTest.swift` add a check after "shaders": `results.append(await check("implicit engine") { await ImplicitEngineCheck.run() })` (with `import CreatorImplicit`). In `docs/packaging.md`, after the Windows zip's contents, add a paragraph "**The implicit engine's shader compiler (after MetalUI XP-G25).** Linux and Windows packages will ship SDL_shadercross, DXC and their libraries for the implicit engine's run-time compilation (plan xp-c, task 12); until then the packages are unchanged and the engine off macOS is the CPU (`--self-test`'s "implicit engine" line says so)."
- [ ] **Step 3: Run** (`swift test --filter "ImplicitEngineCheckTests|SelfTest"`, `scripts/linux-test.sh smoke`), **lint, commit** (`feat(app): --self-test names the implicit engine (xp-c task 8)`).

---

### Task 9: Benchmarks before XP-G25: x-1, x-2 and x-1h per engine, x-3o the offline compile cost

**Files:** Create `Tests/CreatorImplicitTests/ImplicitBenchHLSL.swift`; modify `Tests/CreatorImplicitTests/Support/GeneratedKernels.swift` (the bench sheet), `docs/verification/performance.md`.

**Interfaces:** Produces `ImplicitBenchHLSL.sheet(wall:)`; the rows task 10 and human check XP-27 cite.

- [ ] **Step 1: The bench suite** (add `("bench sheet", ImplicitBenchHLSL.sheet(wall: 3))` to `GeneratedKernels.solids`):
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// Rows x-1, x-2, x-1h and x-3m (plan xp-c, X-C7): the engines side by side on one solid, the mesher alone; x-3m is Metal's own compile of a new shape,
/// the figure the HLSL engine's run-time compile (x-3, task 11) is compared with. A plain `swift test` skips it; `scripts/bench.sh ImplicitBench` on a Mac,
/// `DOCKER_EXTRA="-e METALCREATOR_BENCH=1" scripts/linux-test.sh test -c release --no-parallel --filter ImplicitBenchHLSL` on Linux.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["METALCREATOR_BENCH"] == "1", "set METALCREATOR_BENCH=1"))
struct ImplicitBenchHLSL {
    static func sheet(wall: Double) -> ImplicitSolid {
        .tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeCells(size: .constant(100)), thickness: .constant(wall),
                          region: BoundingBox(min: Vector3(-50, -50, -50), max: Vector3(50, 50, 50))))
    }

    static let resolution = 100.0 / 128

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func releaseOnly() -> Bool {
        #if DEBUG
        Issue.record("Benchmarks run in a release build: scripts/bench.sh (swift test -c release).")
        return false
        #else
        return true
        #endif
    }

    /// The mesher on `name`'s engine ("CPU" for the CPU evaluator), warm: the median of six runs after one.
    static func time(_ solid: ImplicitSolid, on name: String) async throws -> Double {
        let evaluator: any ImplicitBatchEvaluator = name == "CPU"
            ? CPUBatchEvaluator(solid)
            : await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: try GPUEnginesUnderTest.engine(name)).evaluator
        let clock = ContinuousClock()
        var samples: [Double] = []
        for round in 0..<7 {
            let start = clock.now
            let (_, path) = try await ImplicitMesher(evaluator: evaluator).meshReportingPath(solid, resolution: resolution, quality: .preview)
            if round > 0 { samples.append(milliseconds(clock.now - start)) }
            #expect(name == "CPU" || path == .gpu, "\(name) meshed on the GPU")
        }
        return samples.sorted()[samples.count / 2]
    }

    @Test(arguments: GPUEnginesUnderTest.names + ["CPU"])
    func theFirstPassAndAThicknessEditOnEachEngine(_ name: String) async throws {
        guard Self.releaseOnly() else { return }
        let first = try await Self.time(Self.sheet(wall: 3), on: name)
        let edit = try await Self.time(Self.sheet(wall: 2.5), on: name)
        print("BENCH x-1 \(name): first pass of a 100 mm gyroid sheet at 0.78 mm, warm: median \(first.formatted(.number.precision(.fractionLength(2)))) ms")
        print("BENCH x-2 \(name): thickness edit, warm: median \(edit.formatted(.number.precision(.fractionLength(2)))) ms")
        if name == "Metal (HLSL)" {
            print("BENCH x-1h Metal (HLSL): \(first.formatted(.number.precision(.fractionLength(2)))) ms; budget 1000.00 ms: \(first < 1000 ? "met" : "missed")")
            #expect(first < 1000, "x-1h: the generated HLSL on this Mac's GPU misses i-1's 1 s")
        }
    }

    #if canImport(Metal)
    /// x-3m: Metal compiling one new shape, the evaluation pipeline and then the five meshing kernels (a fresh engine each time).
    @Test func metalsCompileOfANewShape() async throws {
        guard Self.releaseOnly(), MetalImplicitEngine.shared != nil else { return }
        let clock = ContinuousClock()
        var evaluation: [Double] = []
        var meshing: [Double] = []
        for round in 0..<5 {
            let engine = try #require(MetalImplicitEngine())
            let solid = Self.sheet(wall: 3 + Double(round))
            let start = clock.now
            let program = try await engine.compile(solid)
            let compiled = clock.now
            let plan = try await BrickPlan.build(for: solid, resolution: 10, using: CPUBatchEvaluator(solid))
            _ = try await engine.meshBricks(program, BrickMeshRequest(plan: plan, snap: true)) { _ in }
            evaluation.append(Self.milliseconds(compiled - start))
            meshing.append(Self.milliseconds(clock.now - compiled))
        }
        print("BENCH x-3m Metal: a new shape's evaluation pipeline median \(evaluation.sorted()[2].formatted(.number.precision(.fractionLength(2)))) ms, "
            + "its meshing pipelines and a coarse mesh median \(meshing.sorted()[2].formatted(.number.precision(.fractionLength(2)))) ms")
    }
    #endif
}
```
- [ ] **Step 2: Run** (idle Mac; Linux in Docker):
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh kernels 2>&1 | grep COMPILE-TIME     # x-3o: the offline compile, kernels and seconds
scripts/bench.sh ImplicitBenchHLSL
DOCKER_EXTRA="-e METALCREATOR_BENCH=1" XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test -c release --no-parallel --filter ImplicitBenchHLSL 2>&1 | grep BENCH
```
(For x-3o, empty `.build/generated-kernels/compiled` first so every kernel compiles; divide the time by the kernels: the offline cost of one kernel through the shadercross CLI, an upper bound on XP-G25's in-process compile.) x-1h missing its budget is a finding to report, not a test to loosen.
- [ ] **Step 3: Record** in `docs/verification/performance.md` a section "Implicit engines side by side (plan xp-c)" with a table (row, machine and load, engine, median, budget, verdict) for x-1 and x-2 (Metal, Metal (HLSL), CPU on the Mac; Vulkan on lavapipe, CPU in the Linux image), x-1h (budget 1000 ms), x-3m (Metal, recorded), x-3o (shadercross CLI per kernel, recorded), and the `BENCH` lines; x-3 and x-4 are "after XP-G25 (task 11)".
- [ ] **Step 4: Commit** (`bench(implicit): rows x-1, x-2, x-1h, x-3m, x-3o (xp-c task 9)`).

---

### Task 10: The errata, the human checks and the project notes (the state before XP-G25, with the run-time half named)

**Files:** Modify both specs, `docs/verification/human-checks.md`, `docs/metalui-gaps.md`, `CLAUDE.md`.

- [ ] **Step 1: Erratum E8** after E7 in the cross-platform spec:
```markdown
- **E8 (xp-c, XP-G2 and E7's last sentence). Implicit evaluation and meshing on SDL GPU, as on macOS.** The user ruled (2026-10-22) that Linux and Windows
  follow macOS: `ImplicitCompiler`'s walk writes HLSL as well as MSL (`ShaderDialect`; the `sdf` statement for statement, the same buffers; the MSL bytes
  unchanged, pinned by digests), one source per kernel, compiled while the app runs and cached by the source's digest (`HLSLImplicitEngine`, the twin of
  `MetalImplicitEngine`, over MetalUI's SDL_GPU compute on an owned headless device). Run-time compilation needs MetalUI gap XP-G25 (a compiler over
  SDL_shadercross's library and DXC, pipelines from bytes); **until it is adopted, E7's last sentence still holds for the app** (evaluation and meshing
  on the CPU off macOS) while the engine is tested on lavapipe and on the Mac's GPU over kernels the build-time SDL_shadercross compiled offline
  (`scripts/linux-test.sh kernels`). Once adopted (plan xp-c, task 11): no SDL_GPU device, the CPU silently; the compiler library missing (its named
  error lists the paths tried), a pipeline refused, or a source DXC refuses, the CPU with "Running on the CPU" and the reason; the badge says "Vulkan" or
  "Direct3D 12". The packages ship the compiler's shared libraries and their licences (task 12). Exports are byte-identical run to run on one machine, as
  on macOS (they stream through the CPU mesher over the engine's values); bytes across machines or backends are not promised, D15's tolerances are.
  Gaps XP-G23 (adapter name, software rasterizer) and XP-G24 (compute limits) are open; meanwhile the driver's name and 128 MiB buffers.
```
In §5's table, the XP-G2 row's "Needed by" becomes `after xp-3. **Answered by MetalUI S5**; used by xp-c with XP-G25 (erratum E8)`.

- [ ] **Step 2: Erratum D21** after D20 in the implicit spec:
```markdown
- **D21. The HLSL GPU engine (xp-c, plan `2026-10-22-xp-c-sdl-gpu-meshing.md`).** Amends §4.1, §6, D11, D13. (1) **Compilation follows Metal.** One walk of
  the tree (`ImplicitCompiler.Generator`) writes MSL or HLSL (`ShaderDialect`), the same statements over the same five buffers; HLSL is compiled while the
  app runs (MetalUI XP-G25), one source per kernel because an SDL_GPU shader has one entry point; the kernels that do not call `sdf` (`mesh_clear`, which
  SDL_GPU needs for want of a buffer fill, `mesh_classify`, `mesh_number`, `mesh_emit`) are one text for every shape, so the digest-keyed cache makes them
  once. An edited value never recompiles; a new shape compiles its evaluation kernel at `prepare` and its meshing kernels at its first mesh, as on Metal.
  (2) **Agreement.** The same suites and tolerances as Metal, over the Mac's GPU (the HLSL's MSL), lavapipe and WARP: values 1e-4 mm; D15; D17; D20's
  amended allowance unchanged, its Face-mapped Voronoi item measured <task 7's figures and conclusion>. (3) **Precision.** Float only; the HLSL library's
  own sine, cosine and arctangent (Vulkan guarantees 2^-11 for `sin`); the noise hash in 32-bit word pairs. (4) **Order and bytes.** `meshBricks` keeps
  the threads' order on both engines (D13: the set is fixed); exports stream through the CPU mesher in the plan's order (D12), so the same export on one
  machine is the same bytes on every engine; across machines and backends only D15's tolerances hold. (5) **Budgets.** §6's i-1 and i-2 stay Metal's
  (D11). x-1 and x-2 are recorded per engine without a budget in CI; x-1h, the HLSL on this Mac's GPU, is held to 1 s (<task 9's figure>); x-3 (a new
  shape's compile) and x-4 (its first pass, compile included) are recorded after XP-G25, x-4 proposed under 2 s on a desktop GPU (human check XP-27).
  (6) **Limits.** Storage buffers of at most 128 MiB until XP-G24 (an edge table of 2^25 slots, Metal's 2^27); past it the request is the CPU mesher's.
```
Fill each `<…>` from tasks 7 and 9; none may remain.

- [ ] **Step 3: Human checks**, a group after XP3:
```markdown
## Group XPC — implicit evaluation and meshing on SDL GPU, Linux and Windows (xp-c)

**Status: NOT RUN; needs plan xp-c task 11 (MetalUI XP-G25) and task 12.** Specs: cross-platform E8, implicit D21. CI holds the engine to the CPU on
lavapipe and WARP; these checks are a real GPU, a person's eye and a stopwatch.

- [ ] **XP-27 Lattice previews on a desktop GPU (Linux and Windows).** A graph with a TPMS node filling a 100 mm cube and a Mesh node: the badge says
  "Vulkan" (Linux) or "Direct3D 12" (Windows); the very first preview, which compiles the shape's kernels, appears within about 2 s (x-4, proposed); a
  thickness drag re-meshes within about a tenth of a second a pass (i-2) and never pauses to compile; a new shape (switch the TPMS type) pauses once,
  then not again. The surface looks as on a Mac. For numbers, `METALCREATOR_BENCH=1 swift test -c release --no-parallel --filter "ImplicitBenchHLSL|ImplicitBench/(theFirstPreview|aThicknessEdit)"`
  on that machine, into `docs/verification/performance.md`. **Pinned:** `GPUAgreementTests`, `GPUMeshAgreementTests`, `HLSLRuntimeCompileTests`. **Observed:**
- [ ] **XP-28 The same export twice.** Export the Mesh as STL twice, and as 3MF twice: `cmp a.stl b.stl` (Linux), `fc /b a.stl b.stl` (Windows) say
  identical, as on a Mac. **Pinned:** `StreamingMesherGPUTests.exportingTheSameSolidTwiceGivesTheSameBytes`. **Observed:**
- [ ] **XP-29 A package without its compiler.** Unpack the tarball or zip, move the shader compiler's libraries out of its `lib` (or beside the `.exe`)
  and launch it away from any checkout: the app runs, a Mesh node meshes, its badge says "Running on the CPU"; `--self-test` fails naming the missing
  library and the paths tried. Put them back: "Vulkan" (or "Direct3D 12") after a relaunch. **Pinned:** `HLSLRuntimeCompileTests.aMissingCompilerLibraryIsBrokenAndNamesWhatItTried`, task 12's package checks. **Observed:**
```

- [ ] **Step 4: Gaps file and `CLAUDE.md`.** The XP-G2 row's status: "✅ answered (MetalUI S5); used by xp-c with XP-G25". In `CLAUDE.md`, after the xp-3 paragraph, a paragraph stating: `ImplicitCompiler.Generator` has a `ShaderDialect` (MSL byte-identical, `MetalSourceDigests` pins it; edit a generator case once, for both); `ImplicitCompiler.compileHLSL` and `HLSLShaderLibrary`/`HLSLMeshShaderLibrary` (edit the MSL library and its HLSL twin together; `HLSLSourceTests` checks the `sdf` statement for statement, the registers and the forbidden constructs); `HLSLImplicitEngine` over `ImplicitComputeBackend` (`SDLComputeBackend` with an `SDLKernelProvider`; `MSLComputeBackend` in the Mac's tests); the offline kernels (`scripts/linux-test.sh kernels`, `.build/generated-kernels`, `GeneratedKernels.solids`: add a new test shape there); `availability`; until XP-G25 the app's engine off macOS is the CPU; the GPU suites run over `GPUEnginesUnderTest.names`; gaps XP-G23 to XP-G25; human checks XP-27 to XP-29. Replace the 7c-1g paragraph's "The SDL3 engine for Linux and Windows is track xp-c." with "Linux and Windows follow macOS since xp-c (below)." Add `scripts/linux-test.sh kernels` to "Commands". Run `swift test --filter CIPinTests`.

- [ ] **Step 5: Commit** (`docs: errata E8 and D21, human checks XP-27 to XP-29, xp-c in CLAUDE.md (xp-c task 10)`).

---

### Task 11 (waits for MetalUI XP-G25): compile at run time; the app's engine off macOS

Starts when `docs/metalui-gaps.md` (or the coordinator) says XP-G25 is merged in MetalUI, naming the commit. **The names below are MetalUI's planned shape (`feat/sdl-gpu-runtime-shaders`) and provisional**: before writing code, read the answering commit (`git -C ../MetalUI show <commit>:Backends/SDL/Sources/MetalUISDLGPU/…`, its record and `docs/packaging.md` §4a) and use its real names; the plan calls them `SDLGPUShaderCompiler` (nonisolated; `compileCompute(hlsl:entryPoint:defines:for:) throws -> SDLGPUShaderBlob` or bytes plus reflection), `SDLGPUShaderCompilerError` (a missing library listing the paths tried; a compile failure with DXC's text), `SDLGPUDevice.compileComputePipeline(_:)` from the compiler's output, and `SDLGPUShaderCompiler.selfTest()`.

**Files:** Create `Sources/CreatorImplicit/SDL/SDLRuntimeKernels.swift`, `Sources/CreatorImplicit/SDL/SDLImplicitEngine.swift`, `Tests/CreatorImplicitTests/HLSLRuntimeCompileTests.swift`; modify `Sources/CreatorImplicit/GPU/ImplicitGPUEngines.swift`, `Tests/CreatorImplicitTests/Support/GPUEnginesUnderTest.swift`, `ImplicitGPUAvailabilityTests.swift`, `GPUBatchEvaluatorTests.swift`, `ImplicitBenchHLSL.swift`, `.github/workflows/xp.yml` (`METALUI_COMMIT`), the docs.

**Interfaces:** Produces `SDLRuntimeKernels: SDLKernelProvider`; `HLSLImplicitEngine.sdl`; `platformDefault` off macOS; rows x-3 and x-4.

- [ ] **Step 1: Bump the pin** to the answering commit in `xp.yml` (`METALUI_COMMIT`) and check `../MetalUI` is at or past it (read-only: `git -C ../MetalUI merge-base --is-ancestor <commit> HEAD`).

- [ ] **Step 2: The failing tests.** `Tests/CreatorImplicitTests/HLSLRuntimeCompileTests.swift` (wholly `#if canImport(MetalUISDLGPU)`):
```swift
#if canImport(MetalUISDLGPU)
import Foundation
import Testing
@testable import CreatorImplicit

/// Run-time compilation of the generated HLSL (plan xp-c task 11, MetalUI XP-G25): what the app does on Linux and Windows.
struct HLSLRuntimeCompileTests {
    /// Review Focus 2: no compiler library → broken, naming the paths tried, so the person hears "Running on the CPU".
    @Test func aMissingCompilerLibraryIsBrokenAndNamesWhatItTried() {
        let state = SDLComputeBackend.make(kernels: SDLRuntimeKernels(librarySearchPath: [FileManager.default.temporaryDirectory]))
        if case .broken(let why) = state {
            #expect(why.contains(FileManager.default.temporaryDirectory.path), "\(why)")
        } else if case .absent = state {
            // no device here: nothing to say about the compiler
        } else {
            Issue.record("a ready backend without a compiler library")
        }
    }

    /// Review Focus 1: a source DXC refuses is the CPU's, with DXC's text.
    @Test(.enabled(if: SDLRuntimeKernels.isAvailable, "needs MetalUI's run-time compiler"))
    func aSourceTheCompilerRefusesRunsOnTheCPUWithItsDiagnostic() async throws {
        guard case .ready(let backend) = SDLComputeBackend.make(kernels: SDLRuntimeKernels()) else { return }
        let broken = KernelSource(kernel: .evaluate, text: HLSLShaderLibrary.prelude + "void main( {")
        await #expect { _ = try await backend.makePipeline(broken) } throws: { error in
            guard case ImplicitCompileError.engine(let text) = error else { return false }
            return !text.isEmpty
        }
    }

    /// The app's engine compiles each fixture's kernels at run time and agrees with the CPU (the agreement suites then run on it too, step 4).
    @Test(.enabled(if: SDLRuntimeKernels.isAvailable, "needs MetalUI's run-time compiler"))
    func thePlatformEngineCompilesAtRunTime() async throws {
        let engine = try #require(ImplicitGPUEngines.platformDefault)
        #expect(await engine.availability == .available)
        let values = try await GPUBatchEvaluator(engine: engine, program: try await engine.compile(.sphere(radius: 5))).evaluate([SIMD3(8, 0, 0)])
        #expect(abs(values[0] - 3) < 1e-5)
    }
}
#endif
```
- [ ] **Step 3: Implement.** `SDLRuntimeKernels` (`SDLKernelProvider`): `unavailability` is `.broken(<MetalUI's named error>)` when the compiler library cannot be loaded, else `nil`; `pipeline(for:device:)` compiles `source.text` with entry point `main` for the device's backend and makes the pipeline from the result, mapping a compile error to `ImplicitCompileError.engine(<DXC's text>)` and a refused pipeline to `.engine(<SDL's reason>)`; it checks the reflection against `source.kernel.bindings` as `SDLPrecompiledKernels` does. **Threads:** if XP-G25's compile is synchronous it runs on the actor's executor for its duration, a cooperative-pool thread blocked for a compile; run it instead on a serial worker of our own (`SDLCompileWorker`: one `Thread` and a `CheckedContinuation` per job, the pattern of MetalUI's `SDLGPUWorker`), unless MetalUI's answer offers an `async` compile or documents that it serializes itself, and say which in the doc comment. `SDLImplicitEngine.swift`: `extension HLSLImplicitEngine { public static let sdl = HLSLImplicitEngine(name: SDLComputeBackend.platformName, backend: { SDLComputeBackend.make(kernels: SDLRuntimeKernels()) }) }`. `ImplicitGPUEngines.platformDefault` gains `#elseif canImport(MetalUISDLGPU)` → `HLSLImplicitEngine.sdl`, and `meshesMade()` likewise; `GPUBatchEvaluatorTests.thePlatformEngineIsMetalOrNothing` becomes "…is the machine's" accepting "Metal", "Vulkan" and "Direct3D 12"; `GPUEnginesUnderTest.hlslState` uses `SDLRuntimeKernels()` when `SDLRuntimeKernels.isAvailable`, else the offline kernels; `ImplicitGPUAvailabilityTests` drops `&& !os(Windows)` and also expects `await HLSLImplicitEngine.sdl.availability == .available` under `XP_REQUIRE_GPU=1`; `ImplicitEngineCheck` loses its "waits for XP-G25" line.
- [ ] **Step 4: Run** on Linux (`scripts/linux-test.sh all`: the agreement suites now compile at run time on lavapipe) and Windows CI (WARP, run-time compiled; the release build). If CI lacks the compiler libraries, task 12 step 3 adds them to the image and the Windows job; run task 12 first in that case.
- [ ] **Step 5: x-3 and x-4.** Add to `ImplicitBenchHLSL` a test for the SDL engine: a fresh engine, a new shape (the sheet with a new `TPMSType` each round), the time of `compile` (x-3: the evaluation kernel), of the first `meshBricks` minus a warm one (x-3: the six meshing kernels; the four shared ones only on the first shape), and of a first `ImplicitMesher` pass compile included (x-4); `BENCH x-3 …`, `BENCH x-4 …`. Record them on Linux (lavapipe) in `performance.md` beside x-3m and x-3o, and raise in the report if x-4 would miss the proposed 2 s on a desktop GPU.
- [ ] **Step 6: Docs.** E8's "until it is adopted…" sentence becomes "Adopted by plan xp-c task 11 (MetalUI `<commit>`)"; the gap row XP-G25 "✅ fixed by MetalUI `<commit>`, adopted by xp-c task 11"; `CLAUDE.md` likewise. Lint, commit, push.

---

### Task 12 (waits for MetalUI XP-G25): ship the compiler; CI; `selfTest()`

**Files:** `scripts/linux/Dockerfile` (the shadercross stage installs its shared libraries, not only the CLI), `scripts/install-shadercross.ps1`, `.github/workflows/xp.yml` (the caches; the Windows job's PATH), `scripts/package-linux.sh`, `scripts/package-appimage.sh`, `scripts/package-windows.ps1`, `scripts/linux-test.sh` (the clean-Ubuntu checks), `packaging/` NOTICE and licence files, `Sources/CreatorImplicit/GPU/ImplicitEngineCheck.swift`, `Sources/CreatorApp/SelfTest.swift`, `docs/packaging.md`.

- [ ] **Step 1: Ask the user.** The packages will carry third-party shared libraries (SDL_shadercross, zlib licence; DXC and `dxil`, the LLVM/University of Illinois licence; SPIRV-Cross and SPIRV-Tools, Apache 2.0; the exact list is XP-G25's `packaging.md` §4a, including its answer on shipping `dxil.dll`): `AGENTS.md` requires asking before adding third-party code to the app. Stop until the user answers.
- [ ] **Step 2: Build what to ship** per `packaging.md` §4a: the Linux image's `shadercross` stage keeps `lib/libSDL3_shadercross*.so`, `libdxcompiler.so`, `libdxil.so`, `libspirv-cross-c-shared.so` (the names §4a gives) in `/opt/shadercross/lib`; `install-shadercross.ps1` keeps the DLLs; both cached as today.
- [ ] **Step 3: Package them.** The tarball and the AppImage copy them into the package's `lib` (the `$ORIGIN/lib` rpath xp-2 set up), the zip beside `MetalCreator.exe`, with their licences in `share/doc/metalcreator` and lines in `NOTICE.txt`. The clean-Ubuntu checks and the zip's own check run `--self-test`, which now includes MetalUI's `selfTest()` (step 4) and so fails a package without the libraries.
- [ ] **Step 4: `selfTest()`.** `ImplicitEngineCheck` gains `public static func compilerSelfTest() throws -> String?` calling MetalUI's `selfTest()` off macOS (`nil` on a Mac); `SelfTest`'s "implicit engine" check calls it and fails with MetalUI's error when it throws.
- [ ] **Step 5: Run** `scripts/linux-test.sh package` (both packages pass in a clean ubuntu:24.04 and their self-test compiles a kernel) and the Windows job's "Package (zip), checked on its own"; then human check XP-29 on a real machine.
- [ ] **Step 6: Docs, lint, commit, push** (`packaging.md` §"The implicit engine's shader compiler" filled; E8's packaging sentence says adopted).

---

### Task 13 (waits for MetalUI XP-G23, XP-G24): the adapter's name, the limits, and software devices (X-C5, pending)

MetalUI is building both on `feat/sdl-gpu-device-info`; planned (provisional) `SDLGPUDevice.adapterName: String?`, `isSoftwareRasterizer: Bool`, `limits` (likely SDL's guaranteed minimums). Use the answering commit's names.

- [ ] **Step 1: Tests** (in `SDLComputeBackendTests`): the device name is the adapter's when MetalUI gives one; `largestBuffer` is `limits`' storage-buffer binding size (at least 2^27); and, **only if the user chose X-C5 (a)**, `SDLComputeBackend.policy(isSoftware: true, allowingSoftware: false) == .preferCPU`, `(true, true) == .use`, `(false, false) == .use`.
- [ ] **Step 2: Implement:** `deviceName` from `adapterName`; `largestBuffer` and `ComputeBytes.maximumGroups` from `limits`; under X-C5 (a), `SDLRuntimeKernels`' backend is `.absent("a software rasterizer: the CPU engine is used")` on a software device in the app, unless task 9's x-1 showed lavapipe faster than the CPU in the Linux image (then the default allows it, citing the rows); the tests' backend always allows software devices.
- [ ] **Step 3: Run** (Linux, Windows CI; the inspector on lavapipe shows "llvmpipe (…)"), mark the gaps adopted, update E8, lint, commit, push.

---

## Execution order and verification

Tasks 0 → 10 in order; none waits for MetalUI. Task 11 waits for XP-G25 (and task 12 follows it; if CI cannot compile at run time without the libraries, task 12's steps 2 and 3 come first). Task 13 waits for XP-G23 and XP-G24, and for the user's X-C5.

Done before XP-G25 (task 10's commit): macOS `swift test` exits 0 with 12 lines, the MSL digests unchanged; `swift test --filter CreatorImplicitTests` with and without `.build/generated-kernels` both pass; Linux `scripts/linux-test.sh all` passes with the agreement suites on lavapipe over the offline kernels; Windows CI builds (debug and release) and passes with the HLSL cases skipped by name; `git status` clean after a build. Done after task 12: the same, with Linux and Windows compiling at run time, the packages' self-tests passing in clean environments, and human checks XP-27 to XP-29 ready to run.
