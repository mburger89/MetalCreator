# xp-c: Implicit Evaluation and Meshing on SDL GPU Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Linux and Windows, 7c's implicit evaluation and marching-cubes meshing run on the GPU through MetalUI's SDL_GPU compute, held to the CPU reference by the same agreement suites and tolerances as Metal; macOS keeps `MetalImplicitEngine` unchanged, and the same HLSL also runs on the Mac's GPU in the tests.

**Architecture:** SDL_GPU only takes shaders compiled before the app runs (`SDLGPUShaderBlob` has no public initializer and is loaded only from a compiled directory; xp-3's U1(b) compiles at build time), so the Metal engine's design, one generated source per tree shape compiled at run time, cannot be carried over. Instead a solid compiles to an **`ImplicitProgram`**: fixed-size instructions (an op code, a destination register and six operands) over the same five buffers the Metal source reads, made by `ImplicitProgramCompiler`, which walks the tree exactly as `ImplicitCompiler.Generator` does, so both compilers write identical parameter, integer, table, pool and image buffers (pinned by a test). One HLSL interpreter (`Shaders/implicit/interpreter.hlsli`, a `switch` over 37 ops whose cases are line-for-line ports of `ImplicitShaderLibrary`'s MSL) is the `sdf` of seven compute kernels: `implicit_evaluate` and the five meshing kernels of 7c-1g (`mesh_sample`, `mesh_classify`, `mesh_number`, `mesh_place`, `mesh_emit`) plus `mesh_clear`, which empties the edge table because SDL_GPU has no buffer fill. The kernels are compiled at build time exactly as xp-3's viewport shaders are (`scripts/build-shaders.sh`/`.ps1`, MetalUI's `MetalUICompileShaders`, the pinned SDL_shadercross) into `Shaders/implicit/compiled`, git-ignored, shipped as `ImplicitShaders` beside the executable. **`InterpretedImplicitEngine`** (an actor, portable Swift) drives them through a small protocol, **`ImplicitComputeBackend`** (make a buffer; run one batch of uploads, dispatches, each in a compute pass of its own, and downloads; nothing else). Two backends implement it: **`SDLComputeBackend`** (Linux and Windows, `MetalUISDLGPU`, an owned headless `SDLGPUDevice`), which is `ImplicitGPUEngines.platformDefault` there, and **`MSLComputeBackend`** (macOS, test support only), which loads the MSL that SDL_shadercross made of the same HLSL and binds it the way SDL_GPU's Metal driver does. So the same HLSL and the same engine code run on the Mac's GPU, Linux's lavapipe and Windows' WARP, and `GPUAgreementTests` and `GPUMeshAgreementTests` run over every engine a machine has. The interpreted engine's meshes come back in a **canonical order** (vertices by edge key, triangles by brick, cube and table order; a radix sort on the CPU after readback), so a request meshes to the same arrays every run.

**Tech Stack:** Swift 6.4 strict concurrency, Swift Testing, MetalUI at the CI pin `ff0db06e9cdb8d11de8ee2210f695eb08da271fe` (`MetalUISDLGPU`: `SDLGPUDevice.make()`, `makeBuffer(size:usage:)`, `makeTransferBuffer(size:direction:)`, `compileComputePipeline(_:)`, `submitBatch(_:)`, `SDLGPUFence.wait()`, `SDLGPUCommandBuffer.beginComputePass(readWrite:)`, `copy(_:to:destinationOffset:size:)`, `copy(_:range:to:)`, `SDLGPUComputePass.bind(_:)`, `bind(readOnly:firstSlot:)`, `push(uniform:at:)`, `dispatch(x:y:z:)`, `end()`, `SDLGPUShaderLibrary.locate(directoryName:sourceTree:)`, `compute(_:for:)`; every name checked with `git -C ../MetalUI show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/…`; the layer is unchanged between `ff0db06e` and MetalUI master `63feea05`), HLSL through SDL_shadercross commit `1ff05bec573988a98ef9e0260b4da44f512b8367` (`scripts/shadercross.env`, unchanged), Metal (macOS, the existing engine and the test backend), Mesa lavapipe (Linux, a CPU Vulkan driver) and Direct3D 12 WARP (Windows) in CI.

**Spec:** `docs/superpowers/specs/2026-10-13-cross-platform-design.md` row XP-G2 ("Portable compute (SDL GPU compute) for 7c's implicit engine", after xp-3) and errata E1 to E7, whose E7 ends "Implicit evaluation and meshing stay on the CPU off macOS (xp-c)"; and `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §4.1 to §4.3, §6, §7 and Errata D11 (the CPU is a complete engine; GPU behind a protocol; agreement suite skipped without a GPU evaluator), D13 ("An SDL3 GPU compute implementation for Linux and Windows follows … The user asked for it explicitly"; CPU the reference and fallback; same topology, vertices within 1e-4 mm), D15 (mesher alone 1e-4 mm; whole pipeline surfaces 1e-4 mm, vertices 2e-3 mm), D17 (surface allowance 1e-4 mm ÷ |∇f|, never less than 1e-4 mm), D20 (the amended allowance: twice D17 for `GPUFixtures.meshMarginal`, no mesh comparison inside 4 mm of a Face chart's axis, 7× for the Face-mapped Voronoi struts on a cylinder, an open item), under the parent spec `2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. This plan adds erratum **E8** to the cross-platform spec and erratum **D21** to the implicit spec (task 9; their text is in task 9).

**Branch:** `xp-c` (worktree `../MetalCreator-xp-c`), made from master `7a010ec` on 2026-10-22. MetalUI is the sibling `../MetalUI`, **read-only** (another session owns it). The CI pin `METALUI_COMMIT` stays `ff0db06e…`; xp-c does not bump it.

## User decisions

The choices below touch a spec, a file's bytes or a fallback a person sees. Each has this plan's recommendation; the tasks are written to the recommendation, and the alternative's cost is stated so the user can choose it instead.

**X-C1. How a solid runs on SDL_GPU. Recommended: (a).**
- (a) **A bytecode interpreter in one set of build-time HLSL kernels** (`ImplicitProgram`, `Shaders/implicit/interpreter.hlsli`). Editing a value or changing the tree's shape never compiles a shader; nothing new ships at run time; the kernels are compiled and tested like the viewport's. Cost: an interpreted `sdf` is slower per sample than Metal's specialised one (a `switch` per instruction, registers in scratch memory); bounded by a 32-value, 8-point, 4,096-step program (beyond it: the CPU, with the warning).
- (b) Generate HLSL per shape and compile it at run time with SDL_shadercross linked into the app: specialised speed, but shadercross and DXC (about 40 MB of DLLs and shared objects) would ship in every package, MetalUI has no runtime compile path (`SDLGPUShaderBlob` has no public initializer, so it would be a MetalUI gap first), and a compile on a user's machine can fail in ways CI never sees.

**X-C2. One HLSL source, run on the Mac too. Recommended: (a).**
- (a) **The HLSL kernels are the interpreted engine's only source; on macOS the app keeps `MetalImplicitEngine`, and the tests also run the interpreted engine on the Mac's GPU over the MSL SDL_shadercross made of the HLSL** (`MSLComputeBackend`, test support). The Mac gets the MSL from `scripts/linux-test.sh shaders` (the Linux image compiles into the worktree, which it mounts read-write); without it the Mac's interpreted cases are skipped, by name. macOS needs no shadercross (xp-3's U1(b), U6(a)) and its app is untouched.
- (b) Also ship the interpreted engine as the macOS engine: one engine everywhere, but slower than Metal's specialised kernels on the Mac and a visible change there.

**X-C3. The order of a mesh's vertices and triangles. Recommended: (a).**
- (a) **Canonical on the interpreted engine**: vertices by their lattice edge key, triangles by the brick's place in the request, then the cube in the brick, then the marching-cubes table's order (an O(n) radix sort on the CPU after readback, 4 more bytes a triangle on the GPU). A request meshes to the same arrays run after run on one machine, so an STL or 3MF exported twice on Linux or Windows has the same bytes. Metal's order stays the threads' (D13: "the set is fixed"), so macOS is unchanged.
- (b) Like Metal: the set fixed, the order the threads'. Cheaper by the sort (measured in task 8), but exported files differ from run to run in their byte order.

**X-C4. What the person sees when the GPU engine cannot run. Recommended: (a).**
- (a) **No SDL_GPU device: the CPU, silently** (the machine has no GPU engine; D11's existing rule). **Kernels missing, or a pipeline refused: the CPU with "Running on the CPU"** and the reason in the selection's diagnostic (a broken install or driver the person should hear about), and `--self-test` fails naming the script to run. **A solid beyond the interpreter** (more than 32 values or 8 points held at once, more than 4,096 steps, a distance to a profile): the CPU with the warning, as on Metal. A request beyond the 128 MiB buffer cap or the 32-bit tables: that request on the CPU mesher, silently, as on Metal.
- (b) Silent CPU in every case: simpler, but a package that lost its kernels would be slow with no sign why.

**X-C5. Software devices (Mesa lavapipe, Direct3D 12 WARP). Recommended: (a).**
- (a) **Tests and CI run on them** (`XP_REQUIRE_GPU=1` fails a runner without one). **The app uses whatever device SDL_GPU picks until MetalUI answers gap XP-G23** (the adapter's name and whether it is a software rasterizer); then task 10 makes the app prefer the CPU engine on a software device, unless task 8's rows x-1 and x-2 show lavapipe beating the CPU engine in the Linux image, in which case task 10 keeps it and records why.
- (b) Always use a software device: no gap needed, but a GPU-less Linux VM would run the interpreter through llvmpipe whether or not that is faster than the CPU engine.

**X-C6. Precision. Recommended: (a).**
- (a) **Float everywhere, never `half` or `min16float`; the engine's own sine, cosine and arctangent** (Cody–Waite reduction, Cephes minimax polynomials, about 1 ulp), because Vulkan guarantees only an absolute error of 2^-11 for `sin` on [-π, π] and Direct3D 12 says nothing tighter, while a TPMS wall is scaled by cell ÷ 2π, so 2^-11 would be about 4e-4 mm at a 5 mm cell, four times D11's 1e-4; **the noise's 64-bit hash in pairs of 32-bit words** (exact, so bit-for-bit the CPU's draw), because `uint64_t` needs the `shaderInt64` feature SDL_GPU neither enables nor reports. The tolerances are the 7c spec's, not loosened: 1e-4 mm values, D15, D17 and D20's amended allowance including the 7× Face-mapped Voronoi item.
- (b) The drivers' own `sin`, `cos` and `atan2` and `uint64_t`: shorter HLSL, with agreement that depends on the driver.

**X-C7. Performance budgets. Recommended: (a).**
- (a) **No budget in CI** (lavapipe and WARP are CPU rasterizers, D11's "the CPU path records its numbers without a budget" applies in spirit): rows x-1 (the first pass of a 100 mm gyroid sheet at 0.78 mm) and x-2 (a thickness edit, no recompile) are recorded per engine in `docs/verification/performance.md`. **On this Mac, the interpreted engine over Metal (x-1h) is judged against i-1's 1 s**, a proxy for a desktop GPU. **On a desktop GPU under Linux or Windows, human check XP-27 asks for i-1's 1 s and i-2's 100 ms.**
- (b) Hold the SDL engine to i-1 and i-2 in CI: impossible on CPU rasterizers.

**X-C8. Names a person sees.** The preview badge and the inspector say **"Vulkan"** on Linux and **"Direct3D 12"** on Windows where they say "Metal" on a Mac (the engine's `name`); until gap XP-G23 is answered the inspector's device name is the same word. The compiled kernels ship as **`ImplicitShaders`** beside the executable (the viewport's stay `MetalUIAppShaders`). Recommended as written.

No saved file format, saved setting or document changes: the engine choice is not saved, and a graph saved on any platform evaluates the same way on every other.

## Global Constraints

- **The base is master `7a010ec`** (2026-10-22). If master moves before a task, rebase and take its counts as the baseline (task 0, step 3).
- **MetalUI is never modified**: no edit, no checkout, no stash, no commit, and no build product written into `../MetalUI` (MetalUI's tool is built with `--scratch-path` outside it); `Package.swift`'s `.package(path: "../MetalUI", …)` line is never edited. A MetalUI gap goes in `docs/metalui-gaps.md` (the entry and the summary-table row) and is never worked around: no raw `SDL_` call in MetalCreator code (each typed object's `.raw` stays unused).
- Swift 6 strict concurrency; Swift Testing; one type per file; no force unwraps or force `try`; no GCD; no `String(format:)` or legacy formatters (`CLAUDE.md`, `AGENTS.md`). No `@Observable` type is added.
- `swiftlint lint --strict` reports zero violations before every commit.
- **macOS is unchanged in behaviour**: `MetalImplicitEngine`, `ImplicitCompiler`, `ImplicitShaderLibrary` and `ImplicitMeshShaderLibrary` are not edited (task 1 adds one stored property to `CompiledImplicit`, `nil` for Metal). macOS builds no SDL and runs no shadercross.
- **Portability** (`CLAUDE.md`, "Cross-platform"; implicit spec D11): no Metal outside `#if canImport(Metal)` files named `Metal*.swift` (test support `MSLComputeBackend.swift` is a test file, also wholly under `#if canImport(Metal)`); no `MetalUISDLGPU` outside files named `SDL*.swift` in `Sources/CreatorImplicit/SDL`, each wholly under `#if canImport(MetalUISDLGPU)`; no `SDLGPU…` type named outside them (`ImplicitPortabilityTests`, task 4).
- **The compiled kernels are never committed.** `Shaders/implicit/compiled` is git-ignored and made by `scripts/build-shaders.sh` (`.ps1` on Windows) through MetalUI's `MetalUICompileShaders`; `git status` after a build shows nothing new.
- **HLSL rules for `Shaders/implicit`** (pinned by `ImplicitShaderContractTests`, task 2): no `half`, `min16float`, `double`, `uint64_t` or `int64_t`; no `GetDimensions` (SPIRV-Cross would add a buffer-size binding the backends do not bind); no driver `sin`, `cos`, `tan`, `atan`, `atan2` (use `accSin`, `accCos`, `accAtan2`); every buffer a kernel declares is read or written by it (DXC drops an unused one from the reflection and every later slot would shift); read-only storage is `register(tN, space0)` and read-write `register(uN, space1)`, numbered from 0 without gaps in the order `ImplicitKernel.bindings` lists; the one uniform block is `cbuffer Params : register(b0, space2)` (SDL_GPU's compute convention, MetalUI `docs/packaging.md` §4a). Every operand an instruction reads is read before its result is written (the compiler reuses registers).
- **SDL_GPU compute rules** (SDL's `SDL_gpu.h`, "A VERY IMPORTANT NOTE"): dispatches inside one compute pass are not synchronized, so **every dispatch that reads what an earlier one wrote is in a compute pass of its own** (the backends give each `ComputeDispatch` its own pass); no blocking verb (`submitBatchSynchronously`, `waitBlocking`, `downloadSynchronously`, `waitForIdle`) is called from the engine: it awaits `submitBatch` and `SDLGPUFence.wait()`, so no cooperative-pool thread blocks. A dispatch has at most 65,535 thread groups of 64 threads (Vulkan's guaranteed `maxComputeWorkGroupCount`); a storage buffer is at most 128 MiB (Vulkan's guaranteed `maxStorageBufferRange`, 2^27 bytes) until gap XP-G24 is answered.
- **The Windows Swift 6.4 compiler (learned in xp-1 and xp-2).** (1) Keep heavy loops out of `async` functions: put them in synchronous helpers (an `async` function that holds a loop's locals across an `await` asserts in coroutine splitting, `CoroFrame.cpp`); the engine's `async` loops hold only a range and an index, and the byte packing, the batch building and the canonical sort are synchronous. (2) Do not pass typed-throws closures to generic helpers. (3) In a release build an `async` function that takes a closure and gets closure-specialised can crash the coroutine split: every `async` engine method that takes the `progress` closure is `@_optimize(none)` with a comment saying why (master's `OccupancyGrid.fill(lipschitz:awaiting:)`, `TrappedVolumeCheck.runConcurrently`). If an `async` loop still asserts, rewrite it as recursion over the index (`func sweep(from index: Int) async throws`), which holds no loop locals. (4) **Every task that changes code Windows compiles must pass CI's `swift build -c release` ("Build release (for the zip)" step)**; the Windows job is `continue-on-error`, so read its log. (5) The local check is the 6.4 asserts snapshot: `TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release` (it compiles what macOS compiles: `InterpretedImplicitEngine` yes, the `SDL*.swift` files no, so CI is their check).
- A full `swift test` passes only if the exit code is 0, no line says "recorded an issue" or "failed after", and the number of "Test run with" lines is **12 on macOS, Linux and Windows** (xp-c adds no test target). Test totals are not hard checks: take the baselines in task 0 and compare deltas.
- Linux is verified with `scripts/linux-test.sh` in Docker (OrbStack), **`XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c`** on every call (this track's own container, volume and image); Windows only in CI on the pushed `xp-c` branch (`.github/workflows/xp.yml`).
- **Processes.** Never `pkill`, `killall` or `xargs kill` swift, swift-test, swift-build, swift-frontend or xctest: other sessions (MetalUI's among them) run `swift test` on this Mac. Kill only PIDs you started yourself (captured with `$!`), and stop a Docker run only by this track's container names (`xp-c-linux`, `xp-c-linux-clean`).
- **Line endings.** A text file a test reads must read the same with CRLF: split lines with `split(whereSeparator: \.isNewline)`, never `split(separator: "\n")`. `.gitattributes` already pins `Shaders/**` to LF.
- No third-party code without asking: xp-c adds none (SDL_shadercross is xp-3's approved build tool; the polynomial coefficients are Cephes', public domain, credited in a comment).

## Review Focus

The inputs this plan's tasks would not meet unless asked, most likely to bite first. Each has a test in the task that owns the code.

1. **A tree too big for the interpreter.** A deep nest of blended unions, a lattice inside many moves, a 5,000-child union. It must run on the CPU with "Running on the CPU", never trap, never read past a register array. Task 1, `ImplicitProgramCompilerTests.aTreeThatHoldsTooManyValuesIsUnsupported` and `aProgramOfMoreThan4096StepsIsUnsupported`; task 4, `ImplicitEvaluatorsTests.aSolidBeyondTheInterpreterRunsOnTheCPUWithTheWarning`.
2. **A checkout or package without the compiled kernels on Linux or Windows.** `swift build` alone compiles no shader (U1(b)), so the app can build and then have no kernels. It must still mesh (the CPU) and say "Running on the CPU", and `--self-test` must fail naming the script. Task 4, `SDLComputeBackendTests.aDirectoryWithoutTheKernelsIsBrokenAndSaysWhatToRun`; task 7, `ImplicitShaderCheckTests.aMissingDirectoryFailsTheSelfTestCheckWithAMessageThatSaysWhatToRun`.
3. **A request past the buffer cap or the 32-bit tables.** A fine export window or a huge preview: that request goes to the CPU mesher and the mesh is still made. Task 6, `InterpretedMeshingTests.aMeshBeyondTheLargestTableIsLeftToTheCPU` and `aRequestPastTheBufferCapIsUnsupportedAndTheMesherFallsBack`.
4. **An edit during a long preview.** The pass in flight ends at its next batch with `CancellationError` and the next mesh runs whole. Task 6, `InterpretedMeshingTests.cancellingTheTaskEndsAMeshAtItsNextBatchAndNotTheNextMesh` and `anEngineCancelEndsAMeshAtItsNextBatchAndNotTheNextMesh`; task 3, `InterpretedEngineTests.cancelEndsABatchAtItsNextDispatchAndNotTheOnesAfter`.
5. **The angle's cut and the axis of a mapped lattice, and noise at negative lattice coordinates.** `atan2` on the cut (y exactly 0 on either side of the axis) and at the axis (x = y = 0), and the hash of negative cell indices, are where a port goes subtly wrong. Task 3, `InterpretedEngineTests.theAngleOnTheCutAndAtTheAxisAgreesWithTheCPU`; the noise fixtures of `GPUAgreementTests` sample from -18 to 18 mm.
6. **The same export twice.** On Linux and Windows two exports of one graph must be byte-identical (X-C3). Task 5, `InterpretedMeshingTests.theSameRequestMeshesToTheSameArraysEveryTime`; human check XP-28.

---

## Shared files

Other tracks still open (the MetalUI adoption track, 7c follow-ups) may edit the same files; the side that merges second keeps everything listed.

| File | Edited by xp-c | The second merge must keep |
|---|---|---|
| `Package.swift` | `metalUISDL`, `metalUISDLGPU` added to `CreatorImplicit` and `CreatorImplicitTests`; the `metalUISDLGPU` comment (task 4) | both sides' dependency lists; no xp-c line inside an `#if os(…)` block |
| `scripts/build-shaders.sh`, `scripts/build-shaders.ps1` | compile every set in `Shaders/` (`viewport`, `implicit`), each into its own `compiled` (task 2) | xp-3's pin checks and messages; the viewport set's output is unchanged |
| `scripts/linux-test.sh` | a `shaders` verb (task 2) | every existing verb |
| `scripts/package-linux.sh`, `scripts/package-windows.ps1`, `docs/packaging.md` | `Shaders/implicit/compiled` copied as `ImplicitShaders`; the zip's self-test moves it aside too (task 7) | `MetalUISDLShaders` and `MetalUIAppShaders` |
| `Sources/CreatorApp/SelfTest.swift` | `ImplicitShaderCheck.run()` beside `ViewportShaderCheck.run()`, and its detail string (task 7) | both checks |
| `.gitignore` | `/Shaders/implicit/compiled` (task 2) | both lines |
| `CLAUDE.md`, `docs/metalui-gaps.md`, `docs/verification/human-checks.md`, `docs/verification/performance.md`, both specs | task 0 (gaps), task 8 (performance), task 9 (the rest) | both sides' paragraphs and rows; a gap either branch adds next takes XP-G25; a human check, XP-30; a cross-platform erratum, E9; an implicit erratum, D22 |
| `Tests/CreatorImplicitTests/GPUAgreementTests.swift`, `GPUMeshAgreementTests.swift` | run over every engine a machine has (tasks 3 and 6); the Metal-only dispatch tests move to `MetalEngineDispatchTests.swift` unchanged | the fixtures and allowances; a 7c follow-up's new fixture runs on every engine |

## Key decisions (made by this plan)

- **The interpreter's operands.** An operand word `x ≥ 0` is register `x`; `x < 0` is float parameter slot `-x - 1` (for a point, slots `-x - 1` to `-x + 1`). A raw word (an integer slot, a buffer offset, a constant's bits) is the op's to read as it says. Register `v0` holds the point being evaluated; the compiler never gives it out. Registers are given back after their one read, lowest first, so a union of any number of children holds three values; the blend width of a combination and the local point of a move are held for their subtree.
- **The buffers are Metal's.** `ImplicitProgramCompiler` appends to `parameters`, `integers`, `tables`, `pool` and `images` in exactly the order `ImplicitCompiler.Generator` does, so the library functions read the same offsets and a test proves both compilers' buffers equal on every fixture. The interpreted engine packs them into two storage buffers (floats: parameters, then pool, then images; ints: integers, then tables) with the bases in the uniform block, so no kernel declares more than six read-only storage buffers.
- **One uniform block for every kernel**, `KernelParameters`: 16 four-byte words (64 bytes), the same in Swift and HLSL (`ImplicitShaderContractTests`).
- **An owned, headless device.** `SDLComputeBackend` makes its own `SDLGPUDevice.make()` (no window needed, MetalUI guide "Compute needs no window") rather than borrowing the viewport's: the engine evaluates before any window draws, in headless tests and in exports, off the main actor, and its batches never wait behind a frame. Its mesh comes back to the CPU as `BrickMesh` arrays, as Metal's does.
- **Made lazily, off the main actor.** `InterpretedImplicitEngine.sdl` is a static let that costs nothing to make; the device, the kernel library and the seven pipelines are made on the engine's first `availability`, `compile` or `evaluate` (inside the actor), and the result is kept: `ImplicitEvaluators.make`'s default argument is evaluated on the caller's actor, which may be the main one.
- **`ImplicitGPUEngine` gains `availability`** (`.available`, `.absent(reason)`, `.broken(reason)`, default `.available`, so Metal and the stub are unchanged), which `ImplicitEvaluators.make` reads before it compiles (X-C4).
- **Batches.** One `ComputeBatch` is one `submitBatch`: its uploads (each through a transfer buffer), its dispatches (each in its own compute pass), its downloads (into transfer buffers, mapped after the fence). An evaluation chunk is one batch (upload the points, dispatch, download the values); a meshing step is one batch per brick batch or slot range, as Metal's command buffers are.
- **Sizes for the watchdog.** SDL's engine meshes 1,024 bricks a batch (Metal 4,096) and numbers or places 2^18 table slots a batch (Metal 2^20), and evaluates 2^20 points a dispatch (Metal 2^22): an interpreted `sdf` costs more, and Windows' TDR resets a GPU whose work runs past about 2 s. The tests tune them down further to reach the many-batch paths.
- **The canonical order (X-C3)** is made on the CPU: `mesh_place` writes each vertex's edge key beside its position (`uint4`), `mesh_emit` writes one tag a triangle (the brick's place in the request × 512 + the cube), and `MeshCanonicalOrder` sorts by them with a stable radix sort. A request of 8,388,608 bricks or more (`UInt32.max / 512`) is the CPU's.

## File structure

**Portable, `Sources/CreatorImplicit`**

| File | Responsibility |
|---|---|
| `Interpreter/ImplicitOp.swift` | the 37 op codes, `Int32` raw values 1 to 37, the HLSL's `OP_…` numbers |
| `Interpreter/ImplicitProgram.swift` | a compiled program: its words and its limits (32 values, 8 points, 4,096 steps, 8 words a step) |
| `Interpreter/ProgramOperand.swift` | what an instruction's operand word holds, and whose register it is |
| `Interpreter/ImplicitProgramBuilder.swift` | registers, numbers, `emit`, the solids (mirrors `ImplicitCompiler.Generator`) |
| `Interpreter/ImplicitProgramBuilder+Lattices.swift` | TPMS, struts, Voronoi, the mappings and the cut |
| `Interpreter/ImplicitProgramBuilder+Fields.swift` | gradings and the 14 field kinds |
| `Interpreter/ImplicitProgramCompiler.swift` | `compile(_:)`: a `CompiledImplicit` whose `program` is set |
| `Metal/CompiledImplicit.swift` (changed) | a `program: ImplicitProgram?` property, `nil` for Metal |
| `GPU/ImplicitEngineAvailability.swift` | `.available`, `.absent(String)`, `.broken(String)` |
| `GPU/ImplicitGPUEngine.swift` (changed) | the `availability` requirement and its default |
| `GPU/ImplicitEvaluators.swift` (changed) | reads `availability` before compiling (X-C4) |
| `GPU/ImplicitGPUEngines.swift` (changed) | `platformDefault` is the SDL engine off macOS; `meshesMade()` |
| `GPU/ImplicitShaderCheck.swift` | `--self-test`'s question: were the implicit kernels built and shipped |
| `Compute/ImplicitKernel.swift` | the seven kernels, their file names and their buffer counts |
| `Compute/KernelParameters.swift` | the 64-byte uniform block |
| `Compute/ImplicitComputeBackend.swift` | `ComputeBuffer`, `ImplicitComputeBackend`, `ComputeBackendState` |
| `Compute/ComputeBatch.swift` | `ComputeUpload`, `ComputeDispatch`, `ComputeDownload`, `ComputeBatch` |
| `Compute/ComputeBytes.swift` | synchronous packing and unpacking, dispatch ranges |
| `Compute/InterpretedImplicitEngine.swift` | the actor: availability, compile, prepare, evaluate, cancel, the solid's buffers |
| `Compute/InterpretedImplicitEngine+Meshing.swift` | `meshBricks`: the attempts, the sweeps, the readback |
| `Compute/InterpretedMeshJob.swift` | the meshing job, run and output buffers, and the synchronous batch builders |
| `Compute/MeshCanonicalOrder.swift`, `Compute/RadixSort.swift` | the canonical order (X-C3) |

**SDL, `Sources/CreatorImplicit/SDL`** (each file wholly under `#if canImport(MetalUISDLGPU)`)

| File | Responsibility |
|---|---|
| `SDLComputeBackend.swift` | the backend over `MetalUISDLGPU`: device, pipelines, buffers, `run` |
| `SDLComputeRecording.swift` | one batch prepared for the worker thread (transfer buffers filled, groups counted) and its readback |
| `SDLComputeBuffer.swift` | an `SDLGPUBuffer` as a `ComputeBuffer` |
| `SDLImplicitShaders.swift` | where the compiled kernels are (`ImplicitShaders` beside the executable, else `Shaders/implicit/compiled`) |
| `SDLImplicitEngine.swift` | `InterpretedImplicitEngine.sdl`, the platform's engine |

**Shaders, `Shaders/implicit`**: `contract.hlsli` (op codes, limits, table offsets, counters, `cbuffer Params`), `accurate_math.hlsli`, `wide_integer.hlsli`, `library.hlsli`, `lattices.hlsli`, `interpreter.hlsli`, `mesh_common.hlsli`, `mesh_cubes.hlsli`, `mesh_lattice.hlsli`, and the kernels `implicit_evaluate.comp.hlsl`, `mesh_clear.comp.hlsl`, `mesh_sample.comp.hlsl`, `mesh_classify.comp.hlsl`, `mesh_number.comp.hlsl`, `mesh_place.comp.hlsl`, `mesh_emit.comp.hlsl`; `compiled/` is generated and git-ignored.

**Tests, `Tests/CreatorImplicitTests`**: new `ImplicitProgramCompilerTests`, `ImplicitShaderContractTests`, `InterpretedEngineTests`, `InterpretedMeshingTests`, `MeshCanonicalOrderTests`, `SDLComputeBackendTests` (Linux and Windows), `ImplicitGPUAvailabilityTests`, `ImplicitShaderCheckTests`, `MetalEngineDispatchTests` (moved from `GPUAgreementTests`), `ImplicitBenchInterpreted`; support `Support/MSLComputeBackend.swift`, `Support/MSLComputeBuffer.swift` (macOS), `Support/GPUEnginesUnderTest.swift`; changed `GPUAgreementTests`, `GPUMeshAgreementTests`, `ImplicitEvaluatorsTests`, `GPUBatchEvaluatorTests`, `ImplicitPortabilityTests`, `Support/StubGPUEngine.swift`.

---

## Tasks

### Task 0: Baselines, the two MetalUI gaps, and a check of the API this plan names

**Files:**
- Modify: `docs/metalui-gaps.md` (two summary rows after XP-G22's, one section at the end)

**Interfaces:**
- Consumes: nothing.
- Produces: the baselines every later task compares with; gap numbers XP-G23 and XP-G24, cited by tasks 4, 9 and 10.

- [ ] **Step 1: Confirm the branch and the MetalUI pin.**

Run:
```bash
cd /Users/maxburger/Developer/MetalCreator-xp-c
git log --oneline -1                     # 7a010ec docs: metalui-gaps notes the pin is now ff0db06e (or a later master after a rebase)
grep -n "METALUI_COMMIT:" .github/workflows/xp.yml   # METALUI_COMMIT: ff0db06e9cdb8d11de8ee2210f695eb08da271fe
git -C ../MetalUI diff --stat ff0db06e 63feea05 -- Backends/SDL/Sources/MetalUISDLGPU Sources/MetalUIShaderCompile
```
Expected: the last command prints nothing (the typed SDL_GPU layer and the shader tool are the same at the pin and at MetalUI's master). If it prints a change, read it before tasks 3 and 4 and note in the task's commit message which name moved. Never check anything out in `../MetalUI`.

- [ ] **Step 2: Check every MetalUI name this plan uses at the pin.**

Run:
```bash
cd /Users/maxburger/Developer/MetalUI
for name in "static func make(debug" "func makeBuffer(size" "func makeTransferBuffer(size" "func compileComputePipeline" \
            "func submitBatch(_ record" "lastFailure" "var driver"; do
  git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUDevice.swift | grep -c "$name"; done
for name in "func beginComputePass(readWrite" "func copy(_ source: SDLGPUTransferBuffer" "func copy(_ source: SDLGPUBuffer, range" \
            "func bind(_ pipeline" "func bind(readOnly" "func push(uniform" "func dispatch(x" "func end()"; do
  git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUCompute.swift | grep -c "$name"; done
git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUShaderLibrary.swift | grep -c "public static func locate(directoryName"
git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUFence.swift | grep -c "public func wait() async"
git show ff0db06e:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUBuffer.swift | grep -c "public func map()"
```
Expected: every count is 1 or more. A 0 means the API moved: stop and report it (it is a MetalUI change, not something to work around).

- [ ] **Step 3: Take the baselines.**

Run (macOS, idle enough to finish):
```bash
cd /Users/maxburger/Developer/MetalCreator-xp-c
swift test 2>&1 | tee .build/xp-c-baseline-mac.log | grep -c "Test run with"        # 12
grep "Test run with" .build/xp-c-baseline-mac.log | sed -E 's/.*with ([0-9]+) tests.*/\1/' | paste -sd+ - | bc
swift test --filter CreatorImplicitTests 2>&1 | grep "Test run with"
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test 2>&1 | tail -3   # Linux: PASS (12 'Test run with' lines, N tests)
```
Expected: 12 lines on each; write the macOS total, the `CreatorImplicitTests` count and the Linux total into the task's commit message (`Baselines: macOS N tests, CreatorImplicitTests M, Linux L`). Later tasks state their counts as `baseline + n`.

- [ ] **Step 4: Log XP-G23 and XP-G24 in `docs/metalui-gaps.md`.**

In the summary table, after the XP-G22 row (keep XP-G21's row where it is), add:
```markdown
| XP-G23 | The SDL_GPU adapter's name, and whether it is a software rasterizer (lavapipe, llvmpipe, WARP) | MetalUI (SDL GPU layer) | ❌ open (xp-c): until answered, the implicit engine's device name is its driver's ("Vulkan", "Direct3D 12") and a software device is used like a hardware one |
| XP-G24 | SDL_GPU device limits for compute: the largest storage buffer a binding may span, the most thread groups a dispatch may have | MetalUI (SDL GPU layer) | ❌ open (xp-c): until answered, the implicit engine assumes Vulkan's guaranteed minimums (2^27 bytes, 65,535 groups) |
```
At the end of the file add:
```markdown
## Hit by implicit evaluation and meshing on SDL GPU (xp-c), 2026-10-22

Plan `docs/superpowers/plans/2026-10-22-xp-c-sdl-gpu-meshing.md`, checked against MetalUI `ff0db06e` (the CI pin; its SDL_GPU layer is the same at
master `63feea05`). XP-G2 (portable compute) was answered by MetalUI S5 and is what xp-c runs on: an owned headless `SDLGPUDevice.make()`,
`compileComputePipeline`, `submitBatch` with one compute pass per dependent dispatch, `InterlockedAdd` and `InterlockedCompareExchange` on read-write
storage buffers, transfer-buffer uploads and downloads awaited on the fence. Nothing is worked around and no raw `SDL_` call is made.

- **XP-G23. The adapter's name, and whether it is a software rasterizer.** The Mesh node's inspector says which device meshed (`ImplicitGPUEngine.deviceName`;
  Metal's is `MTLDevice.name`, "Apple M3 Max"), and the app should prefer its CPU engine on a software Vulkan or Direct3D 12 device (Mesa's lavapipe,
  `llvmpipe (LLVM …)`; Microsoft's WARP, "Microsoft Basic Render Driver"), where interpreting the solid in a CPU-emulated shader can be slower than the CPU
  engine itself (xp-c's user decision X-C5; measured by rows x-1 and x-2). `SDLGPUDevice` offers `driver` only ("vulkan", "direct3d12"). SDL 3.4 has
  `SDL_GetGPUDeviceProperties` with `SDL_PROP_GPU_DEVICE_NAME_STRING`, `SDL_PROP_GPU_DEVICE_DRIVER_NAME_STRING` and `…_DRIVER_INFO_STRING`. Needed:
  `SDLGPUDevice.adapterName: String?` and `SDLGPUDevice.isSoftwareRasterizer: Bool` (true for a Vulkan `VK_PHYSICAL_DEVICE_TYPE_CPU` device or
  D3D12's WARP adapter; MetalUI's ruling decides how it is told). Meanwhile: the device name is the driver's, a software device is used, and CI is
  unaffected (it wants the software device).
- **XP-G24. Compute limits.** The implicit engine sizes its edge table, its sample buffer and its dispatches to what the device can bind: on Metal it
  reads `MTLDevice.maxBufferLength`. SDL_GPU reports no limit, so the engine assumes Vulkan's guaranteed minimums: a storage buffer of 2^27 bytes
  (`maxStorageBufferRange`) and 65,535 thread groups a dimension (`maxComputeWorkGroupCount`), which caps a mesh's edge table at 2^25 slots (Metal's
  is 2^27) and sends a larger request to the CPU mesher. Needed: `SDLGPUDevice.limits` with at least `maxStorageBufferBindingSize` and
  `maxComputeWorkGroupCount` (or MetalUI's documented statement of the minimum SDL_GPU guarantees on every backend, if SDL cannot report them).
  Meanwhile the minimums above.

What xp-c does not need, and so does not ask for: a runtime shader compiler (`SDLGPUShaderBlob` has no public initializer, and the interpreter's
kernels are compiled at build time like the viewport's), indirect dispatch, storage textures, a buffer fill (the `mesh_clear` kernel empties the table),
and a blocking submit (the engine awaits every fence).
```

- [ ] **Step 5: Commit.**

```bash
git add docs/metalui-gaps.md
git commit -m "docs: log MetalUI gaps XP-G23 (adapter name, software rasterizer) and XP-G24 (compute limits) for xp-c

Baselines: macOS N tests, CreatorImplicitTests M, Linux L (12 'Test run with' lines each).

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```
(Put the measured numbers in place of N, M and L.)

---

### Task 1: The bytecode: `ImplicitOp`, `ImplicitProgram` and `ImplicitProgramCompiler`

Portable Swift, no GPU: runs and is tested on all three platforms.

**Files:**
- Create: `Sources/CreatorImplicit/Interpreter/ImplicitOp.swift`, `ImplicitProgram.swift`, `ProgramOperand.swift`, `ImplicitProgramBuilder.swift`, `ImplicitProgramBuilder+Lattices.swift`, `ImplicitProgramBuilder+Fields.swift`, `ImplicitProgramCompiler.swift`
- Modify: `Sources/CreatorImplicit/Metal/CompiledImplicit.swift` (one stored property, one init parameter)
- Test: `Tests/CreatorImplicitTests/ImplicitProgramCompilerTests.swift`

**Interfaces:**
- Consumes: `ImplicitSolid`, `Grading`, `Field`, `DistanceBlocks`, `LatticeMapping`, `FaceMap`, `ImplicitCompileError`, `CompiledImplicit`, `ImplicitCompiler.compile(_:)` (the buffers to match).
- Produces:
  - `public enum ImplicitOp: Int32, CaseIterable, Sendable` (37 cases, raw values 1…37, in the order below).
  - `public struct ImplicitProgram: Sendable, Equatable { public static let maximumScalars = 32, maximumVectors = 8, maximumInstructions = 4096, wordsPerInstruction = 8; public let words: [Int32]; public let scalarsUsed: Int; public let vectorsUsed: Int; public var instructionCount: Int }`.
  - `CompiledImplicit.program: ImplicitProgram?` (`nil` from `ImplicitCompiler`).
  - `public enum ImplicitProgramCompiler { public static func compile(_ solid: ImplicitSolid) throws(ImplicitCompileError) -> CompiledImplicit }` (its `source` is `""`, its buffers are `ImplicitCompiler`'s, its `program` is set).

- [ ] **Step 1: Write the failing tests.**

`Tests/CreatorImplicitTests/ImplicitProgramCompilerTests.swift`:
```swift
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The interpreter's compiler (plan xp-c, task 1): it reads the same buffers as the Metal source, so the shader library's functions find the same
/// offsets, and its programs stay within the interpreter's registers and steps, or say they cannot.
struct ImplicitProgramCompilerTests {
    /// Every solid the GPU suites use, by name.
    static var fixtures: [(name: String, solid: ImplicitSolid)] {
        GPUFixtures.all + LatticeFixtures.everyMapped + ImplicitFixtures.all
    }

    @Test(arguments: fixtures.map(\.name))
    func everyFixtureReadsTheSameBuffersAsItsMetalSource(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        let metal = try? ImplicitCompiler.compile(solid)
        let program = try? ImplicitProgramCompiler.compile(solid)
        #expect((metal == nil) == (program == nil), "\(name): one compiler refused what the other took")
        guard let metal, let program else { return }
        #expect(program.parameters == metal.parameters, "\(name): the float parameters")
        #expect(program.integers == metal.integers, "\(name): the integer parameters")
        #expect(program.tables == metal.tables, "\(name): the tables")
        #expect(program.pool == metal.pool, "\(name): the pool")
        #expect(program.images == metal.images, "\(name): the pictures")
        #expect(metal.program == nil && program.program != nil)
    }

    @Test(arguments: fixtures.map(\.name))
    func everyFixtureFitsTheRegistersAndEndsInAResult(_ name: String) throws {
        let solid = try #require(Self.fixtures.first { $0.name == name }?.solid)
        guard let compiled = try? ImplicitProgramCompiler.compile(solid) else { return }
        let program = try #require(compiled.program)
        let words = ImplicitProgram.wordsPerInstruction
        #expect(program.words.count == program.instructionCount * words)
        #expect(program.instructionCount <= ImplicitProgram.maximumInstructions)
        #expect(program.scalarsUsed <= ImplicitProgram.maximumScalars && program.vectorsUsed <= ImplicitProgram.maximumVectors)
        #expect(program.words[program.words.count - words] == ImplicitOp.result.rawValue, "\(name): the last step is the result")
        for step in 0..<program.instructionCount {
            let op = try #require(ImplicitOp(rawValue: program.words[step * words]), "\(name): step \(step) has no op")
            if op != .result {
                #expect(program.words[step * words + 1] >= 0, "\(name): step \(step) writes a register")
            }
        }
    }

    @Test func aUnionOfAHundredSpheresHoldsAFewValuesAtOnce() throws {
        let spheres = (0..<100).map { ImplicitSolid.moved(.sphere(radius: 1), RigidMove(origin: Vector3(Double($0), 0, 0), xAxis: Vector3(1, 0, 0), yAxis: Vector3(0, 1, 0), zAxis: Vector3(0, 0, 1))) }
        let program = try #require(try ImplicitProgramCompiler.compile(.union(spheres, blend: .constant(0.5))).program)
        #expect(program.scalarsUsed <= 4, "the children are folded as they come, not held")
        #expect(program.vectorsUsed == 2, "the point and one moved point")
    }

    @Test func aTreeThatHoldsTooManyValuesIsUnsupported() {
        // Each level's blend width is held while the level's first child, the next level, is evaluated.
        var solid = ImplicitSolid.sphere(radius: 1)
        for _ in 0..<40 { solid = .union([solid, .sphere(radius: 2)], blend: .constant(0.5)) }
        #expect(throws: ImplicitCompileError.self) { try ImplicitProgramCompiler.compile(solid) }
    }

    @Test func aProgramOfMoreThan4096StepsIsUnsupported() {
        let spheres = (0..<2_100).map { ImplicitSolid.moved(.sphere(radius: 1), RigidMove(origin: Vector3(Double($0), 0, 0), xAxis: Vector3(1, 0, 0), yAxis: Vector3(0, 1, 0), zAxis: Vector3(0, 0, 1))) }
        #expect(throws: ImplicitCompileError.self) { try ImplicitProgramCompiler.compile(.union(spheres, blend: .constant(0))) }
    }

    @Test func aDistanceToAProfileIsUnsupportedAsOnMetal() {
        #expect(throws: ImplicitCompileError.self) { try ImplicitProgramCompiler.compile(ImplicitEvaluatorsTests.profileSolid) }
    }

    @Test func solidsOfOneShapeHaveOneProgramAndDifferOnlyInTheirNumbers() throws {
        let small = try ImplicitProgramCompiler.compile(.sphere(radius: 5))
        let large = try ImplicitProgramCompiler.compile(.sphere(radius: 25))
        #expect(small.program == large.program, "an edit of a value is not a new program")
        #expect(small.parameters != large.parameters)
    }

    @Test func theOpCodesAreOneToThirtySevenInOrder() {
        #expect(ImplicitOp.allCases.map(\.rawValue) == Array(1...37))
    }
}
```
`RigidMove(origin:xAxis:yAxis:zAxis:)` is `Sources/CreatorImplicit/Solid/RigidMove.swift`'s initializer; `ImplicitEvaluatorsTests.profileSolid` is a `static let` of that suite.

- [ ] **Step 2: Run them to see them fail.**

Run: `swift test --filter CreatorImplicitTests.ImplicitProgramCompilerTests 2>&1 | tail -5`
Expected: build failure, "cannot find 'ImplicitProgramCompiler' in scope".

- [ ] **Step 3: Write the op codes and the program.**

`Sources/CreatorImplicit/Interpreter/ImplicitOp.swift`:
```swift
/// One step of an `ImplicitProgram` (plan xp-c; implicit spec erratum D21): the HLSL interpreter's `OP_…` numbers, pinned to
/// `Shaders/implicit/contract.hlsli` by `ImplicitShaderContractTests`. Each is a port of one statement `ImplicitCompiler.Generator` writes; the
/// operands are listed as the interpreter reads them (S: a scalar operand, V: a point operand, raw: a word the op reads as it is, I: the
/// integer parameter at a raw slot). Every op writes register `destination`, a scalar register unless marked "→ point".
public enum ImplicitOp: Int32, CaseIterable, Sendable {
    /// raw a: the bits of a `Float`.
    case constant = 1
    /// length(V a) − S b.
    case sphere
    /// sdBox(V a, V b, S c).
    case box
    /// sdCylinder(V a, S b, S c).
    case cylinder
    /// → point: (dot(V a − V b, V c), dot(…, V d), dot(…, V e)).
    case move
    /// max(0, S a).
    case positive
    /// smoothMin(S a, S b, S c).
    case smoothUnion
    /// −smoothMin(−S a, −S b, S c).
    case smoothIntersect
    /// −smoothMin(−S a, S b, S c).
    case smoothSubtract
    /// S a − S b.
    case difference
    /// The shell: |S a − centre| − S b / 2, the centre from the side I(raw c) and the wall S b.
    case shell
    /// bakedValue(raw a, raw b, V c).
    case baked
    /// max((S a − S b) / S c, regionDistance(V d, V e, V f)).
    case isosurface
    /// tpmsBody(V a, S b, V c, S d, I(raw e), I(raw e + 1), S f).
    case tpms
    /// strutBody(I(raw a), I(raw a + 1), V b, S c, V d, S e, S f).
    case struts
    /// voronoiBody(raw a, raw b, V c, S d, I(raw e), S f).
    case voronoi
    /// → point: mapCylindrical(V a, V b, V c, V d, V e, S f).
    case mapCylindrical
    /// singularCylindrical(V a, V b, V c, V d).
    case singularCylindrical
    /// → point: mapSpherical(V a, V b, S c).
    case mapSpherical
    /// singularSpherical(V a, V b).
    case singularSpherical
    /// → point: mapFace(raw a, V b, S c, S d).
    case mapFace
    /// bakedChannel(raw a, raw b, V c).
    case bakedChannel
    /// mappingJoin(S a, S b, S c, S d).
    case mappingJoin
    /// max(S a, regionDistance(V b, V c, V d)): a lattice cut to its region.
    case region
    /// length(V a − V b).
    case pointDistance
    /// dot(V a − V b, V c) / S d.
    case linear
    /// length(V a − V b) / S c.
    case radial
    /// fieldNoise(V a, S b, I(raw c), I(raw c + 1)).
    case noise
    /// → point: V a − V b.
    case vectorDifference
    /// imageValue(raw f, dot(V a, V b) / S d + 0.5, 0.5 − dot(V a, V c) / S e).
    case image
    /// S a + S b.
    case add
    /// S a × S b.
    case multiply
    /// min(S a, S b).
    case minimum
    /// max(S a, S b).
    case maximum
    /// remapField(S a, S b, S c, S d, S e, I(raw f)).
    case remap
    /// min(max(S a, S b), S c).
    case clamp
    /// The program's value is S a; nothing after it runs.
    case result
}
```

`Sources/CreatorImplicit/Interpreter/ImplicitProgram.swift`:
```swift
/// A solid compiled for the HLSL interpreter (plan xp-c; implicit spec erratum D21): `instructionCount` steps of `wordsPerInstruction` words each,
/// an op, a destination register and six operands. An operand word `x ≥ 0` is register `x` (a scalar or a point, as the op reads it); `x < 0` is
/// the float parameter at slot `-x - 1` (a point's three slots from there); a raw operand is the op's to read as it says (`ImplicitOp`). Point
/// register 0 holds the point being evaluated. The words depend on the tree's shape only: the numbers are in `CompiledImplicit`'s buffers, so an
/// edit of a value never makes a new program, and the interpreter is the same for every program.
public struct ImplicitProgram: Sendable, Equatable {
    /// The interpreter's scalar registers (`MAX_SCALARS`).
    public static let maximumScalars = 32
    /// Its point registers, the evaluated point's included (`MAX_VECTORS`).
    public static let maximumVectors = 8
    /// The most steps a program may have.
    public static let maximumInstructions = 4096
    /// Words a step (`INSTRUCTION_WORDS`): the op, the destination and six operands.
    public static let wordsPerInstruction = 8

    /// The steps, `wordsPerInstruction` words each.
    public let words: [Int32]
    /// How many scalar registers the program uses, at most `maximumScalars`.
    public let scalarsUsed: Int
    /// How many point registers it uses, the evaluated point's included.
    public let vectorsUsed: Int

    public var instructionCount: Int { words.count / Self.wordsPerInstruction }

    public init(words: [Int32], scalarsUsed: Int, vectorsUsed: Int) {
        self.words = words
        self.scalarsUsed = scalarsUsed
        self.vectorsUsed = vectorsUsed
    }
}
```

`Sources/CreatorImplicit/Interpreter/ProgramOperand.swift`:
```swift
/// What an operand word of an `ImplicitProgram` holds, as the builder knows it: a register it gave out (to take back once the value is read), a float
/// parameter slot, or a raw word.
struct ProgramOperand: Hashable {
    /// The word: the register's index, or `-(slot + 1)` for a parameter, or the raw value.
    let code: Int32
    /// The register to give back, or `nil` for a parameter, a raw word and the evaluated point.
    let register: Int?
    /// Whether it is a point (three floats).
    let isVector: Bool

    /// The point being evaluated: point register 0, never given back.
    static let point = ProgramOperand(code: 0, register: nil, isVector: true)

    static func scalarParameter(_ slot: Int) -> ProgramOperand {
        ProgramOperand(code: Int32(-(slot + 1)), register: nil, isVector: false)
    }

    static func vectorParameter(_ slot: Int) -> ProgramOperand {
        ProgramOperand(code: Int32(-(slot + 1)), register: nil, isVector: true)
    }

    /// A word the op reads as it is: an integer slot, a buffer offset, a constant's bits.
    static func raw(_ value: Int) -> ProgramOperand {
        ProgramOperand(code: Int32(truncatingIfNeeded: value), register: nil, isVector: false)
    }
}
```

- [ ] **Step 4: Write the builder (registers and solids).**

`Sources/CreatorImplicit/Interpreter/ImplicitProgramBuilder.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Builds an `ImplicitProgram` (plan xp-c): the walk of `ImplicitCompiler.Generator`, case for case and in the same order, so the five buffers come
/// out identical (`ImplicitProgramCompilerTests` checks every fixture). Where the generator declares a variable this emits a step; where it names a
/// number this names a parameter slot. Registers are given back after their one read, so a step's result may reuse an operand's register (the
/// interpreter reads every operand before it writes); `shared` holds the values read more than once (a combination's blend width, a move's local
/// point) until their subtree is done.
struct ImplicitProgramBuilder {
    var parameters: [Float] = []
    var integers: [Int32] = []
    var tables: [Int32] = []
    var pool: [Float] = []
    var images: [Float] = []
    var registered: [ObjectIdentifier: (integers: Int, parameters: Int)] = [:]

    private(set) var words: [Int32] = []
    private var freeScalars = Array(0..<ImplicitProgram.maximumScalars)
    private var freeVectors = Array(1..<ImplicitProgram.maximumVectors)
    private(set) var scalarsUsed = 0
    private(set) var vectorsUsed = 1
    var shared: Set<ProgramOperand> = []

    // MARK: Numbers

    mutating func number(_ value: Double) -> ProgramOperand {
        parameters.append(Float(value))
        return .scalarParameter(parameters.count - 1)
    }

    /// An integer parameter's slot.
    mutating func integer(_ value: Int) -> Int {
        integers.append(Int32(truncatingIfNeeded: value))
        return integers.count - 1
    }

    mutating func vector(_ value: Vector3) -> ProgramOperand {
        let slot = parameters.count
        parameters += [Float(value.x), Float(value.y), Float(value.z)]
        return .vectorParameter(slot)
    }

    /// `ImplicitCompiler.Generator.register(_:)`, word for word.
    mutating func register(_ blocks: DistanceBlocks) -> (integers: Int, parameters: Int) {
        if let known = registered[ObjectIdentifier(blocks)] { return known }
        let slot = (integers: integers.count, parameters: parameters.count)
        integers += [Int32(tables.count), Int32(pool.count), Int32(pool.count + blocks.pool.count),
                     Int32(blocks.blockCounts[0]), Int32(blocks.blockCounts[1]), Int32(blocks.blockCounts[2]),
        ]
        tables += blocks.table
        pool += blocks.pool
        pool += blocks.coarse
        parameters += [Float(blocks.origin.x), Float(blocks.origin.y), Float(blocks.origin.z), Float(blocks.spacing)]
        registered[ObjectIdentifier(blocks)] = slot
        return slot
    }

    // MARK: Steps

    /// Appends `op` over `operands` (at most six) and returns its result, a scalar unless `vector`. The operands' registers are given back first.
    mutating func emit(_ op: ImplicitOp, _ operands: [ProgramOperand], vector: Bool = false) throws(ImplicitCompileError) -> ProgramOperand {
        guard words.count / ImplicitProgram.wordsPerInstruction < ImplicitProgram.maximumInstructions - 1 else {
            throw .unsupported("a solid of more than \(ImplicitProgram.maximumInstructions) steps")
        }
        var given: Set<ProgramOperand> = []
        for operand in operands where !given.contains(operand) {
            given.insert(operand)
            release(operand)
        }
        let destination = vector ? try allocateVector() : try allocateScalar()
        append(op, destination: destination, operands)
        return ProgramOperand(code: Int32(destination), register: destination, isVector: vector)
    }

    /// The last step: the program's value is `value`.
    mutating func finish(_ value: ProgramOperand) {
        append(.result, destination: 0, [value])
    }

    private mutating func append(_ op: ImplicitOp, destination: Int, _ operands: [ProgramOperand]) {
        words.append(op.rawValue)
        words.append(Int32(destination))
        for index in 0..<6 { words.append(index < operands.count ? operands[index].code : 0) }
    }

    /// Gives `operand`'s register back, unless it is shared or not a register.
    mutating func release(_ operand: ProgramOperand) {
        guard let register = operand.register, !shared.contains(operand) else { return }
        if operand.isVector {
            freeVectors.append(register)
            freeVectors.sort()
        } else {
            freeScalars.append(register)
            freeScalars.sort()
        }
    }

    private mutating func allocateScalar() throws(ImplicitCompileError) -> Int {
        guard !freeScalars.isEmpty else {
            throw .unsupported("a solid that holds more than \(ImplicitProgram.maximumScalars) values at once")
        }
        let register = freeScalars.removeFirst()
        scalarsUsed = max(scalarsUsed, register + 1)
        return register
    }

    private mutating func allocateVector() throws(ImplicitCompileError) -> Int {
        guard !freeVectors.isEmpty else {
            throw .unsupported("a solid that holds more than \(ImplicitProgram.maximumVectors) points at once")
        }
        let register = freeVectors.removeFirst()
        vectorsUsed = max(vectorsUsed, register + 1)
        return register
    }

    var program: ImplicitProgram {
        ImplicitProgram(words: words, scalarsUsed: scalarsUsed, vectorsUsed: vectorsUsed)
    }

    // MARK: Solids

    // One branch per case, with no `default`, so a case added later is a compile error here as in `ImplicitCompiler`.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func solid(_ solid: ImplicitSolid, at p: ProgramOperand) throws(ImplicitCompileError) -> ProgramOperand {
        switch solid {
        case .sphere(let radius):
            let r = number(radius)
            return try emit(.sphere, [p, r])
        case .box(let half, let cornerRadius):
            let size = vector(half)
            let corner = number(cornerRadius)
            return try emit(.box, [p, size, corner])
        case .cylinder(let radius, let halfHeight):
            let r = number(radius)
            let h = number(halfHeight)
            return try emit(.cylinder, [p, r, h])
        case .moved(let child, let move):
            let origin = vector(move.origin)
            let x = vector(move.xAxis)
            let y = vector(move.yAxis)
            let z = vector(move.zAxis)
            let local = try emit(.move, [p, origin, x, y, z], vector: true)
            shared.insert(local)
            let result = try self.solid(child, at: local)
            shared.remove(local)
            release(local)
            return result
        case .union(let children, let blend):
            return try combine(children, blend, at: p, empty: 1e30, join: .smoothUnion)
        case .intersect(let children, let blend):
            return try combine(children, blend, at: p, empty: -1e30, join: .smoothIntersect)
        case .subtract(let children, let blend):
            return try combine(children, blend, at: p, empty: 1e30, join: .smoothSubtract)
        case .offset(let child, let distance):
            let inner = try self.solid(child, at: p)
            let amount = try grading(distance, at: p)
            return try emit(.difference, [inner, amount])
        case .shell(let child, let thickness, let side):
            let inner = try self.solid(child, at: p)
            let graded = try grading(thickness, at: p)
            let wall = try emit(.positive, [graded])
            let sideSlot = integer(side.rawValue)
            return try emit(.shell, [inner, wall, .raw(sideSlot)])
        case .baked(let blocks, _):
            let slot = register(blocks)
            return try emit(.baked, [.raw(slot.integers), .raw(slot.parameters), p])
        case .isosurface(let graded, let level, let maxSlope, let region):
            let value = try grading(graded, at: p)
            let levelOperand = number(level)
            let slope = number(maxSlope)
            let centre = vector(region.center)
            let half = vector(region.size * 0.5)
            return try emit(.isosurface, [value, levelOperand, slope, p, centre, half])
        case .tpms(let lattice):
            return try tpms(lattice, at: p)
        case .struts(let lattice):
            return try struts(lattice, at: p)
        case .voronoi(let lattice):
            return try voronoi(lattice, at: p)
        }
    }

    /// Union, intersect and subtract: the blend width first, then the children folded left to right as they come (the generator evaluates them all
    /// first and folds after; the fold and the buffers are the same, and this holds three values, not one per child).
    mutating func combine(_ children: [ImplicitSolid], _ blend: Grading, at p: ProgramOperand, empty: Float,
                          join: ImplicitOp) throws(ImplicitCompileError) -> ProgramOperand {
        let graded = try grading(blend, at: p)
        let width = try emit(.positive, [graded])
        guard let first = children.first else {
            release(width)
            return try emit(.constant, [.raw(Int(Int32(bitPattern: empty.bitPattern)))])
        }
        shared.insert(width)
        var result = try solid(first, at: p)
        for child in children.dropFirst() {
            let next = try solid(child, at: p)
            result = try emit(join, [result, next, width])
        }
        shared.remove(width)
        release(width)
        return result
    }
}
```

- [ ] **Step 5: Write the lattices, the mappings and the fields.**

`Sources/CreatorImplicit/Interpreter/ImplicitProgramBuilder+Lattices.swift`:
```swift
import CreatorGeometry

/// The lattices, their mappings and their cut (implicit spec §3.4, §3.5): `ImplicitCompiler.Generator`'s `tpms`, `struts`, `voronoi`, `mapped`,
/// `face` and `cut`, in the same order of numbers.
extension ImplicitProgramBuilder {
    mutating func tpms(_ lattice: TPMSLattice, at p: ProgramOperand) throws(ImplicitCompileError) -> ProgramOperand {
        let cell = try grading(lattice.cells.size, at: p)
        let wall = try grading(lattice.thickness, at: p)
        let stretch = vector(lattice.cells.stretch)
        let typeSlot = integer(lattice.type.rawValue)
        _ = integer(lattice.form.rawValue)
        let scale = number(lattice.type.wallScale)
        let mapping = try mapped(lattice.mapping, at: p)
        let body = try emit(.tpms, [mapping.coordinates, cell, stretch, wall, .raw(typeSlot), scale])
        return try cut(body, singular: mapping.singular, at: p, region: lattice.region)
    }

    mutating func struts(_ lattice: StrutLattice, at p: ProgramOperand) throws(ImplicitCompileError) -> ProgramOperand {
        let cell = try grading(lattice.cells.size, at: p)
        let radius = try grading(lattice.radius, at: p)
        let stretch = vector(lattice.cells.stretch)
        let offsetSlot = integer(pool.count)
        _ = integer(lattice.cell.struts.count)
        for strut in lattice.cell.struts {
            pool += [strut.start, strut.end].flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        }
        let blend = number(lattice.blend)
        let mapping = try mapped(lattice.mapping, at: p)
        let body = try emit(.struts, [.raw(offsetSlot), mapping.coordinates, cell, stretch, radius, blend])
        return try cut(body, singular: mapping.singular, at: p, region: lattice.region)
    }

    mutating func voronoi(_ lattice: VoronoiLattice, at p: ProgramOperand) throws(ImplicitCompileError) -> ProgramOperand {
        let seeds = lattice.seeds
        let wall = try grading(lattice.thickness, at: p)
        let slot = (integers: integers.count, parameters: parameters.count)
        integers += [Int32(pool.count), Int32(tables.count), Int32(tables.count + seeds.starts.count)]
        integers += seeds.counts.map { Int32($0) }
        pool += seeds.points.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        tables += seeds.starts
        tables += seeds.entries
        parameters += [Float(seeds.origin.x), Float(seeds.origin.y), Float(seeds.origin.z), Float(seeds.radius)]
        let formSlot = integer(lattice.form.rawValue)
        let scale = number(VoronoiLattice.strutScale)
        let mapping = try mapped(lattice.mapping, at: p)
        let body = try emit(.voronoi, [.raw(slot.integers), .raw(slot.parameters), mapping.coordinates, wall, .raw(formSlot), scale])
        return try cut(body, singular: mapping.singular, at: p, region: lattice.region)
    }

    /// The lattice coordinates of `p` and the distance to the mapping's singular set (`nil` for Straight, whose coordinates are `p`).
    mutating func mapped(_ mapping: LatticeMapping,
                         at p: ProgramOperand) throws(ImplicitCompileError) -> (coordinates: ProgramOperand, singular: ProgramOperand?) {
        switch mapping {
        case .straight:
            return (p, nil)
        case .cylindrical(let map):
            let origin = vector(map.origin)
            let reference = vector(map.reference)
            let side = vector(map.side)
            let axis = vector(map.axis)
            let radius = number(map.radius)
            let coordinates = try emit(.mapCylindrical, [p, origin, reference, side, axis, radius], vector: true)
            let singular = try emit(.singularCylindrical, [p, origin, reference, side])
            return (coordinates, singular)
        case .spherical(let map):
            let centre = vector(map.centre)
            let radius = number(map.radius)
            let coordinates = try emit(.mapSpherical, [p, centre, radius], vector: true)
            let singular = try emit(.singularSpherical, [p, centre])
            return (coordinates, singular)
        case .face(let map):
            return try face(map, at: p)
        }
    }

    mutating func face(_ map: FaceMap, at p: ProgramOperand) throws(ImplicitCompileError) -> (coordinates: ProgramOperand, singular: ProgramOperand?) {
        let chart = map.chart
        let slots = [chart.first, chart.firstSine ?? chart.first, chart.second, chart.secondSine ?? chart.second, chart.depth]
            .map { register($0) }
        let header = integers.count
        let flags = (chart.firstSine == nil ? 0 : 1) | (chart.secondSine == nil ? 0 : 2)
        integers += [Int32(flags)] + slots.flatMap { [Int32($0.integers), Int32($0.parameters)] }
        let first = number(map.firstRadius ?? 1)
        let second = number(map.secondRadius ?? 1)
        let coordinates = try emit(.mapFace, [.raw(header), p, first, second], vector: true)
        guard let blocks = chart.singular else { return (coordinates, nil) }
        let slot = register(blocks)
        let singular = try emit(.bakedChannel, [.raw(slot.integers), .raw(slot.parameters), p])
        return (coordinates, singular)
    }

    /// A lattice's body left solid at the singular set and cut to the region at `p`.
    mutating func cut(_ body: ProgramOperand, singular: ProgramOperand?, at p: ProgramOperand,
                      region: BoundingBox) throws(ImplicitCompileError) -> ProgramOperand {
        var joined = body
        if let singular {
            let exclusion = number(LatticeMapping.exclusion)
            let fade = number(LatticeMapping.fadeWidth)
            joined = try emit(.mappingJoin, [body, singular, exclusion, fade])
        }
        let centre = vector(region.center)
        let half = vector(region.size * 0.5)
        return try emit(.region, [joined, p, centre, half])
    }
}
```

`Sources/CreatorImplicit/Interpreter/ImplicitProgramBuilder+Fields.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Gradings and fields: `ImplicitCompiler.Generator.grading` and `.field`, in the same order of numbers.
extension ImplicitProgramBuilder {
    mutating func grading(_ grading: Grading, at p: ProgramOperand) throws(ImplicitCompileError) -> ProgramOperand {
        if let constant = grading.constantValue { return number(constant) }
        return try field(grading.field, at: p, in: grading)
    }

    // One branch per field case, with no `default`.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func field(_ field: Field, at p: ProgramOperand, in grading: Grading) throws(ImplicitCompileError) -> ProgramOperand {
        switch field {
        case .constant(let value):
            return number(value)
        case .distance(let source, let signed):
            switch source {
            case .point(let target):
                let point = vector(target)
                return try emit(.pointDistance, [p, point])
            case .profile:
                throw .unsupported("a distance to a profile")
            case .kernel(let target):
                guard let blocks = grading.blocks(for: target.identity, signed: signed) else {
                    throw .unsupported("a distance to a solid that was not baked")
                }
                let slot = register(blocks)
                return try emit(.baked, [.raw(slot.integers), .raw(slot.parameters), p])
            }
        case .linearGradient(let plane, let length):
            let origin = vector(plane.origin)
            let normal = vector(plane.normal.normalized ?? .zero)
            let size = number(length)
            return try emit(.linear, [p, origin, normal, size])
        case .radialGradient(let center, let radius):
            let centre = vector(center)
            let size = number(radius)
            return try emit(.radial, [p, centre, size])
        case .noise(let seed, let scale, let octaves):
            let seeds = tables.count
            for octave in 0..<octaves {
                let start = SeededRandom(seed: seed, stream: octave, purpose: .fieldNoise).streamStart
                tables += [Int32(truncatingIfNeeded: start & 0xFFFF_FFFF), Int32(truncatingIfNeeded: start >> 32)]
            }
            let size = number(scale)
            let octavesSlot = integer(octaves)
            _ = integer(seeds)
            return try emit(.noise, [p, size, .raw(octavesSlot)])
        case .image(let image, let plane, let width, let height, let edges):
            let slot = integers.count
            integers += [Int32(images.count), Int32(image.width), Int32(image.height), Int32(edges.rawValue)]
            images += image.pixels.map(Float.init)
            let origin = vector(plane.origin)
            let across = vector(plane.xAxis.normalized ?? .zero)
            let up = vector(plane.yAxis.normalized ?? .zero)
            let w = number(width)
            let h = number(height)
            let offset = try emit(.vectorDifference, [p, origin], vector: true)
            return try emit(.image, [offset, across, up, w, h, .raw(slot)])
        case .implicit(let reference):
            guard let solid = reference.solid else { throw .unsupported("an implicit that is not an ImplicitSolid") }
            return try self.solid(solid, at: p)
        case .add(let a, let b):
            let x = try self.field(a, at: p, in: grading)
            let y = try self.field(b, at: p, in: grading)
            return try emit(.add, [x, y])
        case .multiply(let a, let b):
            let x = try self.field(a, at: p, in: grading)
            let y = try self.field(b, at: p, in: grading)
            return try emit(.multiply, [x, y])
        case .minimum(let a, let b):
            let x = try self.field(a, at: p, in: grading)
            let y = try self.field(b, at: p, in: grading)
            return try emit(.minimum, [x, y])
        case .maximum(let a, let b):
            let x = try self.field(a, at: p, in: grading)
            let y = try self.field(b, at: p, in: grading)
            return try emit(.maximum, [x, y])
        case .remap(let inner, let fromLow, let fromHigh, let toLow, let toHigh, let clamped):
            let value = try self.field(inner, at: p, in: grading)
            let numbers = [fromLow, fromHigh, toLow, toHigh].map { number($0) }
            let clampedSlot = integer(clamped ? 1 : 0)
            return try emit(.remap, [value] + numbers + [.raw(clampedSlot)])
        case .clamp(let inner, let low, let high):
            let value = try self.field(inner, at: p, in: grading)
            let lowest = number(low)
            let highest = number(high)
            return try emit(.clamp, [value, lowest, highest])
        case .smoothMinimum(let a, let b, let width):
            let x = try self.field(a, at: p, in: grading)
            let y = try self.field(b, at: p, in: grading)
            let w = number(width)
            return try emit(.smoothUnion, [x, y, w])
        }
    }
}
```
If a `case` above does not match `Field`'s current cases exactly (a 7c follow-up added one), copy `ImplicitCompiler.Generator.field`'s branch for it and add the op it needs (a new `ImplicitOp` case, the HLSL `OP_` define and interpreter `case` in task 2): the compiler must mirror the generator.

- [ ] **Step 6: Write the compiler and the `CompiledImplicit` property.**

`Sources/CreatorImplicit/Interpreter/ImplicitProgramCompiler.swift`:
```swift
/// Compiles a solid for the HLSL interpreter (plan xp-c; implicit spec erratum D21). The result is a `CompiledImplicit` with no Metal source, the
/// same five buffers `ImplicitCompiler` makes and an `ImplicitProgram`; `InterpretedImplicitEngine` runs it.
public enum ImplicitProgramCompiler {
    public static func compile(_ solid: ImplicitSolid) throws(ImplicitCompileError) -> CompiledImplicit {
        var builder = ImplicitProgramBuilder()
        let result = try builder.solid(solid, at: .point)
        builder.finish(result)
        return CompiledImplicit(source: "", parameters: builder.parameters, integers: builder.integers, tables: builder.tables,
                                pool: builder.pool, images: builder.images, program: builder.program)
    }
}
```

In `Sources/CreatorImplicit/Metal/CompiledImplicit.swift` add after `public let images: [Float]`:
```swift
    /// The program the HLSL interpreter runs (`ImplicitProgramCompiler`), or `nil` for a solid compiled to Metal source.
    public let program: ImplicitProgram?
```
and change the initializer to:
```swift
    init(source: String, parameters: [Float], integers: [Int32], tables: [Int32], pool: [Float], images: [Float],
         program: ImplicitProgram? = nil) {
        self.source = source
        self.parameters = parameters
        self.integers = integers
        self.tables = tables
        self.pool = pool
        self.images = images
        self.program = program
        shape = ShapeKey(source)
    }
```
and its doc comment's first line to "An implicit solid compiled for a GPU (implicit spec §4.1): Metal source, or an `ImplicitProgram` for the HLSL interpreter (plan xp-c), and the buffers either reads."

- [ ] **Step 7: Run the tests.**

Run: `swift test --filter CreatorImplicitTests.ImplicitProgramCompilerTests 2>&1 | tail -5`
Expected: PASS. If `everyFixtureReadsTheSameBuffersAsItsMetalSource` fails for one fixture, the builder's order of `number`/`integer`/`vector` calls differs from the generator's in that case: compare the two branches line by line (Swift evaluates a tuple and an array literal left to right, so the generator's `let (a, b) = (number(x), integer(y))` is `number` first).

Then: `swift test --filter CreatorImplicitTests 2>&1 | grep "Test run with"` — baseline + the new tests, no issue.

- [ ] **Step 8: Lint and commit.**

```bash
swiftlint lint --strict
git add Sources/CreatorImplicit/Interpreter Sources/CreatorImplicit/Metal/CompiledImplicit.swift Tests/CreatorImplicitTests/ImplicitProgramCompilerTests.swift
git commit -m "feat(implicit): compile solids to ImplicitProgram, the HLSL interpreter's bytecode (xp-c task 1)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

---

### Task 2: The HLSL kernels' evaluation half, the build path for a second shader set, and the contract tests

**Files:**
- Create: `Shaders/implicit/contract.hlsli`, `accurate_math.hlsli`, `wide_integer.hlsli`, `library.hlsli`, `lattices.hlsli`, `interpreter.hlsli`, `implicit_evaluate.comp.hlsl`
- Create: `Sources/CreatorImplicit/Compute/ImplicitKernel.swift`, `Sources/CreatorImplicit/Compute/KernelParameters.swift`
- Modify: `scripts/build-shaders.sh`, `scripts/build-shaders.ps1` (every set in `Shaders/`), `scripts/linux-test.sh` (a `shaders` verb), `.gitignore`
- Test: `Tests/CreatorImplicitTests/ImplicitShaderContractTests.swift`

**Interfaces:**
- Consumes: `ImplicitOp`, `ImplicitProgram` (task 1); `MarchingCubesBuffers`, `ImplicitMeshShaderLibrary.Counter`, `ImplicitMeshShaderLibrary.probeLimit`, `BrickPlan.brickSize` (7c-1g).
- Produces:
  - `public enum ImplicitKernel: String, CaseIterable, Sendable` with cases `evaluate = "implicit_evaluate"`, `clear = "mesh_clear"`, `sample = "mesh_sample"`, `classify = "mesh_classify"`, `number = "mesh_number"`, `place = "mesh_place"`, `emit = "mesh_emit"`, and `public var bindings: (readOnly: Int, readWrite: Int)` = evaluate (4, 1), clear (0, 1), sample (5, 1), classify (3, 2), number (1, 2), place (6, 2), emit (5, 3); `public static let threadsPerGroup = 64`.
  - `public struct KernelParameters: Sendable, Equatable` (16 four-byte fields, below) and `var bytes: [UInt8]`.
  - The HLSL `sdf(float3 p)` (in `interpreter.hlsli`), included by every kernel that evaluates; `Shaders/implicit/compiled/implicit_evaluate.comp.{spv,dxil,msl,json}` after `scripts/build-shaders.sh`.
  - `scripts/linux-test.sh shaders`: compiles every set into the worktree (the Mac's `MSLComputeBackend` reads the MSL from there, task 3).

The five meshing kernels and `mesh_*.hlsli` are task 5's; this task's contract test already lists all seven kernels' bindings and skips a kernel whose source does not exist yet (`Shaders/implicit/<name>.comp.hlsl`), so task 5 needs no change to it.

- [ ] **Step 1: Write the failing contract tests.**

`Tests/CreatorImplicitTests/ImplicitShaderContractTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorImplicit

/// The HLSL of `Shaders/implicit` against the Swift that drives it (plan xp-c): the op codes, the limits, the table offsets, the counters and the
/// uniform block are the same numbers on both sides; each kernel declares the storage buffers `ImplicitKernel.bindings` says, in order; the HLSL
/// keeps the precision and portability rules. Reads the sources, so it runs everywhere. On Linux and Windows (and on a Mac where
/// `scripts/linux-test.sh shaders` was run) it also checks that the build compiled every kernel and is current.
struct ImplicitShaderContractTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Shaders/implicit")
    static let compiled = directory.appending(path: "compiled")

    static func text(_ name: String) throws -> String {
        try String(contentsOf: directory.appending(path: name), encoding: .utf8)
    }

    static var sources: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".hlsl") || $0.hasSuffix(".hlsli") }.sorted()
    }

    /// `#define NAME VALUE` lines of the contract, with a trailing `u` dropped.
    static func defines() throws -> [String: Int] {
        var table: [String: Int] = [:]
        for line in try text("contract.hlsli").split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count >= 3, words[0] == "#define" else { continue }
            var value = String(words[2])
            if value.hasSuffix("u") { value.removeLast() }
            let number = value.hasPrefix("0x") ? Int(value.dropFirst(2), radix: 16) : Int(value)
            if let number { table[String(words[1])] = number }
        }
        return table
    }

    /// `smoothUnion` → `OP_SMOOTH_UNION`.
    static func shaderName(_ op: ImplicitOp) -> String {
        var name = "OP_"
        for character in String(describing: op) {
            if character.isUppercase { name += "_" }
            name += character.uppercased()
        }
        return name
    }

    @Test func theSourcesAreFound() {
        #expect(Self.sources.contains("contract.hlsli") && Self.sources.contains("implicit_evaluate.comp.hlsl"), "\(Self.directory.path)")
    }

    @Test func everyOpCodeIsTheSwiftOne() throws {
        let defines = try Self.defines()
        for op in ImplicitOp.allCases {
            #expect(defines[Self.shaderName(op)] == Int(op.rawValue), "\(Self.shaderName(op))")
        }
        #expect(defines.keys.filter { $0.hasPrefix("OP_") }.count == ImplicitOp.allCases.count, "no op the Swift side lacks")
    }

    @Test func theLimitsOffsetsAndCountersAreTheSwiftOnes() throws {
        let defines = try Self.defines()
        let expected: [String: Int] = [
            "MAX_SCALARS": ImplicitProgram.maximumScalars, "MAX_VECTORS": ImplicitProgram.maximumVectors,
            "INSTRUCTION_WORDS": ImplicitProgram.wordsPerInstruction, "THREADS": ImplicitKernel.threadsPerGroup,
            "CUBE_STARTS": MarchingCubesBuffers.startsOffset, "CUBE_LOWER": MarchingCubesBuffers.lowerCornersOffset,
            "CUBE_UPPER": MarchingCubesBuffers.upperCornersOffset, "CUBE_EDGES": MarchingCubesBuffers.edgesOffset,
            "BRICK": BrickPlan.brickSize, "SIDE": BrickPlan.brickSize + 1,
            "CUBES": BrickPlan.brickSize * BrickPlan.brickSize * BrickPlan.brickSize,
            "POINTS": (BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1),
            "PROBE_LIMIT": ImplicitMeshShaderLibrary.probeLimit,
            "COUNTER_VERTICES": ImplicitMeshShaderLibrary.Counter.vertices,
            "COUNTER_TRIANGLE_TOTAL": ImplicitMeshShaderLibrary.Counter.triangleTotal,
            "COUNTER_TRIANGLE_CURSOR": ImplicitMeshShaderLibrary.Counter.triangleCursor,
            "COUNTER_OVERFLOW": ImplicitMeshShaderLibrary.Counter.overflow,
            "EMPTY_KEY": Int(BrickLattice.emptyKey),
        ]
        for (name, value) in expected { #expect(defines[name] == value, "\(name): \(String(describing: defines[name])) against \(value)") }
    }

    /// `cbuffer Params` has sixteen four-byte members, which is `KernelParameters`.
    @Test func theUniformBlockIsKernelParameters() throws {
        let contract = try Self.text("contract.hlsli")
        let start = try #require(contract.range(of: "cbuffer Params : register(b0, space2) {"))
        let end = try #require(contract[start.upperBound...].range(of: "};"))
        let members = contract[start.upperBound..<end.lowerBound].split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        #expect(members.count == 16 && members.allSatisfy { $0.hasPrefix("uint ") || $0.hasPrefix("float ") })
        #expect(MemoryLayout<KernelParameters>.stride == 64 && KernelParameters().bytes.count == 64)
    }

    /// Each kernel's `register(tN, space0)` and `register(uN, space1)` run from 0 without a gap, as many as `bindings` says.
    @Test(arguments: ImplicitKernel.allCases.map(\.rawValue))
    func eachKernelDeclaresItsBuffersInOrder(_ name: String) throws {
        let kernel = try #require(ImplicitKernel(rawValue: name))
        guard let source = try? Self.text("\(name).comp.hlsl") else { return }   // task 5 adds the meshing kernels
        func slots(_ letter: String, _ space: Int) -> [Int] {
            source.split(whereSeparator: \.isNewline).compactMap { line in
                guard let range = line.range(of: #"register\("# + letter + #"(\d+), space\#(space)\)"#, options: .regularExpression) else { return nil }
                return Int(line[range].dropFirst(9 + letter.count).prefix { $0.isNumber })
            }
        }
        #expect(slots("t", 0) == Array(0..<kernel.bindings.readOnly), "\(name): read-only buffers")
        #expect(slots("u", 1) == Array(0..<kernel.bindings.readWrite), "\(name): read-write buffers")
        #expect(source.contains("[numthreads(THREADS, 1, 1)]"), "\(name): 64 threads a group")
    }

    /// No reduced precision, no 64-bit integers, no buffer size query, no driver trigonometry (spec erratum D21, plan X-C6).
    @Test func theHLSLKeepsThePrecisionAndPortabilityRules() throws {
        let forbidden = [#"\bhalf\d?\b"#, #"\bmin16float"#, #"\bdouble\b"#, #"\bu?int64_t\b"#, #"GetDimensions"#,
                         #"(?<![A-Za-z])(sin|cos|tan|atan|atan2|sincos)\s*\("#]
        for name in Self.sources {
            let code = try Self.text(name).split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            for line in code {
                for pattern in forbidden {
                    #expect(line.range(of: pattern, options: .regularExpression) == nil, "\(name): \(line)")
                }
            }
        }
    }

    /// Where the kernels were compiled (always on Linux and Windows; on a Mac after `scripts/linux-test.sh shaders`): every stage's four files are
    /// there, `SOURCE.sha256` and `INCLUDES.sha256` match the sources now, and each reflection has the buffers `bindings` says and one uniform block.
    @Test func theBuildCompiledEveryKernelAndIsCurrent() throws {
        let remedy = "Run scripts/build-shaders.sh (scripts/build-shaders.ps1 on Windows; scripts/linux-test.sh shaders from a Mac)."
        #if canImport(MetalUISDLGPU)
        let required = true
        #else
        let required = false
        #endif
        guard required || FileManager.default.fileExists(atPath: Self.compiled.appending(path: "SOURCE.sha256").path) else { return }
        func digest(_ url: URL) throws -> String { SHA256.hash(try Data(contentsOf: url)).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined() }
        func table(_ file: String) throws -> [String: String] {
            var result: [String: String] = [:]
            for line in try String(contentsOf: Self.compiled.appending(path: file), encoding: .utf8).split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count == 2 { result[String(parts[1])] = String(parts[0]) }
            }
            return result
        }
        let stages = Self.sources.filter { $0.hasSuffix(".comp.hlsl") }
        let marker = try table("SOURCE.sha256")
        #expect(Set(marker.keys) == Set(stages), remedy)
        for stage in stages { #expect(marker[stage] == (try digest(Self.directory.appending(path: stage))), "\(stage) changed. \(remedy)") }
        let includes = try table("INCLUDES.sha256")
        let headers = Self.sources.filter { $0.hasSuffix(".hlsli") }
        #expect(Set(includes.keys) == Set(headers), remedy)
        for header in headers { #expect(includes[header] == (try digest(Self.directory.appending(path: header))), "\(header) changed. \(remedy)") }
        for stage in stages {
            let stem = String(stage.dropLast(".hlsl".count))
            for blob in ["spv", "dxil", "msl", "json"] {
                let size = (try? Data(contentsOf: Self.compiled.appending(path: "\(stem).\(blob)")).count) ?? 0
                #expect(size > 0, "\(stem).\(blob). \(remedy)")
            }
            let kernel = try #require(ImplicitKernel(rawValue: String(stem.dropLast(".comp".count))), "\(stem) is no ImplicitKernel")
            let reflection = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.compiled.appending(path: "\(stem).json"))) as? [String: Int]
            #expect(reflection?["readonly_storage_buffers"] == kernel.bindings.readOnly, "\(stem): a declared read-only buffer was dropped")
            #expect(reflection?["readwrite_storage_buffers"] == kernel.bindings.readWrite, "\(stem): a declared read-write buffer was dropped")
            #expect(reflection?["uniform_buffers"] == 1 && reflection?["threadcount_x"] == ImplicitKernel.threadsPerGroup, "\(stem)")
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail.**

Run: `swift test --filter CreatorImplicitTests.ImplicitShaderContractTests 2>&1 | tail -5`
Expected: build failure ("cannot find 'ImplicitKernel' in scope").

- [ ] **Step 3: Write `ImplicitKernel` and `KernelParameters`.**

`Sources/CreatorImplicit/Compute/ImplicitKernel.swift`:
```swift
/// The interpreted engine's compute kernels (plan xp-c): `Shaders/implicit/<rawValue>.comp.hlsl`, compiled at build time. A `ComputeDispatch` lists a
/// kernel's storage buffers in the order of its `register(tN, space0)` (read-only) and `register(uN, space1)` (read-write) declarations, which
/// `ImplicitShaderContractTests` pins to `bindings`.
public enum ImplicitKernel: String, CaseIterable, Sendable {
    /// points, program, floats, ints → values.
    case evaluate = "implicit_evaluate"
    /// → keys: the edge table emptied over `firstSlot ..< firstSlot + count`.
    case clear = "mesh_clear"
    /// bricks, axes, program, floats, ints → samples.
    case sample = "mesh_sample"
    /// bricks, samples, cube table → keys, counters.
    case classify = "mesh_classify"
    /// keys → slot vertices, counters.
    case number = "mesh_number"
    /// axes, program, floats, ints, keys, slot vertices → positions, normals.
    case place = "mesh_place"
    /// bricks, samples, cube table, keys, slot vertices → counters, indices, tags.
    case emit = "mesh_emit"

    /// The threads of a group (`THREADS`, `[numthreads(THREADS, 1, 1)]`).
    public static let threadsPerGroup = 64

    /// How many read-only and read-write storage buffers the kernel declares.
    public var bindings: (readOnly: Int, readWrite: Int) {
        switch self {
        case .evaluate: (4, 1)
        case .clear: (0, 1)
        case .sample: (5, 1)
        case .classify: (3, 2)
        case .number: (1, 2)
        case .place: (6, 2)
        case .emit: (5, 3)
        }
    }
}
```

`Sources/CreatorImplicit/Compute/KernelParameters.swift`:
```swift
/// The one uniform block every implicit kernel reads (`cbuffer Params : register(b0, space2)` in `Shaders/implicit/contract.hlsli`): sixteen
/// four-byte words, 64 bytes, member for member. A kernel reads the members it needs; the rest are zero.
public struct KernelParameters: Sendable, Equatable {
    /// Points to evaluate (evaluate), or table slots in this range (clear, number, place).
    public var count: UInt32 = 0
    /// The program's steps.
    public var instructions: UInt32 = 0
    /// Where the pool and the pictures start in the floats buffer (the parameters start at 0).
    public var poolBase: UInt32 = 0
    public var imagesBase: UInt32 = 0
    /// Where the tables start in the ints buffer (the integer parameters start at 0).
    public var tablesBase: UInt32 = 0
    /// The batch's first brick and how many it has (sample, classify, emit).
    public var firstBrick: UInt32 = 0
    public var brickCount: UInt32 = 0
    /// The lattice window's points on each axis.
    public var nx: UInt32 = 0
    public var ny: UInt32 = 0
    public var nz: UInt32 = 0
    /// The edge table's slots minus one (a power of two minus one).
    public var mask: UInt32 = 0
    /// 1 when vertices take the Newton step.
    public var snap: UInt32 = 0
    /// The voxel size in millimetres.
    public var resolution: Float = 0
    /// The range's first table slot (clear, number, place).
    public var firstSlot: UInt32 = 0
    public var padding0: UInt32 = 0
    public var padding1: UInt32 = 0

    public init() {}

    /// The block as the GPU reads it, in declaration order.
    var bytes: [UInt8] {
        let words: [UInt32] = [count, instructions, poolBase, imagesBase, tablesBase, firstBrick, brickCount, nx, ny, nz, mask, snap,
                               resolution.bitPattern, firstSlot, padding0, padding1]
        return words.withUnsafeBytes { Array($0) }
    }
}
```
(`bytes` builds from an explicit word list, so it does not depend on Swift's struct layout.)

- [ ] **Step 4: Write the contract header and the two exact-arithmetic headers.**

`Shaders/implicit/contract.hlsli`:
```hlsl
// The numbers the Swift side shares with the implicit kernels (plan xp-c). ImplicitShaderContractTests pins every one to its Swift twin:
// ImplicitOp, ImplicitProgram, ImplicitKernel, MarchingCubesBuffers, BrickPlan, ImplicitMeshShaderLibrary.Counter and .probeLimit,
// BrickLattice.emptyKey, KernelParameters. Change both sides together.
#ifndef IMPLICIT_CONTRACT
#define IMPLICIT_CONTRACT

#define MAX_SCALARS 32
#define MAX_VECTORS 8
#define INSTRUCTION_WORDS 8u
#define THREADS 64

#define OP_CONSTANT 1
#define OP_SPHERE 2
#define OP_BOX 3
#define OP_CYLINDER 4
#define OP_MOVE 5
#define OP_POSITIVE 6
#define OP_SMOOTH_UNION 7
#define OP_SMOOTH_INTERSECT 8
#define OP_SMOOTH_SUBTRACT 9
#define OP_DIFFERENCE 10
#define OP_SHELL 11
#define OP_BAKED 12
#define OP_ISOSURFACE 13
#define OP_TPMS 14
#define OP_STRUTS 15
#define OP_VORONOI 16
#define OP_MAP_CYLINDRICAL 17
#define OP_SINGULAR_CYLINDRICAL 18
#define OP_MAP_SPHERICAL 19
#define OP_SINGULAR_SPHERICAL 20
#define OP_MAP_FACE 21
#define OP_BAKED_CHANNEL 22
#define OP_MAPPING_JOIN 23
#define OP_REGION 24
#define OP_POINT_DISTANCE 25
#define OP_LINEAR 26
#define OP_RADIAL 27
#define OP_NOISE 28
#define OP_VECTOR_DIFFERENCE 29
#define OP_IMAGE 30
#define OP_ADD 31
#define OP_MULTIPLY 32
#define OP_MINIMUM 33
#define OP_MAXIMUM 34
#define OP_REMAP 35
#define OP_CLAMP 36
#define OP_RESULT 37

#define EMPTY_KEY 0xFFFFFFFFu
#define CUBE_STARTS 0u
#define CUBE_LOWER 257u
#define CUBE_UPPER 269u
#define CUBE_EDGES 281u
#define BRICK 8u
#define SIDE 9u
#define CUBES 512u
#define POINTS 729u
#define PROBE_LIMIT 128u
#define COUNTER_VERTICES 0u
#define COUNTER_TRIANGLE_TOTAL 1u
#define COUNTER_TRIANGLE_CURSOR 2u
#define COUNTER_OVERFLOW 3u

#define INFINITY_F asfloat(0x7F800000u)
#define PI_F 3.14159265358979323846f
#define HALF_PI_F 1.57079632679489661923f
#define QUARTER_PI_F 0.78539816339744830962f

// KernelParameters, word for word (64 bytes).
cbuffer Params : register(b0, space2) {
    uint gCount;
    uint gInstructions;
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
};

#endif
```

`Shaders/implicit/accurate_math.hlsli`:
```hlsl
// Sine, cosine and arctangent to about one ulp on every driver (plan xp-c, user decision X-C6). Vulkan promises only an absolute 2^-11 for sin on
// [-pi, pi] and Direct3D says less, while a TPMS wall is scaled by cell / 2pi: 2^-11 would be about 4e-4 mm at a 5 mm cell, against the 1e-4 mm the
// GPU is held to. The reduction is Cody-Waite in three parts of pi/2 (the first two exact in a float product for |q| < 2^15); the polynomials are
// Cephes' sinf, cosf and atanf (Stephen L. Moshier, public domain). The arguments the lattices give are under 13 (tpmsRaw's 2q), far inside that.
#ifndef IMPLICIT_ACCURATE_MATH
#define IMPLICIT_ACCURATE_MATH

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

#endif
```

`Shaders/implicit/wide_integer.hlsli`:
```hlsl
// Unsigned 64-bit arithmetic in two 32-bit words (plan xp-c, user decision X-C6): the noise's SplitMix64 hash needs it, and uint64_t needs a device
// feature (shaderInt64) SDL_GPU neither enables nor reports. Exact, so a draw is bit for bit FieldNoise's on the CPU.
#ifndef IMPLICIT_WIDE_INTEGER
#define IMPLICIT_WIDE_INTEGER

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

#endif
```

- [ ] **Step 5: Port the shader library and the lattices.**

These are line-for-line ports of `ImplicitShaderLibrary.core` and `ImplicitShaderLibrary.lattices` (Swift files in `Sources/CreatorImplicit/Metal/`, MSL as text). The translation: `inline` dropped; `const thread Env& e` parameter dropped, its fields read through the accessors below; `mix` → `lerp`; `precise::sin`/`cos`/`atan2` → `accSin`/`accCos`/`accAtan2` (vector forms `accSin3`/`accCos3`); `as_type<float>(as_type<uint>(x) - 1u)` → `asfloat(asuint(x) - 1u)`; `INFINITY` → `INFINITY_F`; `thread int&` → `out int`; `ulong` → `U64`; `constant` arrays → `static const`; float literals carry an `f`.

`Shaders/implicit/library.hlsli`:
```hlsl
// The functions every compiled implicit shares (implicit spec §4.1): a port of ImplicitShaderLibrary.core (the MSL of the Metal engine), each a
// line-for-line port of its CPU twin (CPUEvaluation, DistanceBlocks, FieldNoise, GreyImage). The kernel declares `floats` (the parameters, then the
// pool, then the pictures) and `ints` (the integer parameters, then the tables) before it includes this; the bases are in Params.
#ifndef IMPLICIT_LIBRARY
#define IMPLICIT_LIBRARY

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

#endif
```

`Shaders/implicit/lattices.hlsli`:
```hlsl
// The lattices and their mappings (implicit spec §3.4, §3.5): a port of ImplicitShaderLibrary.lattices, trigonometry through accurate_math.hlsli.
#ifndef IMPLICIT_LATTICES
#define IMPLICIT_LATTICES

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

#endif
```
Before writing these two files, open `ImplicitShaderLibrary.swift` and `ImplicitShaderLibrary+Lattices.swift` on the branch and compare function by function: if a 7c follow-up changed one since this plan was written, port the current text.

- [ ] **Step 6: Write the interpreter and the evaluation kernel.**

`Shaders/implicit/interpreter.hlsli`:
```hlsl
// The interpreter of ImplicitProgram (plan xp-c, implicit spec erratum D21): the solid's signed distance at p. The kernel declares `program` (the
// words), `floats` and `ints` before it includes this. One case per ImplicitOp; each reads all its operands before the result is written, because
// the compiler reuses an operand's register for the result. An operand x >= 0 is a register, x < 0 the float parameter at -x - 1; the clamps keep a
// malformed program inside the arrays and buffers (it computes nonsense, it never reads out of bounds).
#ifndef IMPLICIT_INTERPRETER
#define IMPLICIT_INTERPRETER

#define S(x) ((x) >= 0 ? r[min((x), MAX_SCALARS - 1)] : P(max(-(x) - 1, 0)))
#define V(x) ((x) >= 0 ? v[min((x), MAX_VECTORS - 1)] : PV(max(-(x) - 1, 0)))

float sdf(float3 p) {
    float r[MAX_SCALARS];
    float3 v[MAX_VECTORS];
    for (int clearing = 0; clearing < MAX_VECTORS; clearing++) { v[clearing] = float3(0.0f, 0.0f, 0.0f); }
    for (int zeroing = 0; zeroing < MAX_SCALARS; zeroing++) { r[zeroing] = 0.0f; }
    v[0] = p;
    for (uint pc = 0u; pc < gInstructions; ++pc) {
        uint at = pc * INSTRUCTION_WORDS;
        int op = program[at], d = program[at + 1u];
        int o0 = program[at + 2u], o1 = program[at + 3u], o2 = program[at + 4u];
        int o3 = program[at + 5u], o4 = program[at + 6u], o5 = program[at + 7u];
        float x = 0.0f;
        float3 w = float3(0.0f, 0.0f, 0.0f);
        bool isVector = false;
        switch (op) {
        case OP_CONSTANT: x = asfloat(o0); break;
        case OP_SPHERE: x = length(V(o0)) - S(o1); break;
        case OP_BOX: x = sdBox(V(o0), V(o1), S(o2)); break;
        case OP_CYLINDER: x = sdCylinder(V(o0), S(o1), S(o2)); break;
        case OP_MOVE: {
            float3 q = V(o0) - V(o1);
            w = float3(dot(q, V(o2)), dot(q, V(o3)), dot(q, V(o4)));
            isVector = true;
            break;
        }
        case OP_POSITIVE: x = max(0.0f, S(o0)); break;
        case OP_SMOOTH_UNION: x = smoothMin(S(o0), S(o1), S(o2)); break;
        case OP_SMOOTH_INTERSECT: x = -smoothMin(-S(o0), -S(o1), S(o2)); break;
        case OP_SMOOTH_SUBTRACT: x = -smoothMin(-S(o0), S(o1), S(o2)); break;
        case OP_DIFFERENCE: x = S(o0) - S(o1); break;
        case OP_SHELL: {
            float inner = S(o0), wall = S(o1);
            int side = I(o2);
            float centre = side == 0 ? -wall / 2.0f : (side == 1 ? wall / 2.0f : 0.0f);
            x = abs(inner - centre) - wall / 2.0f;
            break;
        }
        case OP_BAKED: x = bakedValue(o0, o1, V(o2)); break;
        case OP_ISOSURFACE: x = max((S(o0) - S(o1)) / S(o2), regionDistance(V(o3), V(o4), V(o5))); break;
        case OP_TPMS: x = tpmsBody(V(o0), S(o1), V(o2), S(o3), I(o4), I(o4 + 1), S(o5)); break;
        case OP_STRUTS: x = strutBody(I(o0), I(o0 + 1), V(o1), S(o2), V(o3), S(o4), S(o5)); break;
        case OP_VORONOI: x = voronoiBody(o0, o1, V(o2), S(o3), I(o4), S(o5)); break;
        case OP_MAP_CYLINDRICAL: w = mapCylindrical(V(o0), V(o1), V(o2), V(o3), V(o4), S(o5)); isVector = true; break;
        case OP_SINGULAR_CYLINDRICAL: x = singularCylindrical(V(o0), V(o1), V(o2), V(o3)); break;
        case OP_MAP_SPHERICAL: w = mapSpherical(V(o0), V(o1), S(o2)); isVector = true; break;
        case OP_SINGULAR_SPHERICAL: x = singularSpherical(V(o0), V(o1)); break;
        case OP_MAP_FACE: w = mapFace(o0, V(o1), S(o2), S(o3)); isVector = true; break;
        case OP_BAKED_CHANNEL: x = bakedChannel(o0, o1, V(o2)); break;
        case OP_MAPPING_JOIN: x = mappingJoin(S(o0), S(o1), S(o2), S(o3)); break;
        case OP_REGION: x = max(S(o0), regionDistance(V(o1), V(o2), V(o3))); break;
        case OP_POINT_DISTANCE: x = length(V(o0) - V(o1)); break;
        case OP_LINEAR: x = dot(V(o0) - V(o1), V(o2)) / S(o3); break;
        case OP_RADIAL: x = length(V(o0) - V(o1)) / S(o2); break;
        case OP_NOISE: x = fieldNoise(V(o0), S(o1), I(o2), I(o2 + 1)); break;
        case OP_VECTOR_DIFFERENCE: w = V(o0) - V(o1); isVector = true; break;
        case OP_IMAGE: {
            float3 offset = V(o0);
            x = imageValue(o5, dot(offset, V(o1)) / S(o3) + 0.5f, 0.5f - dot(offset, V(o2)) / S(o4));
            break;
        }
        case OP_ADD: x = S(o0) + S(o1); break;
        case OP_MULTIPLY: x = S(o0) * S(o1); break;
        case OP_MINIMUM: x = min(S(o0), S(o1)); break;
        case OP_MAXIMUM: x = max(S(o0), S(o1)); break;
        case OP_REMAP: x = remapField(S(o0), S(o1), S(o2), S(o3), S(o4), I(o5)); break;
        case OP_CLAMP: x = min(max(S(o0), S(o1)), S(o2)); break;
        case OP_RESULT: return S(o0);
        default: return 0.0f;
        }
        if (isVector) {
            v[clamp(d, 0, MAX_VECTORS - 1)] = w;
        } else {
            r[clamp(d, 0, MAX_SCALARS - 1)] = x;
        }
    }
    return 0.0f;
}

#endif
```

`Shaders/implicit/implicit_evaluate.comp.hlsl`:
```hlsl
// Evaluates a compiled solid at a batch of points (implicit spec §4.1; the Metal engine's evaluateImplicit): points as three floats each.
#include "contract.hlsli"

StructuredBuffer<float> points : register(t0, space0);
StructuredBuffer<int> program : register(t1, space0);
StructuredBuffer<float> floats : register(t2, space0);
StructuredBuffer<int> ints : register(t3, space0);
RWStructuredBuffer<float> values : register(u0, space1);

#include "accurate_math.hlsli"
#include "wide_integer.hlsli"
#include "library.hlsli"
#include "lattices.hlsli"
#include "interpreter.hlsli"

[numthreads(THREADS, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint index = id.x;
    if (index >= gCount) { return; }
    values[index] = sdf(float3(points[3u * index], points[3u * index + 1u], points[3u * index + 2u]));
}
```

- [ ] **Step 7: Compile every shader set, not only the viewport's.**

In `scripts/build-shaders.sh`, replace everything from the line `cd Shaders/viewport` to the end of the file with:
```bash
shopt -s nullglob
# sha256sum's "<sha256>  <name>" lines for the named files, sorted bytewise by name: the format of MetalUI's SOURCE.sha256
# (SourceMarker.swift), so the same function says whether a directory is current and writes INCLUDES.sha256.
digests() {
    [ "$#" -gt 0 ] || return 0
    local name
    while read -r name; do sha256sum "$name"; done < <(printf '%s\n' "$@" | LC_ALL=C sort)
}

# Compiles Shaders/$1 into Shaders/$1/compiled, or leaves it when current. Every directory of Shaders/ is a set: viewport (xp-3) and implicit
# (xp-c, the implicit engine's compute kernels).
build_set() {
    local set=$1
    cd "$ROOT/Shaders/$set"
    local stages=(*.vert.hlsl *.frag.hlsl *.comp.hlsl)
    local headers=(*.hlsli)
    [ "${#stages[@]}" -gt 0 ] || fail 1 "no NAME.vert.hlsl, NAME.frag.hlsl or NAME.comp.hlsl in Shaders/$set."
    local current=1 stage kind
    if [ -f compiled/SOURCE.sha256 ] && [ -f compiled/INCLUDES.sha256 ] \
        && [ "$(digests "${stages[@]}")" = "$(cat compiled/SOURCE.sha256)" ] \
        && [ "$(digests "${headers[@]}")" = "$(cat compiled/INCLUDES.sha256)" ]; then
        for stage in "${stages[@]}"; do
            for kind in spv msl dxil json; do [ -s "compiled/${stage%.hlsl}.$kind" ] || current=0; done
        done
    else
        current=0
    fi
    if [ "$current" = 1 ]; then
        echo "Shaders/$set/compiled is current."
        return 0
    fi
    rm -rf compiled
    echo "Compiling Shaders/$set with MetalUI's MetalUICompileShaders and $TOOL..."
    if ! swift run --package-path "$METALUI" --scratch-path "$SCRATCH" MetalUICompileShaders \
            --shadercross "$SHADERCROSS" --source "$ROOT/Shaders/$set" --out "$ROOT/Shaders/$set/compiled"; then
        rm -rf compiled
        fail 1 "$TOOL failed to compile a shader of Shaders/$set, or MetalUICompileShaders did not build (the lines above name the file and the complaint). Shaders/$set/compiled was removed."
    fi
    digests "${headers[@]}" > compiled/INCLUDES.sha256
    echo "Built Shaders/$set/compiled ($(find compiled -type f | wc -l | tr -d ' ') files)."
}

for set in viewport implicit; do build_set "$set"; done
```
and in its header comment change "Compiles the viewport's SDL_GPU shaders" to "Compiles the app's SDL_GPU shaders, every set in Shaders/ (the viewport's, xp-3, and the implicit engine's compute kernels, xp-c)", and "the HLSL in Shaders/viewport becomes" to "the HLSL in Shaders/<set> becomes … in Shaders/<set>/compiled". The set list is written out (not globbed) so a stray directory is not compiled.

In `scripts/build-shaders.ps1`, replace everything from the line `$source = Join-Path $root 'Shaders\viewport'` to the end with:
```powershell
# Every directory of Shaders\ is a set: viewport (xp-3) and implicit (xp-c, the implicit engine's compute kernels).
foreach ($set in @('viewport', 'implicit')) {
    $source = Join-Path $root "Shaders\$set"
    $out = Join-Path $source 'compiled'
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    Write-Output "Compiling Shaders\$set with MetalUI's MetalUICompileShaders and $tool..."
    # Run from the shader directory, as build-shaders.sh does: shadercross hands DXC the source as "hlsl.hlsl" with no include path, so
    # `#include "contract.hlsli"` resolves against the working directory.
    Push-Location $source
    try {
        swift run --package-path $metalUI --scratch-path $scratch MetalUICompileShaders --shadercross $ShaderCross --source $source --out $out
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE) {
        if (Test-Path $out) { Remove-Item $out -Recurse -Force }
        Stop-Build 1 "$tool failed to compile a shader of Shaders\$set, or MetalUICompileShaders did not build (the lines above name the file). Shaders\$set\compiled was removed."
    }
    # INCLUDES.sha256 in MetalUI's marker format: "<sha256>  <name>" per header, sorted by name, LF (the tests read it as a table).
    $lines = Get-ChildItem (Join-Path $source '*.hlsli') | Sort-Object Name | ForEach-Object {
        "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
    }
    [IO.File]::WriteAllText((Join-Path $out 'INCLUDES.sha256'), (($lines -join "`n") + "`n"))
    Write-Output "Built Shaders\$set\compiled ($((Get-ChildItem $out -File).Count) files)."
}
```
and update its `.SYNOPSIS` the same way. Check how `build-shaders.sh` runs `swift run` relative to the shader directory before this change (it `cd`s into the set): the function above keeps that.

In `scripts/linux-test.sh`: in the usage comment add `#     shaders compiles every shader set into the worktree (Shaders/*/compiled, git-ignored) and stops: a Mac's tests read the implicit kernels' MSL from there (plan xp-c)`; in the `case $step in` block add `    shaders) compile_shaders ;;` before `all)`; and add `shaders` to the usage line's list (`[build|test|smoke|package|shaders|all]`) and to the error message's.

In `.gitignore`, under the viewport's line, add:
```
# The implicit engine's compute kernels, compiled the same way from Shaders/implicit/*.hlsl (plan xp-c).
/Shaders/implicit/compiled
```

- [ ] **Step 8: Compile and run the contract tests on Linux and on the Mac.**

Run:
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh shaders
ls Shaders/implicit/compiled                     # implicit_evaluate.comp.{dxil,json,msl,spv}, SOURCE.sha256, INCLUDES.sha256
git status --short Shaders                        # nothing: the compiled directory is ignored
swift test --filter CreatorImplicitTests.ImplicitShaderContractTests 2>&1 | tail -3
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter ImplicitShaderContractTests 2>&1 | tail -3
```
Expected: shadercross compiles both sets (the viewport's is "current"); the Mac and Linux runs pass. A DXC error names the file and line: fix the HLSL, not the test. If `theBuildCompiledEveryKernelAndIsCurrent` reports a dropped buffer, the kernel declares one it never reads.

- [ ] **Step 9: Lint and commit.**

```bash
swiftlint lint --strict
git add Shaders/implicit scripts/build-shaders.sh scripts/build-shaders.ps1 scripts/linux-test.sh .gitignore \
        Sources/CreatorImplicit/Compute/ImplicitKernel.swift Sources/CreatorImplicit/Compute/KernelParameters.swift \
        Tests/CreatorImplicitTests/ImplicitShaderContractTests.swift
git commit -m "feat(implicit): the HLSL interpreter and evaluation kernel, compiled with the viewport's shaders (xp-c task 2)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

---

### Task 3: The compute backend, `InterpretedImplicitEngine`'s evaluation, and the Mac's MSL backend

After this task the interpreted engine evaluates on the Mac's GPU in the tests (over the MSL of task 2's kernel) and `GPUAgreementTests` holds it to the CPU. The SDL backend is task 4.

**Files:**
- Create: `Sources/CreatorImplicit/Compute/ImplicitComputeBackend.swift`, `ComputeBatch.swift`, `ComputeBytes.swift`, `InterpretedImplicitEngine.swift`
- Create: `Sources/CreatorImplicit/GPU/ImplicitEngineAvailability.swift`
- Modify: `Sources/CreatorImplicit/GPU/ImplicitGPUEngine.swift` (the `availability` requirement)
- Create (tests): `Tests/CreatorImplicitTests/Support/MSLComputeBackend.swift`, `Support/MSLComputeBuffer.swift`, `Support/GPUEnginesUnderTest.swift`, `InterpretedEngineTests.swift`, `MetalEngineDispatchTests.swift`
- Modify (tests): `Tests/CreatorImplicitTests/GPUAgreementTests.swift`

**Interfaces:**
- Consumes: `ImplicitProgramCompiler.compile(_:)`, `CompiledImplicit.program` (task 1); `ImplicitKernel`, `KernelParameters` (task 2).
- Produces:
  - `public protocol ComputeBuffer: AnyObject, Sendable { var length: Int { get } }`
  - `public protocol ImplicitComputeBackend: Sendable { var name: String { get }; var deviceName: String { get }; var largestBuffer: Int { get }; func makeBuffer(length: Int) throws -> any ComputeBuffer; func run(_ batch: ComputeBatch) async throws -> [[UInt8]] }`
  - `public enum ComputeBackendState: Sendable, CustomStringConvertible { case ready(any ImplicitComputeBackend), absent(String), broken(String) }`
  - `public struct ComputeUpload`, `ComputeDispatch`, `ComputeDownload`, `ComputeBatch` (fields below), all `Sendable`.
  - `public enum ImplicitEngineAvailability: Sendable, Equatable { case available, absent(String), broken(String) }`; `ImplicitGPUEngine.availability: ImplicitEngineAvailability { get async }`, default `.available`.
  - `public actor InterpretedImplicitEngine: ImplicitGPUEngine` with `public init(name: String, backend: @escaping @Sendable () -> ComputeBackendState, dispatchSize: Int = pointsPerDispatch)`, `public static let pointsPerDispatch = 1 << 20`, `func setAfterDispatch(_:)`, `public internal(set) var meshesMade`, `var epoch`, `func backend() throws(ImplicitCompileError) -> any ImplicitComputeBackend`, `func buffers(for:on:) async throws -> InterpretedImplicitEngine.Prepared`, and `Prepared { program, floats, ints: any ComputeBuffer; parameters: KernelParameters; used: Int }` (task 5 meshes with them).
  - Tests: `GPUEnginesUnderTest.names: [String]`, `.engine(_:) throws -> any ImplicitGPUEngine`, `.interpreted: InterpretedImplicitEngine?`, `.makeInterpreted(dispatchSize:) -> InterpretedImplicitEngine?`, `.interpretedName`, `.interpretedState`.

- [ ] **Step 1: Write the failing tests.**

Move the four Metal-only tests out of `GPUAgreementTests` unchanged: create `Tests/CreatorImplicitTests/MetalEngineDispatchTests.swift` holding `shapesShareOnePipeline`, `aBatchLargerThanOneDispatchIsAnswered`, `anEmptyBatchAndACancelledOneAreHandled`, `cancelEndsABatchAtItsNextDispatchAndNotTheOnesAfter` and `aBatchOfSeveralSmallDispatchesIsAnsweredInOrder`, their bodies copied as they are, in:
```swift
#if canImport(Metal)
import CreatorGeometry
import Synchronization
import Testing
@testable import CreatorImplicit

/// The Metal engine's own dispatching: one pipeline per shape, dispatch sizes, cancellation (moved from `GPUAgreementTests` by plan xp-c, which
/// made that suite run over every engine; these name `MetalImplicitEngine` and stay Metal's). Skipped without a Metal device.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct MetalEngineDispatchTests {
    // the five tests, unchanged
}
#endif
```

Replace `Tests/CreatorImplicitTests/GPUAgreementTests.swift` with:
```swift
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Every GPU engine this machine has against the CPU reference (implicit spec §4.1, §7, Errata D11, D21): every node and every field kind on a
/// fixed point set, within 1e-4 mm. The engines are `GPUEnginesUnderTest.names`: Metal on a Mac with a device, the interpreted engine over the MSL
/// of the HLSL kernels on a Mac where `scripts/linux-test.sh shaders` was run, and the interpreted engine over SDL_GPU on Linux and Windows. With no
/// engine the suite is skipped, by name.
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

    /// The mapped lattices where the mapping is hardest: next to the singular set (the exclusion and its fade) and on both sides of the cut of the
    /// angle.
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
The only differences from the old suite: the engine is an argument (`engine.compile(solid)` instead of `ImplicitCompiler.compile(solid)`, so each engine compiles its own form), the messages name it, and the file is no longer under `#if canImport(Metal)`. On a Mac without the MSL the Metal cases run exactly as before.

`Tests/CreatorImplicitTests/InterpretedEngineTests.swift`:
```swift
import CreatorGeometry
import Synchronization
import Testing
@testable import CreatorImplicit

/// The interpreted engine's own dispatching (plan xp-c): the same backend code on every platform (the MSL backend on a Mac, SDL_GPU on Linux and
/// Windows), so these run wherever `GPUEnginesUnderTest.interpreted` exists, and are skipped, by name, where it does not.
@Suite(.enabled(if: GPUEnginesUnderTest.interpreted != nil, "needs the interpreted engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct InterpretedEngineTests {
    @Test func aBatchLargerThanOneDispatchIsAnsweredInOrder() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeInterpreted(dispatchSize: 1_000))
        let program = try await engine.compile(.sphere(radius: 5))
        let points = (0..<2_500).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let values = try await engine.evaluate(program, at: points)
        #expect(values.count == points.count)
        for index in [0, 999, 1_000, 2_499] { #expect(abs(values[index] - Float(index % 100 - 5)) < 1e-5) }
    }

    @Test func anEmptyBatchAndACancelledOneAreHandled() async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(.sphere(radius: 5)))
        #expect(try await evaluator.evaluate([]).isEmpty)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await evaluator.evaluate([SIMD3(1, 2, 3)])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancelEndsABatchAtItsNextDispatchAndNotTheOnesAfter() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeInterpreted(dispatchSize: 1_000))
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
        #expect(whole.count == points.count && abs(whole[3_499] - Float(3_499 % 100 - 5)) < 1e-5, "a later batch runs whole")
    }

    @Test func editingANumberNeedsNoNewProgramAndGivesTheNewValue() async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        let first = try await engine.compile(.sphere(radius: 5))
        let second = try await engine.compile(.sphere(radius: 25))
        #expect(first.program == second.program)
        let values = try await engine.evaluate(second, at: [SIMD3(30, 0, 0)])
        #expect(abs(values[0] - 5) < 1e-5)
    }

    /// A Metal-compiled solid (no program) is not the interpreter's: `.unsupported`, so `ImplicitEvaluators` would use the CPU.
    @Test func aSolidWithoutAProgramIsUnsupported() async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        let metalForm = try ImplicitCompiler.compile(.sphere(radius: 1))
        await #expect(throws: ImplicitCompileError.self) { try await engine.prepare(metalForm) }
    }

    /// The angle of a cylindrical or spherical mapping exactly on its cut (y = 0 on either side of the axis) and at the axis itself (x = y = 0),
    /// where a port of atan2 goes wrong first (Review Focus 5).
    @Test(arguments: LatticeFixtures.mappedAll.map(\.name))
    func theAngleOnTheCutAndAtTheAxisAgreesWithTheCPU(_ name: String) async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
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
`LatticeFixtures.mappedAll` and `LatticeFixtures.crossing` exist (`Support/LatticeFixtures.swift`; `everyMapped` is `mappedAll + faceAll + faceOutsideAll`).

- [ ] **Step 2: Run them to see them fail.**

Run: `swift test --filter "CreatorImplicitTests.(GPUAgreementTests|InterpretedEngineTests|MetalEngineDispatchTests)" 2>&1 | tail -5`
Expected: build failure ("cannot find 'GPUEnginesUnderTest' in scope").

- [ ] **Step 3: Write the backend protocol and the batch.**

`Sources/CreatorImplicit/GPU/ImplicitEngineAvailability.swift`:
```swift
/// Whether a GPU engine can run on this machine (plan xp-c, user decision X-C4), asked by `ImplicitEvaluators.make` before it compiles.
public enum ImplicitEngineAvailability: Sendable, Equatable {
    case available
    /// There is no GPU for it (no device answers): the CPU runs, and nobody is told, as on a machine with no GPU engine at all.
    case absent(String)
    /// It should run and cannot (its kernels are missing, a pipeline was refused): the CPU runs and the person is told "Running on the CPU".
    case broken(String)
}
```

In `Sources/CreatorImplicit/GPU/ImplicitGPUEngine.swift`, add to the protocol after `deviceName`:
```swift
    /// Whether this engine can run here (plan xp-c). Asked before `compile`; an engine that is absent or broken is not asked to compile. The default
    /// is `.available` (Metal's engine exists only where it has a device).
    var availability: ImplicitEngineAvailability { get async }
```
and to its extension:
```swift
    public var availability: ImplicitEngineAvailability { .available }
```
and in the protocol's doc comment replace "`MetalImplicitEngine` is its only implementation in 7c-1, compiled only where Metal exists, and an SDL3 GPU compute engine for Linux and Windows follows (track xp-c)" with "`MetalImplicitEngine` is macOS's, compiled only where Metal exists; `InterpretedImplicitEngine` is Linux's and Windows' (plan xp-c), over SDL_GPU compute".

`Sources/CreatorImplicit/Compute/ImplicitComputeBackend.swift`:
```swift
/// A GPU buffer a backend made: storage the kernels read and write, and the copies go to and from.
public protocol ComputeBuffer: AnyObject, Sendable {
    var length: Int { get }
}

/// What `InterpretedImplicitEngine` needs from a GPU API (plan xp-c): buffers, and one batch of copies and dispatches at a time. SDL_GPU on Linux and
/// Windows (`SDLComputeBackend`); in the tests, Metal running the MSL the same HLSL was compiled to (`MSLComputeBackend`). A backend never blocks the
/// calling thread: `run` awaits the GPU.
public protocol ImplicitComputeBackend: Sendable {
    /// The engine's name for the badge: "Vulkan", "Direct3D 12", "Metal (HLSL)".
    var name: String { get }
    /// The device's name, for the inspector.
    var deviceName: String { get }
    /// The largest storage buffer, in bytes, the engine may make.
    var largestBuffer: Int { get }

    /// A storage buffer the kernels may read and write, at least `length` bytes. Throws `ImplicitCompileError.unsupported` past `largestBuffer` or
    /// when the device refuses, so the request goes to the CPU.
    func makeBuffer(length: Int) throws -> any ComputeBuffer

    /// Records `batch` into one command buffer, its uploads, then each dispatch in a compute pass of its own (so a dispatch sees what the ones
    /// before it wrote: SDL_GPU does not synchronize dispatches inside one pass), then its downloads; submits it, awaits the GPU, and returns each
    /// download's bytes in order. Throws `ImplicitCompileError.engine` when the GPU API refuses something.
    func run(_ batch: ComputeBatch) async throws -> [[UInt8]]
}

/// A backend, or why there is none.
public enum ComputeBackendState: Sendable, CustomStringConvertible {
    case ready(any ImplicitComputeBackend)
    /// No device (`ImplicitEngineAvailability.absent`).
    case absent(String)
    /// A device, but the kernels are missing or a pipeline was refused (`ImplicitEngineAvailability.broken`).
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
/// Bytes copied into a buffer before a batch's dispatches.
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

/// One kernel run over `threads` threads (rounded up to whole groups of `ImplicitKernel.threadsPerGroup`; the kernels ignore the extra ones), with
/// its storage buffers in the order the kernel declares them.
public struct ComputeDispatch: Sendable {
    public var kernel: ImplicitKernel
    public var parameters: KernelParameters
    public var readOnly: [any ComputeBuffer]
    public var readWrite: [any ComputeBuffer]
    public var threads: Int

    public init(kernel: ImplicitKernel, parameters: KernelParameters, readOnly: [any ComputeBuffer], readWrite: [any ComputeBuffer],
                threads: Int) {
        self.kernel = kernel
        self.parameters = parameters
        self.readOnly = readOnly
        self.readWrite = readWrite
        self.threads = threads
    }
}

/// The first `length` bytes of a buffer, read back after a batch's dispatches.
public struct ComputeDownload: Sendable {
    public var buffer: any ComputeBuffer
    public var length: Int

    public init(buffer: any ComputeBuffer, length: Int) {
        self.buffer = buffer
        self.length = length
    }
}

/// One command buffer's work (`ImplicitComputeBackend.run`).
public struct ComputeBatch: Sendable {
    public var uploads: [ComputeUpload]
    public var dispatches: [ComputeDispatch]
    public var downloads: [ComputeDownload]

    public init(uploads: [ComputeUpload] = [], dispatches: [ComputeDispatch] = [], downloads: [ComputeDownload] = []) {
        self.uploads = uploads
        self.dispatches = dispatches
        self.downloads = downloads
    }

    /// Whether every dispatch lists the buffers its kernel declares and fits in one dispatch's 65,535 groups (`SDLComputeBackend` and
    /// `MSLComputeBackend` check it before they record).
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
/// The engine's synchronous byte work (plan xp-c): packing values for an upload and reading them back, and cutting a count into dispatch ranges.
/// Synchronous on purpose: the Windows Swift 6.4 compiler asserts on an `async` function that holds a loop's locals across an `await`.
enum ComputeBytes {
    /// The most thread groups one dispatch has (Vulkan's guaranteed `maxComputeWorkGroupCount`; gap XP-G24).
    static let maximumGroups = 65_535

    static func bytes<Value>(of values: [Value]) -> [UInt8] {
        values.withUnsafeBytes { Array($0) }
    }

    /// Points as three floats each (the kernels read `float` triples; `SIMD3<Float>` is 16 bytes).
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

    /// The bytes read as `Value`s (whole values only), copied, so alignment does not matter.
    static func values<Value: BitwiseCopyable>(_ bytes: [UInt8], as type: Value.Type) -> [Value] {
        let count = bytes.count / MemoryLayout<Value>.stride
        return [Value](unsafeUninitializedCapacity: count) { buffer, initialized in
            bytes.withUnsafeBytes { raw in
                UnsafeMutableRawBufferPointer(buffer).copyMemory(from: UnsafeRawBufferPointer(rebasing: raw[0..<(count * MemoryLayout<Value>.stride)]))
            }
            initialized = count
        }
    }

    /// `0 ..< count` cut into ranges of at most `size`.
    static func ranges(count: Int, size: Int) -> [Range<Int>] {
        stride(from: 0, to: count, by: max(1, size)).map { $0..<min($0 + max(1, size), count) }
    }
}
```

- [ ] **Step 4: Write the engine's evaluation half.**

`Sources/CreatorImplicit/Compute/InterpretedImplicitEngine.swift`:
```swift
import Foundation

/// The portable GPU engine (plan xp-c; cross-platform spec erratum E8, implicit spec erratum D21): a solid compiled to an `ImplicitProgram` runs in
/// the HLSL interpreter's kernels (`Shaders/implicit`), the same kernels on every backend. Linux's and Windows' engine (`InterpretedImplicitEngine.sdl`,
/// over SDL_GPU); on a Mac, the tests' (over Metal and the MSL of the same HLSL). The backend is made on first use, inside the actor, so making the
/// engine costs nothing and its device is never made on the main actor. Like `MetalImplicitEngine` it keeps the buffers of the few compiled solids
/// most recently used, so meshing batch after batch uploads a solid once; unlike it there is nothing to compile per shape.
public actor InterpretedImplicitEngine: ImplicitGPUEngine {
    /// A solid's uploaded program and buffers, and the uniform block's solid-specific words.
    struct Prepared: Sendable {
        var program: any ComputeBuffer
        var floats: any ComputeBuffer
        var ints: any ComputeBuffer
        var parameters: KernelParameters
        var used: Int
    }

    public nonisolated let name: String
    private let makeBackend: @Sendable () -> ComputeBackendState
    private var state: ComputeBackendState?
    private var prepared: [UUID: Prepared] = [:]
    private var clock = 0

    /// How many compiled solids keep their buffers.
    private static let preparedLimit = 8
    /// The most points one dispatch takes (an interpreted `sdf` costs more than Metal's specialised one: Metal's is 2^22).
    public static let pointsPerDispatch = 1 << 20

    /// Bumped by `cancel()`: a batch that started before it ends at its next dispatch.
    var epoch = 0
    let dispatchSize: Int
    private var afterDispatch: (@Sendable (Int) async -> Void)?
    /// The sizes meshing works in (`InterpretedImplicitEngine+Meshing.swift`).
    var meshTuning = MeshTuning()
    /// How many meshes `meshBricks` has made: the benchmarks use it to see a row's meshes were made on the GPU.
    public internal(set) var meshesMade = 0

    /// `backend` makes the backend, once, on first use; `dispatchSize` is `pointsPerDispatch` except in tests that need many dispatches.
    public init(name: String, backend: @escaping @Sendable () -> ComputeBackendState, dispatchSize: Int = pointsPerDispatch) {
        self.name = name
        makeBackend = backend
        self.dispatchSize = max(1, min(dispatchSize, Self.pointsPerDispatch))
    }

    /// Sets (or clears) the hook called after each dispatch with how many have run in this batch: tests cancel from it, at a known point.
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
        let program = try ImplicitProgramCompiler.compile(solid)
        try await prepare(program)
        return program
    }

    /// Nothing to compile per shape: checks that `program` is the interpreter's and that the backend exists.
    public func prepare(_ program: CompiledImplicit) async throws(ImplicitCompileError) {
        guard program.program != nil else { throw .unsupported("a solid compiled for Metal, not for the interpreter") }
        _ = try backend()
    }

    public func evaluate(_ program: CompiledImplicit, at points: [SIMD3<Float>]) async throws -> [Float] {
        try Task.checkCancellation()
        guard !points.isEmpty else { return [] }
        let started = epoch
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
            values += try await backend.run(Self.evaluation(points[ranges[index]], solid, input, output)).first.map {
                ComputeBytes.values($0, as: Float.self)
            } ?? []
            await afterDispatch?(index + 1)
        }
        return values
    }

    /// One evaluation dispatch: upload the points, run, download the values.
    private static func evaluation(_ points: ArraySlice<SIMD3<Float>>, _ solid: Prepared, _ input: any ComputeBuffer,
                                   _ output: any ComputeBuffer) -> ComputeBatch {
        var parameters = solid.parameters
        parameters.count = UInt32(points.count)
        return ComputeBatch(
            uploads: [ComputeUpload(bytes: ComputeBytes.packed(points), buffer: input)],
            dispatches: [ComputeDispatch(kernel: .evaluate, parameters: parameters, readOnly: [input, solid.program, solid.floats, solid.ints],
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
        guard let words = program.program?.words else { throw ImplicitCompileError.unsupported("a solid compiled for Metal") }
        let floats = program.parameters + program.pool + program.images
        let ints = program.integers + program.tables
        var parameters = KernelParameters()
        parameters.instructions = UInt32(words.count / ImplicitProgram.wordsPerInstruction)
        parameters.poolBase = UInt32(program.parameters.count)
        parameters.imagesBase = UInt32(program.parameters.count + program.pool.count)
        parameters.tablesBase = UInt32(program.integers.count)
        let entry = Prepared(program: try backend.makeBuffer(length: words.count * 4), floats: try backend.makeBuffer(length: floats.count * 4),
                             ints: try backend.makeBuffer(length: ints.count * 4), parameters: parameters, used: clock)
        _ = try await backend.run(ComputeBatch(uploads: [
            ComputeUpload(bytes: ComputeBytes.bytes(of: words), buffer: entry.program),
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
`MeshTuning` is task 5's; until then add, in `InterpretedImplicitEngine+Meshing.swift`, only:
```swift
extension InterpretedImplicitEngine {
    /// The sizes meshing works in (task 5 fills this in).
    struct MeshTuning: Sendable {}
}
```
An upload of zero bytes (a solid with no pool or pictures) is skipped by the backends; `makeBuffer` makes at least 16 bytes.

- [ ] **Step 5: Write the Mac's MSL backend and the engines under test.**

`Tests/CreatorImplicitTests/Support/MSLComputeBuffer.swift`:
```swift
#if canImport(Metal)
@preconcurrency import Metal
@testable import CreatorImplicit

/// A Metal buffer as a `ComputeBuffer` (test support for `MSLComputeBackend`).
final class MSLComputeBuffer: ComputeBuffer, @unchecked Sendable {
    let buffer: any MTLBuffer
    var length: Int { buffer.length }

    init(_ buffer: any MTLBuffer) {
        self.buffer = buffer
    }
}
#endif
```
(`@unchecked Sendable`: an `MTLBuffer` is thread-safe to hand between threads; the engine touches its contents only between batches it awaited.)

`Tests/CreatorImplicitTests/Support/MSLComputeBackend.swift`:
```swift
#if canImport(Metal)
import Foundation
@preconcurrency import Metal
@testable import CreatorImplicit

/// The interpreted engine on this Mac's GPU, for the tests (plan xp-c, user decision X-C2): the MSL SDL_shadercross made of `Shaders/implicit`'s HLSL
/// (`Shaders/implicit/compiled/*.comp.msl`, made in the Linux image by `scripts/linux-test.sh shaders`), bound as SDL_GPU's Metal driver binds it:
/// the uniform block at `[[buffer(0)]]`, then the read-only storage buffers, then the read-write ones (SDL's `SDL_CreateGPUComputePipeline` notes).
/// So the HLSL and `InterpretedImplicitEngine` run here exactly as they do on Linux and Windows. Absent when the MSL was not built.
final class MSLComputeBackend: ImplicitComputeBackend, @unchecked Sendable {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Shaders/implicit/compiled")

    /// Made once for the test process.
    static let state: ComputeBackendState = make()

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipelines: [ImplicitKernel: any MTLComputePipelineState]
    let name = "Metal (HLSL)"
    /// The SDL backends' cap (gap XP-G24), so the tests reach the same limits.
    let largestBuffer = 1 << 27
    var deviceName: String { device.name }

    private init(device: any MTLDevice, queue: any MTLCommandQueue, pipelines: [ImplicitKernel: any MTLComputePipelineState]) {
        self.device = device
        self.queue = queue
        self.pipelines = pipelines
    }

    static func make() -> ComputeBackendState {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return .absent("no Metal device") }
        guard FileManager.default.fileExists(atPath: directory.appending(path: "SOURCE.sha256").path) else {
            return .absent("Shaders/implicit/compiled was not built on this Mac: run XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh shaders")
        }
        var pipelines: [ImplicitKernel: any MTLComputePipelineState] = [:]
        for kernel in ImplicitKernel.allCases {
            let stem = directory.appending(path: "\(kernel.rawValue).comp")
            guard FileManager.default.fileExists(atPath: stem.appendingPathExtension("msl").path) else { continue }   // task 5 adds kernels
            do {
                let library = try device.makeLibrary(source: try String(contentsOf: stem.appendingPathExtension("msl"), encoding: .utf8), options: nil)
                guard let function = library.makeFunction(name: "main0") else { return .broken("\(kernel.rawValue).comp.msl has no main0") }
                let reflection = try JSONSerialization.jsonObject(with: Data(contentsOf: stem.appendingPathExtension("json"))) as? [String: Int]
                guard reflection?["readonly_storage_buffers"] == kernel.bindings.readOnly,
                      reflection?["readwrite_storage_buffers"] == kernel.bindings.readWrite, reflection?["uniform_buffers"] == 1,
                      reflection?["threadcount_x"] == ImplicitKernel.threadsPerGroup else {
                    return .broken("\(kernel.rawValue).comp.json does not match ImplicitKernel.bindings")
                }
                pipelines[kernel] = try device.makeComputePipelineState(function: function)
            } catch {
                return .broken("\(kernel.rawValue): \(error.localizedDescription)")
            }
        }
        return .ready(MSLComputeBackend(device: device, queue: queue, pipelines: pipelines))
    }

    func makeBuffer(length: Int) throws -> any ComputeBuffer {
        guard length <= largestBuffer, let buffer = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else {
            throw ImplicitCompileError.unsupported("a GPU buffer of \(length) bytes")
        }
        return MSLComputeBuffer(buffer)
    }

    func run(_ batch: ComputeBatch) async throws -> [[UInt8]] {
        guard batch.isWellFormed, let commands = queue.makeCommandBuffer() else {
            throw ImplicitCompileError.engine("a batch the kernels do not declare, or no command buffer")
        }
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

    /// The uploads copied now (shared memory, and every earlier batch was awaited), then each dispatch in an encoder of its own.
    private func record(_ batch: ComputeBatch, into commands: any MTLCommandBuffer) throws {
        for upload in batch.uploads where !upload.bytes.isEmpty {
            guard let buffer = upload.buffer as? MSLComputeBuffer else { throw ImplicitCompileError.engine("a foreign buffer") }
            upload.bytes.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { (buffer.buffer.contents() + upload.offset).copyMemory(from: base, byteCount: bytes.count) }
            }
        }
        for dispatch in batch.dispatches where dispatch.threads > 0 {
            guard let pipeline = pipelines[dispatch.kernel], let encoder = commands.makeComputeCommandEncoder() else {
                throw ImplicitCompileError.engine("no pipeline for \(dispatch.kernel.rawValue)")
            }
            encoder.setComputePipelineState(pipeline)
            let uniform = dispatch.parameters.bytes
            uniform.withUnsafeBytes { bytes in
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

/// The GPU engines this machine can test, by name (plan xp-c): "Metal" on a Mac with a Metal device; the interpreted engine as "Metal (HLSL)" on a
/// Mac where `scripts/linux-test.sh shaders` built the MSL, as "Vulkan" on Linux and "Direct3D 12" on Windows where SDL_GPU has a device.
enum GPUEnginesUnderTest {
    /// The interpreted engine's backend here, made once.
    static let interpretedState: ComputeBackendState = {
        #if canImport(MetalUISDLGPU)
        return SDLComputeBackend.make()
        #elseif canImport(Metal)
        return MSLComputeBackend.state
        #else
        return .absent("no backend for the interpreted engine on this platform")
        #endif
    }()

    static var interpretedName: String {
        if case .ready(let backend) = interpretedState { return backend.name }
        return "interpreted"
    }

    /// A fresh interpreted engine over the shared backend (each has its own hooks, tuning and epoch), or `nil` without one.
    static func makeInterpreted(dispatchSize: Int = InterpretedImplicitEngine.pointsPerDispatch) -> InterpretedImplicitEngine? {
        guard case .ready = interpretedState else { return nil }
        let state = interpretedState
        return InterpretedImplicitEngine(name: interpretedName, backend: { state }, dispatchSize: dispatchSize)
    }

    /// The interpreted engine the suites share.
    static let interpreted: InterpretedImplicitEngine? = makeInterpreted()

    static let names: [String] = {
        var names: [String] = []
        #if canImport(Metal)
        if MetalImplicitEngine.shared != nil { names.append("Metal") }
        #endif
        if interpreted != nil { names.append(interpretedName) }
        return names
    }()

    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    static func engine(_ name: String) throws -> any ImplicitGPUEngine {
        #if canImport(Metal)
        if name == "Metal", let engine = MetalImplicitEngine.shared { return engine }
        #endif
        if name == interpretedName, let interpreted { return interpreted }
        throw Missing(description: "no engine named \(name) here")
    }

    /// Why the interpreted engine is missing, for a skip's message.
    static var unavailableReason: String { interpretedState.description }
}
```
On Linux and Windows `SDLComputeBackend` is task 4's: until then guard that branch with `#if canImport(MetalUISDLGPU) && false` and remove the `&& false` in task 4, step 6.

- [ ] **Step 6: Build the MSL and run the tests on the Mac.**

Run:
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh shaders
swift test --filter "CreatorImplicitTests.(GPUAgreementTests|InterpretedEngineTests|MetalEngineDispatchTests)" 2>&1 | tail -8
```
Expected: PASS, with the agreement cases run twice per fixture ("Metal" and "Metal (HLSL)"). If an "(HLSL)" case fails on a value: run that fixture alone (`--filter "theGPUAgreesWithTheCPU"` and read the message), find the op it uses, and diff its HLSL against the MSL in `ImplicitShaderLibrary*.swift`; if every case returns 0, the binding order is wrong (check the `.msl` file's `[[buffer(n)]]` against `bindings`). Then without the MSL:
```bash
mv Shaders/implicit/compiled /tmp/xp-c-compiled-aside
swift test --filter "CreatorImplicitTests.(GPUAgreementTests|InterpretedEngineTests)" 2>&1 | tail -3   # Metal cases pass; InterpretedEngineTests skipped, naming the script
mv /tmp/xp-c-compiled-aside Shaders/implicit/compiled
```
Then `swift test --filter CreatorImplicitTests 2>&1 | grep -E "Test run with|recorded an issue"`: one line, no issue.

- [ ] **Step 7: Check the Windows-sensitive code with the asserts toolchain, lint and commit.**

```bash
TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release 2>&1 | tail -3   # Build complete
swiftlint lint --strict
git add Sources/CreatorImplicit/Compute Sources/CreatorImplicit/GPU Tests/CreatorImplicitTests
git commit -m "feat(implicit): InterpretedImplicitEngine evaluates through a compute backend; the Mac runs it over the HLSL's MSL (xp-c task 3)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

---

### Task 4: The SDL_GPU backend, the platform's engine, and the fallbacks a person sees

**Files:**
- Create: `Sources/CreatorImplicit/SDL/SDLComputeBackend.swift`, `SDLComputeRecording.swift`, `SDLComputeBuffer.swift`, `SDLImplicitShaders.swift`, `SDLImplicitEngine.swift`
- Modify: `Package.swift` (`CreatorImplicit` and `CreatorImplicitTests` gain `metalUISDL`, `metalUISDLGPU`), `Sources/CreatorImplicit/GPU/ImplicitGPUEngines.swift`, `Sources/CreatorImplicit/GPU/ImplicitEvaluators.swift`
- Modify (tests): `Support/GPUEnginesUnderTest.swift` (drop task 3's `&& false`), `Support/StubGPUEngine.swift` (an `availability`), `ImplicitEvaluatorsTests.swift`, `GPUBatchEvaluatorTests.swift`, `ImplicitPortabilityTests.swift`
- Create (tests): `Tests/CreatorImplicitTests/SDLComputeBackendTests.swift`, `ImplicitGPUAvailabilityTests.swift`

**Interfaces:**
- Consumes: everything of task 3; MetalUI's `SDLGPUDevice`, `SDLGPUBuffer`, `SDLGPUTransferBuffer`, `SDLGPUComputePipeline`, `SDLGPUCommandBuffer`, `SDLGPUComputePass`, `SDLGPUShaderLibrary`, `SDLGPUFence` (names checked in task 0).
- Produces:
  - `SDLComputeBackend.make(sourceTree: URL = SDLImplicitShaders.sourceTree) -> ComputeBackendState`, `SDLComputeBackend.platformName` ("Vulkan" / "Direct3D 12").
  - `SDLImplicitShaders.sourceTree`, `.directoryName` (`"ImplicitShaders"`), `.library(sourceTree:)`, `.verify(driver:sourceTree:) throws -> Int` (task 7's self-test).
  - `InterpretedImplicitEngine.sdl` (Linux, Windows); `ImplicitGPUEngines.platformDefault` returns it there; `ImplicitGPUEngines.meshesMade() async -> Int?`.
  - `ImplicitEvaluators.make` reads `availability` (X-C4).

- [ ] **Step 1: Write the failing tests.**

In `Tests/CreatorImplicitTests/Support/StubGPUEngine.swift` give the stub an availability: add `private let reported: ImplicitEngineAvailability`, an `availability: ImplicitEngineAvailability = .available` parameter to its initializer (stored in `reported`), and
```swift
    var availability: ImplicitEngineAvailability { reported }
```
(Read the stub's initializer first and add the parameter last, with its default, so every existing call compiles unchanged.)

Add to `ImplicitEvaluatorsTests` (the suite, not `MetalEvaluatorsTests`):
```swift
    /// No device for the engine: the CPU, and nobody is told (plan xp-c, X-C4).
    @Test func anAbsentEngineRunsOnTheCPUSilently() async {
        let engine = StubGPUEngine(availability: .absent("no SDL_GPU device"))
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.sphere, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == nil)
        #expect(await engine.prepared == 0, "an absent engine is not asked to compile")
    }

    /// The engine should run and cannot (its kernels are missing, a pipeline was refused): the CPU, with the warning, and the reason for the log.
    @Test func aBrokenEngineRunsOnTheCPUWithTheWarning() async {
        let engine = StubGPUEngine(availability: .broken("Shaders/implicit/compiled is missing"))
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.sphere, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == ImplicitEvaluators.cpuWarning)
        #expect(selection.diagnostic?.contains("Shaders/implicit/compiled is missing") == true)
    }

    /// A solid beyond the interpreter's registers runs on the CPU with the warning, as one with no Metal form does (Review Focus 1).
    @Test(.enabled(if: GPUEnginesUnderTest.interpreted != nil, "needs the interpreted engine"))
    func aSolidBeyondTheInterpreterRunsOnTheCPUWithTheWarning() async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        var solid = ImplicitSolid.sphere(radius: 1)
        for _ in 0..<40 { solid = .union([solid, .sphere(radius: 2)], blend: .constant(0.5)) }
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == ImplicitEvaluators.cpuWarning)
    }
```
The third test needs the interpreted engine, so it carries its own trait and the suite's other tests run without one.

`Tests/CreatorImplicitTests/ImplicitGPUAvailabilityTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorImplicit

/// Which engine this platform evaluates on (plan xp-c): Metal on a Mac, the interpreted engine over SDL_GPU on Linux and Windows. Where the
/// environment promises a GPU (`XP_REQUIRE_GPU=1`: the Linux image's lavapipe, the Windows job's WARP) a missing device fails here, so a runner
/// that lost its driver cannot pass the agreement suites by skipping them.
struct ImplicitGPUAvailabilityTests {
    @Test func thePlatformEngineIsMetalOnAMacAndTheInterpretedEngineElsewhere() async {
        guard let engine = ImplicitGPUEngines.platformDefault else { return }
        #if canImport(Metal)
        #expect(engine.name == "Metal")
        #elseif os(Windows)
        #expect(engine.name == "Direct3D 12")
        #else
        #expect(engine.name == "Vulkan")
        #endif
    }

    @Test func anEngineAnswersWhereTheEnvironmentPromisesOne() async {
        guard ProcessInfo.processInfo.environment["XP_REQUIRE_GPU"] == "1" else { return }
        #if canImport(MetalUISDLGPU)
        let availability = await InterpretedImplicitEngine.sdl.availability
        #expect(availability == .available, "XP_REQUIRE_GPU=1 but the implicit engine is \(availability)")
        #expect(GPUEnginesUnderTest.interpreted != nil, "XP_REQUIRE_GPU=1 but \(GPUEnginesUnderTest.unavailableReason)")
        #endif
    }
}
```

In `GPUBatchEvaluatorTests.swift` replace `thePlatformEngineIsMetalOrNothing` with:
```swift
    @Test func thePlatformEngineIsTheMachinesOrNothing() async {
        // Metal on a Mac with a device; the interpreted engine over SDL_GPU on Linux and Windows (its availability is the device's); else nil.
        guard let engine = ImplicitGPUEngines.platformDefault else { return }
        #expect(["Metal", "Vulkan", "Direct3D 12"].contains(engine.name))
    }
```

`Tests/CreatorImplicitTests/SDLComputeBackendTests.swift`:
```swift
#if canImport(MetalUISDLGPU)
import Foundation
import Testing
@testable import CreatorImplicit

/// The SDL_GPU backend itself (Linux and Windows): the kernels it finds, a broken install, a batch's order.
struct SDLComputeBackendTests {
    /// A checkout or package without the compiled kernels (`swift build` alone compiles none): broken, not absent, so the person hears "Running on
    /// the CPU", and the reason says what to run (Review Focus 2).
    @Test func aDirectoryWithoutTheKernelsIsBrokenAndSaysWhatToRun() throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: "xp-c-no-kernels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        switch SDLComputeBackend.make(sourceTree: empty) {
        case .broken(let why): #expect(why.contains("scripts/build-shaders"), "\(why)")
        case .absent: break   // no device on this runner: nothing to say about the kernels
        case .ready: Issue.record("an empty directory gave a ready backend")
        }
    }

    @Test(.enabled(if: GPUEnginesUnderTest.interpreted != nil, "needs an SDL_GPU device"))
    func everyKernelLoadsForThePlatformsDriver() throws {
        #expect(try SDLImplicitShaders.verify() == ImplicitKernel.allCases.count)
    }

    /// A dispatch sees what the one before it in the batch wrote, because each has its own compute pass.
    @Test(.enabled(if: GPUEnginesUnderTest.interpreted != nil, "needs an SDL_GPU device"))
    func aBatchsUploadsDispatchesAndDownloadsRunInOrder() async throws {
        guard case .ready(let backend) = GPUEnginesUnderTest.interpretedState else { return }
        let program = try ImplicitProgramCompiler.compile(.sphere(radius: 2))
        let engine = try #require(GPUEnginesUnderTest.makeInterpreted())
        let solid = try await engine.buffers(for: program, on: backend)
        let input = try backend.makeBuffer(length: 24)
        let output = try backend.makeBuffer(length: 8)
        var parameters = solid.parameters
        parameters.count = 2
        let read = try await backend.run(ComputeBatch(
            uploads: [ComputeUpload(bytes: ComputeBytes.bytes(of: [Float](arrayLiteral: 5, 0, 0, 0, 0, 1)), buffer: input)],
            dispatches: [ComputeDispatch(kernel: .evaluate, parameters: parameters, readOnly: [input, solid.program, solid.floats, solid.ints],
                                         readWrite: [output], threads: 2)],
            downloads: [ComputeDownload(buffer: output, length: 8)]))
        let values = ComputeBytes.values(try #require(read.first), as: Float.self)
        #expect(values.count == 2 && abs(values[0] - 3) < 1e-6 && abs(values[1] + 1) < 1e-6)
    }
}
#endif
```

Add to `ImplicitPortabilityTests`:
```swift
    /// SDL_GPU is reached only from `SDL*.swift` files, each wholly under `#if canImport(MetalUISDLGPU)`, and no other file names an `SDLGPU` type
    /// (plan xp-c): the module still builds on a Mac, which has no SDL.
    @Test func onlyTheSDLFilesReachSDLGPU() {
        for (name, lines) in Self.sources {
            let code = lines.filter { !$0.isEmpty && !$0.hasPrefix("//") }
            let importsIt = code.contains { Self.imports($0) == "MetalUISDLGPU" }
            if name.hasPrefix("SDL") {
                #expect(code.first == "#if canImport(MetalUISDLGPU)" && code.last == "#endif", "\(name) must be wrapped in #if canImport(MetalUISDLGPU)")
            } else {
                #expect(!importsIt, "\(name) imports MetalUISDLGPU")
                for line in code {
                    #expect(line.range(of: #"\bSDLGPU\w*"#, options: .regularExpression) == nil, "\(name) names an SDL_GPU type: \(line)")
                }
            }
        }
    }
```

- [ ] **Step 2: Run them to see them fail (Mac, then Linux).**

Run: `swift test --filter "CreatorImplicitTests.(ImplicitEvaluatorsTests|ImplicitGPUAvailabilityTests|ImplicitPortabilityTests)" 2>&1 | tail -5`
Expected: `anAbsentEngineRunsOnTheCPUSilently` and `aBrokenEngineRunsOnTheCPUWithTheWarning` fail (the selection ignores availability); the rest pass on a Mac. On Linux (`XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter CreatorImplicitTests`) the build fails: `SDLComputeBackend` does not exist.

- [ ] **Step 3: Declare the dependency.**

In `Package.swift`:
```swift
    .target(name: "CreatorImplicit", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUISDL, metalUISDLGPU]),
```
```swift
    .testTarget(name: "CreatorImplicitTests",
                dependencies: ["CreatorImplicit", "CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUISDL, metalUISDLGPU]),
```
and in the comment above `CreatorImplicit` replace "Portable: the Metal compiler is gated with `#if canImport(Metal)`." with "Portable: the Metal engine is gated with `#if canImport(Metal)`, the SDL_GPU backend (`Sources/CreatorImplicit/SDL`, plan xp-c) with `#if canImport(MetalUISDLGPU)`; MetalUI's SDL products are named on Linux and Windows only." In `metalUISDLGPU`'s doc comment replace "A dependency of `CreatorViewport` and its tests only." with "A dependency of `CreatorViewport`, `CreatorImplicit` (the implicit engine's compute, xp-c) and their tests." Both constants are already `.when(platforms: [.linux, .windows])`, so a macOS build is unchanged.

- [ ] **Step 4: Write the SDL backend.**

`Sources/CreatorImplicit/SDL/SDLComputeBuffer.swift`:
```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// An `SDLGPUBuffer` as a `ComputeBuffer`.
final class SDLComputeBuffer: ComputeBuffer {
    let buffer: SDLGPUBuffer
    var length: Int { buffer.size }

    init(_ buffer: SDLGPUBuffer) {
        self.buffer = buffer
    }
}
#endif
```

`Sources/CreatorImplicit/SDL/SDLImplicitShaders.swift`:
```swift
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// Where the implicit engine's compiled kernels are (plan xp-c): HLSL in `Shaders/implicit`, compiled at build time by `scripts/build-shaders.sh`
/// (`.ps1` on Windows) into `Shaders/implicit/compiled`, git-ignored; a shipped app has them as `ImplicitShaders` beside the executable, looked for
/// first (MetalUI's `SDLGPUShaderLibrary.locate`, the viewport's lookup with another name).
enum SDLImplicitShaders {
    static let directoryName = "ImplicitShaders"

    /// This file is `Sources/CreatorImplicit/SDL/SDLImplicitShaders.swift`: the repository root is four directories up.
    static var sourceTree: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Shaders/implicit/compiled")
    }

    static let remedy = "The implicit engine's kernels are compiled at build time and are not in the repository: run scripts/build-shaders.sh "
        + "(scripts/build-shaders.ps1 on Windows), which needs SDL_shadercross at the commit pinned in scripts/shadercross.env, and in a shipped app "
        + "copy Shaders/implicit/compiled to \(directoryName) beside the executable."

    static func library(sourceTree: URL = sourceTree) throws -> SDLGPUShaderLibrary {
        try SDLGPUShaderLibrary.locate(directoryName: directoryName, sourceTree: sourceTree)
    }

    /// The driver whose blobs this platform's SDL picks.
    static var platformDriver: String {
        #if os(Windows)
        "direct3d12"
        #else
        "vulkan"
        #endif
    }

    /// Loads every kernel for `driver` (its blob and its reflection) and returns how many; throws naming the first missing one.
    static func verify(driver: String = platformDriver, sourceTree: URL = sourceTree) throws -> Int {
        let library = try library(sourceTree: sourceTree)
        for kernel in ImplicitKernel.allCases { _ = try library.compute(kernel.rawValue, driver: driver) }
        return ImplicitKernel.allCases.count
    }
}
#endif
```

`Sources/CreatorImplicit/SDL/SDLComputeRecording.swift`:
```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU
import Synchronization

/// Whether a batch's recording on the worker thread failed (a compute pass refused).
final class SDLRecordingFailure: Sendable {
    let failed = Mutex(false)
}

/// One `ComputeBatch` made ready for the device's worker thread (plan xp-c): the uploads already copied into transfer buffers, each dispatch's
/// pipeline, buffers, uniform bytes and group count worked out, the download transfer buffers made. Built and read synchronously; only `record`
/// runs on the worker, inside `submitBatch`.
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

    init(_ batch: ComputeBatch, device: SDLGPUDevice, pipelines: [ImplicitKernel: SDLGPUComputePipeline]) throws {
        guard batch.isWellFormed else { throw ImplicitCompileError.engine("a dispatch lists buffers its kernel does not declare, or too many groups") }
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
            guard let pipeline = pipelines[dispatch.kernel] else { throw ImplicitCompileError.engine("no pipeline for \(dispatch.kernel.rawValue)") }
            dispatches.append(Dispatch(pipeline: pipeline, readOnly: try dispatch.readOnly.map(sdl), readWrite: try dispatch.readWrite.map(sdl),
                                       uniform: dispatch.parameters.bytes,
                                       groups: (dispatch.threads + ImplicitKernel.threadsPerGroup - 1) / ImplicitKernel.threadsPerGroup))
        }
        var downloads: [Download] = []
        for download in batch.downloads where download.length > 0 {
            guard let transfer = device.makeTransferBuffer(size: download.length, direction: .download) else {
                throw ImplicitCompileError.engine("SDL_GPU refused a transfer buffer of \(download.length) bytes")
            }
            downloads.append(Download(buffer: try sdl(download.buffer), length: download.length, transfer: transfer))
        }
        self.uploads = uploads
        self.dispatches = dispatches
        self.downloads = downloads
    }

    /// On the worker thread, inside `submitBatch`: the uploads, each dispatch in a compute pass of its own, the downloads.
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

    /// After the fence: each download's bytes. The batch's downloads were all requested with a length, so a missing one is empty.
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
A download whose length is 0 is skipped above, so `read()` would return fewer arrays than requested: the engine never asks for an empty download (it returns an empty mesh before), and `run` checks the count.

`Sources/CreatorImplicit/SDL/SDLComputeBackend.swift`:
```swift
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// The interpreted engine over MetalUI's SDL_GPU compute (`MetalUISDLGPU`, MetalUI S5; plan xp-c): an owned, headless device (no window: the
/// engine evaluates before a window draws, in tests and exports), the seven kernels' pipelines made once, and one `submitBatch` per batch, its
/// fence awaited so no thread blocks. No raw `SDL_` call.
final class SDLComputeBackend: ImplicitComputeBackend {
    /// The engine's name on this platform, for the badge.
    static var platformName: String {
        #if os(Windows)
        "Direct3D 12"
        #else
        "Vulkan"
        #endif
    }

    let device: SDLGPUDevice
    let pipelines: [ImplicitKernel: SDLGPUComputePipeline]
    let name = SDLComputeBackend.platformName
    /// The driver's name until MetalUI gives the adapter's (gap XP-G23).
    var deviceName: String { name }
    /// Vulkan's guaranteed `maxStorageBufferRange`: SDL_GPU reports no limit (gap XP-G24).
    let largestBuffer = 1 << 27

    private init(device: SDLGPUDevice, pipelines: [ImplicitKernel: SDLGPUComputePipeline]) {
        self.device = device
        self.pipelines = pipelines
    }

    /// The device, the kernels and their pipelines. `.absent` when no device answers; `.broken` when the kernels are missing or SDL refuses a
    /// pipeline, with SDL's reason or what to run.
    static func make(sourceTree: URL = SDLImplicitShaders.sourceTree) -> ComputeBackendState {
        guard let device = SDLGPUDevice.make() else { return .absent("no SDL_GPU device: \(SDLGPUDevice.lastFailure)") }
        let library: SDLGPUShaderLibrary
        do {
            library = try SDLImplicitShaders.library(sourceTree: sourceTree)
        } catch {
            return .broken("\(error). \(SDLImplicitShaders.remedy)")
        }
        var pipelines: [ImplicitKernel: SDLGPUComputePipeline] = [:]
        for kernel in ImplicitKernel.allCases {
            do {
                let blob = try library.compute(kernel.rawValue, for: device)
                guard blob.readOnlyStorageBuffers == kernel.bindings.readOnly, blob.readWriteStorageBuffers == kernel.bindings.readWrite,
                      blob.uniformBuffers == 1, blob.threadCount.x == ImplicitKernel.threadsPerGroup else {
                    return .broken("\(kernel.rawValue)'s reflection does not match ImplicitKernel.bindings. \(SDLImplicitShaders.remedy)")
                }
                pipelines[kernel] = try device.compileComputePipeline(blob)
            } catch {
                return .broken("\(kernel.rawValue): \(error). \(SDLImplicitShaders.remedy)")
            }
        }
        return .ready(SDLComputeBackend(device: device, pipelines: pipelines))
    }

    func makeBuffer(length: Int) throws -> any ComputeBuffer {
        guard length <= largestBuffer,
              let buffer = device.makeBuffer(size: max(length, 16), usage: [.computeStorageRead, .computeStorageWrite]) else {
            throw ImplicitCompileError.unsupported("a GPU buffer of \(length) bytes")
        }
        return SDLComputeBuffer(buffer)
    }

    func run(_ batch: ComputeBatch) async throws -> [[UInt8]] {
        let recording = try SDLComputeRecording(batch, device: device, pipelines: pipelines)
        let fence = try await device.submitBatch { commandBuffer in recording.record(into: commandBuffer) }
        await fence.wait()
        if recording.hasFailed { throw ImplicitCompileError.engine("SDL_GPU refused a compute pass") }
        let read = recording.read()
        guard read.count == batch.downloads.count else { throw ImplicitCompileError.engine("a download came back empty") }
        return read
    }
}
#endif
```
`SDLComputeBackend` is `Sendable` without `@unchecked`: its stored properties are `let`s of `Sendable` types (`SDLGPUDevice`, `SDLGPUComputePipeline` are `@unchecked Sendable` in MetalUI). If the compiler disagrees, read the diagnostic; do not add `@unchecked`.

`Sources/CreatorImplicit/SDL/SDLImplicitEngine.swift`:
```swift
#if canImport(MetalUISDLGPU)
/// The machine's implicit engine on Linux and Windows (plan xp-c; cross-platform spec erratum E8). Making it costs nothing: the device, the kernels
/// and the pipelines are made on its first `availability`, `compile` or `evaluate`, inside the actor, and kept.
extension InterpretedImplicitEngine {
    public static let sdl = InterpretedImplicitEngine(name: SDLComputeBackend.platformName, backend: { SDLComputeBackend.make() })
}
#endif
```

- [ ] **Step 5: Make it the platform's engine and read its availability.**

`Sources/CreatorImplicit/GPU/ImplicitGPUEngines.swift`:
```swift
/// Which GPU engine this platform has. The only place outside the engines themselves that knows a platform's GPU API, and it names no type of
/// one: it only asks `canImport`.
public enum ImplicitGPUEngines {
    /// The engine for this machine's GPU: Metal on a Mac with a device; the interpreted engine over SDL_GPU on Linux and Windows (plan xp-c; whether
    /// it has a device is its `availability`); `nil` elsewhere.
    public static var platformDefault: (any ImplicitGPUEngine)? {
        #if canImport(Metal)
        MetalImplicitEngine.shared
        #elseif canImport(MetalUISDLGPU)
        InterpretedImplicitEngine.sdl
        #else
        nil
        #endif
    }

    /// How many meshes the platform's engine has made, or `nil` where there is none: the benchmarks check a row's meshes were made on the GPU.
    public static func meshesMade() async -> Int? {
        #if canImport(Metal)
        await MetalImplicitEngine.shared?.meshesMade
        #elseif canImport(MetalUISDLGPU)
        await InterpretedImplicitEngine.sdl.meshesMade
        #else
        nil
        #endif
    }
}
```

In `Sources/CreatorImplicit/GPU/ImplicitEvaluators.swift`, after the `guard choice == .automatic, let engine else { … }` line add:
```swift
        switch await engine.availability {
        case .available:
            break
        case .absent(let why):
            // No GPU for this engine: like a machine with no GPU engine, the CPU is all there is (plan xp-c, X-C4).
            return Selection(evaluator: cpu, warning: nil, diagnostic: "no GPU engine: \(why)")
        case .broken(let why):
            // A GPU engine that should run and cannot: a broken install or driver the person should hear about.
            return Selection(evaluator: cpu, warning: cpuWarning, diagnostic: "the GPU engine cannot run: \(why)")
        }
```
and in `Selection.warning`'s and `diagnostic`'s doc comments add "or the engine is broken (`ImplicitEngineAvailability.broken`)" and "or why the engine is absent or broken".

In `Tests/CreatorAppTests/Bench/ImplicitBench.swift`, replace the body of `static func meshesMade() async -> Int?` with `await ImplicitGPUEngines.meshesMade()` and its doc comment's "the platform's Metal engine" with "the platform's GPU engine".

In `Support/GPUEnginesUnderTest.swift` change `#if canImport(MetalUISDLGPU) && false` back to `#if canImport(MetalUISDLGPU)`.

- [ ] **Step 6: Run on the Mac, then on Linux.**

Run:
```bash
swift test --filter CreatorImplicitTests 2>&1 | grep -E "Test run with|recorded an issue"     # one line, no issue
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter CreatorImplicitTests 2>&1 | tail -3
```
Expected: both PASS. On Linux `GPUAgreementTests` now runs on "Vulkan" (lavapipe), `SDLComputeBackendTests` and `ImplicitGPUAvailabilityTests` pass with `XP_REQUIRE_GPU=1`. Note the Linux `CreatorImplicitTests` wall time from the log (it is task 6's budget question: the meshing suites add more).

Then the whole Linux suite, because `.automatic` now means the GPU there: `XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh all` — PASS, 12 lines. A test elsewhere that asserted `engineName == "CPU"` under `.automatic` on Linux is wrong now: it should pass its engine explicitly (`engine: nil` for the CPU), as macOS's tests already must.

- [ ] **Step 7: Lint, commit, and read the Windows CI.**

```bash
swiftlint lint --strict
git add Package.swift Sources/CreatorImplicit Tests/CreatorImplicitTests Tests/CreatorAppTests/Bench/ImplicitBench.swift
git commit -m "feat(implicit): the SDL_GPU compute backend is Linux's and Windows' implicit engine; absent or broken engines fall back (xp-c task 4)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
git push origin xp-c
```
Then read the Windows job of `.github/workflows/xp.yml` for this commit (`gh run list --branch xp-c`, `gh run view <id> --log`): the debug build, the test step (12 lines; `GPUAgreementTests` on "Direct3D 12" over WARP) and **"Build release (for the zip)"** must pass. A Windows-only compiler crash in an `async` loop of `InterpretedImplicitEngine` is the Global Constraints' rule (1) or (3): apply the remedy there and push again.

---

### Task 5: Meshing on the interpreted engine: the six meshing kernels, the engine's steps, and the canonical order

**Files:**
- Create: `Shaders/implicit/mesh_common.hlsli`, `mesh_cubes.hlsli`, `mesh_lattice.hlsli`, `mesh_clear.comp.hlsl`, `mesh_sample.comp.hlsl`, `mesh_classify.comp.hlsl`, `mesh_number.comp.hlsl`, `mesh_place.comp.hlsl`, `mesh_emit.comp.hlsl`
- Create: `Sources/CreatorImplicit/Compute/RadixSort.swift`, `MeshCanonicalOrder.swift`, `InterpretedMeshJob.swift`
- Modify: `Sources/CreatorImplicit/Compute/InterpretedImplicitEngine+Meshing.swift` (task 3's placeholder becomes the meshing)
- Test: `Tests/CreatorImplicitTests/MeshCanonicalOrderTests.swift`, `Tests/CreatorImplicitTests/InterpretedMeshingTests.swift`

**Interfaces:**
- Consumes: `InterpretedImplicitEngine.backend()`, `.buffers(for:on:)`, `.epoch`, `Prepared` (task 3); `BrickLattice`, `BrickMeshRequest`, `BrickMesh`, `MarchingCubesBuffers.words`, `ImplicitMeshShaderLibrary.Counter` (7c-1g).
- Produces:
  - `InterpretedImplicitEngine.meshBricks(_:_:progress:)` (the `ImplicitGPUEngine` requirement), `struct MeshTuning { batchBricks = 1024, slotsPerBrick = 256, largestTable = 1 << 25, slotsPerDispatch = 1 << 18, afterBatch }`, `func tune(_:)`, `static let largestBrickCount = Int(UInt32.max) / 512`.
  - `enum RadixSort { static func order(of keys: [UInt32]) -> [UInt32] }` (stable, ascending).
  - `enum MeshCanonicalOrder { static func mesh(positions:normals:keys:triangles:tags:) -> BrickMesh }`.

- [ ] **Step 1: Write the failing tests.**

`Tests/CreatorImplicitTests/MeshCanonicalOrderTests.swift` (portable, no GPU):
```swift
import Testing
@testable import CreatorImplicit

/// The order the interpreted engine gives a mesh (plan xp-c, X-C3): whatever order the GPU's threads made it in, the arrays that come out are the
/// same.
struct MeshCanonicalOrderTests {
    @Test func theRadixSortIsAStableAscendingOrder() {
        let keys: [UInt32] = [7, 0xFFFF_FFFF, 3, 7, 0, 256, 3, 65_536]
        let order = RadixSort.order(of: keys)
        #expect(order.map { keys[Int($0)] } == keys.sorted())
        #expect(order == [4, 2, 6, 0, 3, 5, 7, 1], "equal keys keep their order")
        #expect(RadixSort.order(of: []).isEmpty)
    }

    /// A mesh, and the same mesh with its vertices renumbered and its cubes' triangle blocks shuffled as a GPU's atomics would: one canonical mesh.
    @Test(arguments: [1, 2, 3, 4, 5])
    func aShuffledMeshComesOutAsTheSameArrays(_ seed: Int) {
        // Three cubes (tags 10, 11, 40); the second made two triangles. Vertex keys are the edge keys.
        let keys: [UInt32] = [30, 12, 99, 51, 7, 64]
        let positions = keys.map { SIMD3<Float>(Float($0), 0, 0) }
        let normals = keys.map { _ in SIMD3<Float>(0, 0, 1) }
        let triangles: [UInt32] = [0, 1, 2, 3, 4, 5, 5, 4, 1, 2, 3, 0]
        let tags: [UInt32] = [10, 11, 11, 40]
        let reference = MeshCanonicalOrder.mesh(positions: positions, normals: normals, keys: keys, triangles: triangles, tags: tags)

        let random = SeededRandom(seed: seed, stream: 0)
        let renumber = (0..<keys.count).sorted { random.unit(at: $0) < random.unit(at: $1) }   // new index of old vertex v is renumber.firstIndex(of: v)
        var newOf = [Int](repeating: 0, count: keys.count)
        for (new, old) in renumber.enumerated() { newOf[old] = new }
        let blocks: [[Int]] = [[0], [1, 2], [3]].sorted { random.unit(at: 10 + $0[0]) < random.unit(at: 10 + $1[0]) }
        var shuffledTriangles: [UInt32] = []
        var shuffledTags: [UInt32] = []
        for block in blocks {
            for triangle in block {
                shuffledTriangles += (0..<3).map { UInt32(newOf[Int(triangles[triangle * 3 + $0])]) }
                shuffledTags.append(tags[triangle])
            }
        }
        let shuffled = MeshCanonicalOrder.mesh(positions: renumber.map { positions[$0] }, normals: renumber.map { normals[$0] },
                                               keys: renumber.map { keys[$0] }, triangles: shuffledTriangles, tags: shuffledTags)
        #expect(shuffled == reference)
        #expect(reference.positions.map(\.x) == keys.sorted().map(Float.init), "vertices by edge key")
        #expect(reference.isConsistent)
    }
}
```
`SeededRandom(seed:stream:)` (`Sources/CreatorGeometry/Random/SeededRandom.swift`) takes an `Int` seed.

`Tests/CreatorImplicitTests/InterpretedMeshingTests.swift` (the basics here; task 6 adds the limits):
```swift
import CreatorGeometry
import Synchronization
import Testing
@testable import CreatorImplicit

/// Meshing on the interpreted engine (plan xp-c; implicit spec Errata D13, D21): the basics of what comes back, and that it comes back the same
/// every time. Its agreement with the CPU mesher is `GPUMeshAgreementTests`. Skipped, by name, where the engine has no backend.
@Suite(.enabled(if: GPUEnginesUnderTest.interpreted != nil, "needs the interpreted engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct InterpretedMeshingTests {
    static func request(_ solid: ImplicitSolid, resolution: Double, snap: Bool = true) async throws -> BrickMeshRequest {
        BrickMeshRequest(plan: try await BrickPlan.build(for: solid, resolution: resolution, using: CPUBatchEvaluator(solid)), snap: snap)
    }

    @Test func aSphereMeshedOnTheInterpreterIsAClosedManifoldWithTheRightVolume() async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        let solid = ImplicitSolid.sphere(radius: 10)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == engine.name)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator).meshReportingPath(solid, resolution: 0.53, quality: .export)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 1000
        #expect(abs(mesh.signedVolume - exact) / exact < 0.005, "volume \(mesh.signedVolume) against \(exact)")
        #expect(mesh.normals.count == mesh.positions.count && mesh.normals.allSatisfy { abs(($0 * $0).sum() - 1) < 1e-4 })
    }

    @Test func withoutTheSnapTheNormalsAreZeroAndTheVerticesAreOnTheLattice() async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        let solid = ImplicitFixtures.sphere
        let program = try await engine.compile(solid)
        let request = try await Self.request(solid, resolution: 0.53, snap: false)
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

    /// The same request meshes to the same arrays every time (X-C3), so an export made twice has the same bytes (Review Focus 6).
    @Test func theSameRequestMeshesToTheSameArraysEveryTime() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeInterpreted())
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.batchBricks = 3
        tuning.slotsPerDispatch = 1_000
        await engine.tune(tuning)
        let solid = try #require(GPUFixtures.all.first { $0.name == "smooth union" }?.solid)
        let program = try await engine.compile(solid)
        let request = try await Self.request(solid, resolution: 0.53)
        let first = try await engine.meshBricks(program, request) { _ in }
        for _ in 0..<3 {
            #expect(try await engine.meshBricks(program, request) { _ in } == first)
        }
        await engine.tune(InterpretedImplicitEngine.MeshTuning())
        #expect(try await engine.meshBricks(program, request) { _ in } == first, "the batch sizes do not change the arrays")
    }

    @Test func progressRunsFromZeroToNearlyOneInOrder() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeInterpreted())
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.batchBricks = 2
        await engine.tune(tuning)
        let program = try await engine.compile(ImplicitFixtures.sphere)
        let request = try await Self.request(ImplicitFixtures.sphere, resolution: 0.53)
        let seen = Mutex<[Double]>([])
        _ = try await engine.meshBricks(program, request) { fraction in seen.withLock { $0.append(fraction) } }
        let fractions = seen.withLock { $0 }
        #expect(!fractions.isEmpty && fractions == fractions.sorted() && fractions.allSatisfy { (0...1).contains($0) })
        #expect(await engine.meshesMade == 1)
    }
}
```

- [ ] **Step 2: Run them to see them fail.**

Run: `swift test --filter "CreatorImplicitTests.(MeshCanonicalOrderTests|InterpretedMeshingTests)" 2>&1 | tail -5`
Expected: build failure ("cannot find 'MeshCanonicalOrder' in scope").

- [ ] **Step 3: Write the canonical order.**

`Sources/CreatorImplicit/Compute/RadixSort.swift`:
```swift
/// A stable least-significant-digit radix sort of 32-bit keys, in four passes of eight bits (plan xp-c, X-C3): O(n), which a 2-million-triangle
/// preview needs.
enum RadixSort {
    /// The indices of `keys` in ascending order of key; equal keys keep their order.
    static func order(of keys: [UInt32]) -> [UInt32] {
        var order = Array(0..<UInt32(keys.count))
        var scratch = order
        for shift in stride(from: UInt32(0), to: 32, by: 8) {
            var counts = [Int](repeating: 0, count: 257)
            for index in order { counts[Int((keys[Int(index)] >> shift) & 0xFF) + 1] += 1 }
            for bucket in 1..<257 { counts[bucket] += counts[bucket - 1] }
            for index in order {
                let bucket = Int((keys[Int(index)] >> shift) & 0xFF)
                scratch[counts[bucket]] = index
                counts[bucket] += 1
            }
            swap(&order, &scratch)
        }
        return order
    }
}
```

`Sources/CreatorImplicit/Compute/MeshCanonicalOrder.swift`:
```swift
/// The order the interpreted engine gives a mesh (plan xp-c, user decision X-C3; implicit spec erratum D21). The GPU numbers vertices and places
/// triangles in whatever order its threads run; this puts them in one order that depends only on the mesh: vertices by their lattice edge's key,
/// triangles by the cube that made them (`tag`: the brick's place in the request × 512 + the cube) and, within a cube, as the marching-cubes table
/// lists them (a cube's triangles are written together, in table order). So a request meshes to the same arrays run after run.
enum MeshCanonicalOrder {
    /// `positions`, `normals` and `keys` per vertex as the GPU numbered them; `triangles`, three indices each, and `tags`, one each, as it placed them.
    static func mesh(positions: [SIMD3<Float>], normals: [SIMD3<Float>], keys: [UInt32], triangles: [UInt32], tags: [UInt32]) -> BrickMesh {
        let vertexOrder = RadixSort.order(of: keys)
        var renumbered = [UInt32](repeating: 0, count: keys.count)
        for (new, old) in vertexOrder.enumerated() { renumbered[Int(old)] = UInt32(new) }
        let triangleOrder = RadixSort.order(of: tags)
        var indices: [UInt32] = []
        indices.reserveCapacity(triangles.count)
        for old in triangleOrder {
            let base = Int(old) * 3
            indices.append(renumbered[Int(triangles[base])])
            indices.append(renumbered[Int(triangles[base + 1])])
            indices.append(renumbered[Int(triangles[base + 2])])
        }
        return BrickMesh(positions: vertexOrder.map { positions[Int($0)] }, normals: vertexOrder.map { normals[Int($0)] }, triangles: indices)
    }
}
```

Run: `swift test --filter CreatorImplicitTests.MeshCanonicalOrderTests 2>&1 | tail -3` — PASS (the suite needs only these two files; if the build stops on `InterpretedMeshingTests`, comment that file's suite out until step 6 and say so in the commit).

- [ ] **Step 4: Write the meshing kernels.**

`Shaders/implicit/mesh_common.hlsli`:
```hlsl
// The edge table's hash and the lattice edge key every meshing kernel shares (ImplicitMeshShaderLibrary's tableHash and edgeKey, BrickLattice's
// numbering). Needs contract.hlsli.
#ifndef IMPLICIT_MESH_COMMON
#define IMPLICIT_MESH_COMMON

uint tableHash(uint key, uint mask) {
    uint h = key * 0x9E3779B1u;
    h ^= h >> 16;
    h *= 0x85EBCA6Bu;
    h ^= h >> 13;
    return h & mask;
}

// The key of the edge between corners a and b of the cube whose lowest lattice point is (x, y, z): the CPU's formula.
uint edgeKeyOf(uint x, uint y, uint z, uint a, uint b) {
    uint lx = x + (a & 1u), ly = y + ((a >> 1) & 1u), lz = z + ((a >> 2) & 1u);
    uint axis = ((a ^ b) == 1u) ? 0u : (((a ^ b) == 2u) ? 1u : 2u);
    return ((lz * gNY + ly) * gNX + lx) * 3u + axis;
}

#endif
```

`Shaders/implicit/mesh_cubes.hlsli`:
```hlsl
// A cube's corners and pattern from a batch's samples. The kernel declares `samples` before it includes this.
#ifndef IMPLICIT_MESH_CUBES
#define IMPLICIT_MESH_CUBES

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

#endif
```

`Shaders/implicit/mesh_lattice.hlsli`:
```hlsl
// A lattice point's world position, read from the CPU's coordinates (BrickLattice.axisCoordinates). The kernel declares `axes` before it includes this.
#ifndef IMPLICIT_MESH_LATTICE
#define IMPLICIT_MESH_LATTICE

float3 latticePoint(uint x, uint y, uint z) {
    return float3(axes[x], axes[gNX + y], axes[gNX + gNY + z]);
}

#endif
```

`Shaders/implicit/mesh_clear.comp.hlsl`:
```hlsl
// Empties the edge table over slots gFirstSlot ..< gFirstSlot + gCount: SDL_GPU has no buffer fill (Metal's engine blits 0xFF).
#include "contract.hlsli"

RWStructuredBuffer<uint> keys : register(u0, space1);

[numthreads(THREADS, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint slot = gFirstSlot + id.x;
    if (id.x >= gCount || slot > gMask) { return; }
    keys[slot] = EMPTY_KEY;
}
```

`Shaders/implicit/mesh_sample.comp.hlsl`:
```hlsl
// Step 1 of a mesh (ImplicitMeshShaderLibrary's meshSample): the solid's value at every lattice point of a batch of bricks, at the CPU's coordinates.
#include "contract.hlsli"

StructuredBuffer<uint> bricks : register(t0, space0);
StructuredBuffer<float> axes : register(t1, space0);
StructuredBuffer<int> program : register(t2, space0);
StructuredBuffer<float> floats : register(t3, space0);
StructuredBuffer<int> ints : register(t4, space0);
RWStructuredBuffer<float> samples : register(u0, space1);

#include "accurate_math.hlsli"
#include "wide_integer.hlsli"
#include "library.hlsli"
#include "lattices.hlsli"
#include "interpreter.hlsli"
#include "mesh_lattice.hlsli"

[numthreads(THREADS, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint gid = id.x;
    if (gid >= gBrickCount * POINTS) { return; }
    uint b = gid / POINTS, r = gid % POINTS;
    uint x = r % SIDE, y = (r / SIDE) % SIDE, z = r / (SIDE * SIDE);
    uint at = (gFirstBrick + b) * 3u;
    samples[gid] = sdf(latticePoint(bricks[at] * BRICK + x, bricks[at + 1u] * BRICK + y, bricks[at + 2u] * BRICK + z));
}
```

`Shaders/implicit/mesh_classify.comp.hlsl`:
```hlsl
// Step 2 (meshClassify): each cube's pattern; its triangles added to the total; a table slot claimed for each lattice edge it crosses, by compare and
// swap on the key, so an edge shared by four cubes, or by two bricks, is one slot.
#include "contract.hlsli"

StructuredBuffer<uint> bricks : register(t0, space0);
StructuredBuffer<float> samples : register(t1, space0);
StructuredBuffer<uint> cubeTable : register(t2, space0);
RWStructuredBuffer<uint> keys : register(u0, space1);
RWStructuredBuffer<uint> counters : register(u1, space1);

#include "mesh_common.hlsli"
#include "mesh_cubes.hlsli"

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

[numthreads(THREADS, 1, 1)]
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
```

`Shaders/implicit/mesh_number.comp.hlsl`:
```hlsl
// Step 3 (meshNumber): each occupied slot's vertex number, from an atomic counter (the canonical order is made on the CPU afterwards).
#include "contract.hlsli"

StructuredBuffer<uint> keys : register(t0, space0);
RWStructuredBuffer<uint> slotVertex : register(u0, space1);
RWStructuredBuffer<uint> counters : register(u1, space1);

[numthreads(THREADS, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint slot = gFirstSlot + id.x;
    if (id.x >= gCount || slot > gMask || keys[slot] == EMPTY_KEY) { return; }
    uint number;
    InterlockedAdd(counters[COUNTER_VERTICES], 1u, number);
    slotVertex[slot] = number;
}
```

`Shaders/implicit/mesh_place.comp.hlsl`:
```hlsl
// Step 4 (meshPlace): the vertex on each slot's edge by linear interpolation, then the Newton step and the normal (ImplicitMesher.snap); its
// position and its edge key together (the key orders the vertices on the CPU).
#include "contract.hlsli"

StructuredBuffer<float> axes : register(t0, space0);
StructuredBuffer<int> program : register(t1, space0);
StructuredBuffer<float> floats : register(t2, space0);
StructuredBuffer<int> ints : register(t3, space0);
StructuredBuffer<uint> keys : register(t4, space0);
StructuredBuffer<uint> slotVertex : register(t5, space0);
RWStructuredBuffer<uint4> positions : register(u0, space1);
RWStructuredBuffer<float4> normals : register(u1, space1);

#include "accurate_math.hlsli"
#include "wide_integer.hlsli"
#include "library.hlsli"
#include "lattices.hlsli"
#include "interpreter.hlsli"
#include "mesh_lattice.hlsli"

[numthreads(THREADS, 1, 1)]
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
    uint number = slotVertex[slot];
    positions[number] = uint4(asuint(position), key);
    normals[number] = float4(normal, 0.0f);
}
```

`Shaders/implicit/mesh_emit.comp.hlsl`:
```hlsl
// Step 5 (meshEmit): each cube's triangles, each corner the vertex of its edge's slot, at a place in the index buffer taken from an atomic cursor;
// one tag a triangle (the brick's place in the request x 512 + the cube) orders them on the CPU.
#include "contract.hlsli"

StructuredBuffer<uint> bricks : register(t0, space0);
StructuredBuffer<float> samples : register(t1, space0);
StructuredBuffer<uint> cubeTable : register(t2, space0);
StructuredBuffer<uint> keys : register(t3, space0);
StructuredBuffer<uint> slotVertex : register(t4, space0);
RWStructuredBuffer<uint> counters : register(u0, space1);
RWStructuredBuffer<uint> indices : register(u1, space1);
RWStructuredBuffer<uint> tags : register(u2, space1);

#include "mesh_common.hlsli"
#include "mesh_cubes.hlsli"

uint vertexOfKey(uint key) {
    uint slot = tableHash(key, gMask);
    for (uint probe = 0u; probe <= gMask; ++probe) {
        if (keys[slot] == key) { return slotVertex[slot]; }
        slot = (slot + 1u) & gMask;
    }
    return 0u;
}

[numthreads(THREADS, 1, 1)]
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
    uint triangles = (end - begin) / 3u;
    uint place;
    InterlockedAdd(counters[COUNTER_TRIANGLE_CURSOR], triangles, place);
    for (uint corner = 0u; corner < end - begin; ++corner) {
        uint edge = cubeTable[CUBE_EDGES + begin + corner];
        indices[place * 3u + corner] = vertexOfKey(edgeKeyOf(lx, ly, lz, cubeTable[CUBE_LOWER + edge], cubeTable[CUBE_UPPER + edge]));
    }
    uint tag = (gFirstBrick + b) * CUBES + c;
    for (uint t = 0u; t < triangles; ++t) { tags[place + t] = tag; }
}
```
These are line-for-line ports of `ImplicitMeshShaderLibrary.kernels`; compare them with that text before compiling. The differences are deliberate: `gCount` guards (SDL dispatches whole groups of 64, Metal exact counts), a strong compare-and-swap (HLSL's `InterlockedCompareExchange` cannot fail spuriously, so the weak CAS's retry branch is gone), the key beside the position, and the tags.

Run `XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh shaders` and `swift test --filter CreatorImplicitTests.ImplicitShaderContractTests`: every kernel now has a source, so `eachKernelDeclaresItsBuffersInOrder` and the reflection check cover all seven. PASS.

- [ ] **Step 5: Write the engine's meshing.**

`Sources/CreatorImplicit/Compute/InterpretedMeshJob.swift`:
```swift
/// What one interpreted mesh works with (plan xp-c), and the synchronous builders of its batches: the async engine methods only run them.
struct InterpretedMeshJob: Sendable {
    var solid: InterpretedImplicitEngine.Prepared
    var bricks: any ComputeBuffer
    var axes: any ComputeBuffer
    var cube: any ComputeBuffer
    var parameters: KernelParameters
    var brickCount: Int
    var started: Int
    var tuning: InterpretedImplicitEngine.MeshTuning
}

/// One attempt at one table size.
struct InterpretedMeshRun: Sendable {
    var job: InterpretedMeshJob
    var samples: any ComputeBuffer
    var keys: any ComputeBuffer
    var slotVertex: any ComputeBuffer
    var counters: any ComputeBuffer
    var output: InterpretedMeshOutput?
    let slots: Int

    init(_ job: InterpretedMeshJob, slots: Int, on backend: any ImplicitComputeBackend) throws {
        self.job = job
        self.slots = slots
        samples = try backend.makeBuffer(length: job.tuning.batchBricks * 729 * 4)
        keys = try backend.makeBuffer(length: slots * 4)
        slotVertex = try backend.makeBuffer(length: slots * 4)
        counters = try backend.makeBuffer(length: ImplicitMeshShaderLibrary.Counter.count * 4)
        self.job.parameters.mask = UInt32(slots - 1)
    }

    /// The counters zeroed and the table emptied, in ranges of at most 2^20 slots.
    func clearing() -> ComputeBatch {
        var batch = ComputeBatch(uploads: [ComputeUpload(bytes: [UInt8](repeating: 0, count: ImplicitMeshShaderLibrary.Counter.count * 4),
                                                         buffer: counters)])
        for range in ComputeBytes.ranges(count: slots, size: 1 << 20) {
            var parameters = job.parameters
            (parameters.firstSlot, parameters.count) = (UInt32(range.lowerBound), UInt32(range.count))
            batch.dispatches.append(ComputeDispatch(kernel: .clear, parameters: parameters, readOnly: [], readWrite: [keys], threads: range.count))
        }
        return batch
    }

    /// Steps 1 and 2 (or 1 and 5) for one batch of bricks: sample, then classify or emit, each in its own pass.
    func brickBatch(_ range: Range<Int>, emitting: Bool) -> ComputeBatch {
        var parameters = job.parameters
        (parameters.firstBrick, parameters.brickCount) = (UInt32(range.lowerBound), UInt32(range.count))
        let solid = job.solid
        let sample = ComputeDispatch(kernel: .sample, parameters: parameters, readOnly: [job.bricks, job.axes, solid.program, solid.floats, solid.ints],
                                     readWrite: [samples], threads: range.count * 729)
        guard emitting, let output else {
            return ComputeBatch(dispatches: [sample, ComputeDispatch(kernel: .classify, parameters: parameters, readOnly: [job.bricks, samples, job.cube],
                                                                     readWrite: [keys, counters], threads: range.count * 512)])
        }
        return ComputeBatch(dispatches: [sample, ComputeDispatch(kernel: .emit, parameters: parameters,
                                                                 readOnly: [job.bricks, samples, job.cube, keys, slotVertex],
                                                                 readWrite: [counters, output.indices, output.tags], threads: range.count * 512)])
    }

    /// Step 3 or 4 over one range of table slots.
    func slotBatch(_ range: Range<Int>, _ kernel: ImplicitKernel) -> ComputeBatch {
        var parameters = job.parameters
        (parameters.firstSlot, parameters.count) = (UInt32(range.lowerBound), UInt32(range.count))
        let solid = job.solid
        let dispatch = switch kernel {
        case .place:
            ComputeDispatch(kernel: .place, parameters: parameters, readOnly: [job.axes, solid.program, solid.floats, solid.ints, keys, slotVertex],
                            readWrite: [output?.positions ?? keys, output?.normals ?? keys], threads: range.count)
        default:
            ComputeDispatch(kernel: .number, parameters: parameters, readOnly: [keys], readWrite: [slotVertex, counters], threads: range.count)
        }
        return ComputeBatch(dispatches: [dispatch])
    }

    func readingCounters() -> ComputeBatch {
        ComputeBatch(downloads: [ComputeDownload(buffer: counters, length: ImplicitMeshShaderLibrary.Counter.count * 4)])
    }
}

/// The buffers the mesh is written into, made once the counts are known.
struct InterpretedMeshOutput: Sendable {
    let vertices: Int
    let triangles: Int
    let positions: any ComputeBuffer
    let normals: any ComputeBuffer
    let indices: any ComputeBuffer
    let tags: any ComputeBuffer

    /// Throws `.unsupported` past the backend's largest buffer: that request is the CPU mesher's.
    init(vertices: Int, triangles: Int, on backend: any ImplicitComputeBackend) throws {
        self.vertices = vertices
        self.triangles = triangles
        positions = try backend.makeBuffer(length: vertices * 16)
        normals = try backend.makeBuffer(length: vertices * 16)
        indices = try backend.makeBuffer(length: triangles * 12)
        tags = try backend.makeBuffer(length: triangles * 4)
    }

    func reading(_ counters: any ComputeBuffer) -> ComputeBatch {
        ComputeBatch(downloads: [
            ComputeDownload(buffer: counters, length: ImplicitMeshShaderLibrary.Counter.count * 4),
            ComputeDownload(buffer: positions, length: vertices * 16), ComputeDownload(buffer: normals, length: vertices * 16),
            ComputeDownload(buffer: indices, length: triangles * 12), ComputeDownload(buffer: tags, length: triangles * 4),
        ])
    }

    /// The mesh from what `reading` brought back, in the canonical order; throws when the GPU emitted another count than it counted.
    func mesh(from read: [[UInt8]]) throws -> BrickMesh {
        let counters = ComputeBytes.values(read[0], as: UInt32.self)
        guard counters[ImplicitMeshShaderLibrary.Counter.triangleCursor] == UInt32(triangles) else {
            throw ImplicitCompileError.engine("the GPU emitted a different number of triangles than it counted")
        }
        let placed = ComputeBytes.values(read[1], as: UInt32.self)
        let normalWords = ComputeBytes.values(read[2], as: Float.self)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var keys: [UInt32] = []
        positions.reserveCapacity(vertices)
        normals.reserveCapacity(vertices)
        keys.reserveCapacity(vertices)
        for vertex in 0..<vertices {
            let at = vertex * 4
            positions.append(SIMD3(Float(bitPattern: placed[at]), Float(bitPattern: placed[at + 1]), Float(bitPattern: placed[at + 2])))
            keys.append(placed[at + 3])
            normals.append(SIMD3(normalWords[at], normalWords[at + 1], normalWords[at + 2]))
        }
        return MeshCanonicalOrder.mesh(positions: positions, normals: normals, keys: keys, triangles: ComputeBytes.values(read[3], as: UInt32.self),
                                       tags: ComputeBytes.values(read[4], as: UInt32.self))
    }
}
```
The `place` case's `?? keys` fallbacks are never taken (the engine makes `output` before step 4); they keep the builder total without a force unwrap.

Replace `Sources/CreatorImplicit/Compute/InterpretedImplicitEngine+Meshing.swift` with:
```swift
/// Marching cubes on the interpreted engine (implicit spec §4.3, Errata D13, D21; plan xp-c): the seven kernels of `Shaders/implicit` over the
/// bricks of a `BrickMeshRequest`, the same algorithm and table as the CPU mesher and `MetalImplicitEngine+Meshing`, one batch per brick batch or
/// table range so a cancel ends a mesh between them and no batch runs long enough for a GPU watchdog. The batches are built synchronously
/// (`InterpretedMeshRun`); the methods here only run them (the Windows Swift 6.4 rules in the plan's Global Constraints).
extension InterpretedImplicitEngine {
    /// The sizes meshing works in. The defaults are the engine's; the tests turn them down to reach the paths a small mesh never takes.
    struct MeshTuning: Sendable {
        /// Bricks sampled and meshed in one batch (Metal's is 4,096; an interpreted `sdf` costs more).
        var batchBricks = 1024
        /// The first table has this many slots for each brick; a table that proves too small is doubled.
        var slotsPerBrick = 256
        /// The most slots a table gets (4 bytes each: 2^25 is the 128 MiB buffer cap, gap XP-G24); a mesh needing more is the CPU's.
        var largestTable = 1 << 25
        /// Table slots one batch numbers or places (a slot costs up to nine evaluations of the solid).
        var slotsPerDispatch = 1 << 18
        /// Called with the number of the batch just run (from 1), before the check for a cancel: the tests cancel from it. Nothing in the engine sets it.
        var afterBatch: (@Sendable (Int) async -> Void)?
    }

    /// A request of this many bricks or more is the CPU's: a triangle's tag is the brick's place × 512 + the cube, in 32 bits.
    static let largestBrickCount = Int(UInt32.max) / 512

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
        guard request.bricks.count < Self.largestBrickCount else {
            throw ImplicitCompileError.unsupported("more bricks than a 32-bit triangle tag numbers")
        }
        let backend = try backend()
        let job = try await startJob(program, request, lattice, on: backend)
        let largest = min(job.tuning.largestTable, backend.largestBuffer / 4)
        var slots = Self.firstTableSize(bricks: request.bricks.count, slotsPerBrick: job.tuning.slotsPerBrick)
        while true {
            guard slots <= largest else { throw ImplicitCompileError.unsupported("the edge table would pass \(largest) slots") }
            if let mesh = try await attempt(job, slots: slots, on: backend, progress: progress) {
                meshesMade += 1
                return mesh
            }
            slots *= 2
        }
    }

    /// The smallest power of two of at least 4,096 slots and `slotsPerBrick` a brick (`MetalImplicitEngine`'s rule).
    static func firstTableSize(bricks: Int, slotsPerBrick: Int) -> Int {
        1 << max(12, Int.bitWidth - (bricks * slotsPerBrick - 1).leadingZeroBitCount)
    }

    private func startJob(_ program: CompiledImplicit, _ request: BrickMeshRequest, _ lattice: BrickLattice,
                          on backend: any ImplicitComputeBackend) async throws -> InterpretedMeshJob {
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
        return InterpretedMeshJob(solid: solid, bricks: bricks, axes: axes, cube: cube, parameters: parameters, brickCount: request.bricks.count,
                                  started: epoch, tuning: meshTuning)
    }

    /// One run of the steps with a table of `slots`; `nil` when the table proved too small.
    @_optimize(none) // Windows Swift 6.4 release: takes the progress closure; see `meshBricks`.
    private func attempt(_ job: InterpretedMeshJob, slots: Int, on backend: any ImplicitComputeBackend,
                         progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        var run = try InterpretedMeshRun(job, slots: slots, on: backend)
        _ = try await backend.run(run.clearing())
        try await sweep(run, emitting: false, from: 0, to: 0.4, on: backend, progress: progress)
        var counts = ComputeBytes.values(try await backend.run(run.readingCounters())[0], as: UInt32.self)
        if counts[ImplicitMeshShaderLibrary.Counter.overflow] != 0 { return nil }
        let triangles = Int(counts[ImplicitMeshShaderLibrary.Counter.triangleTotal])
        try await sweepSlots(run, .number, on: backend)
        counts = ComputeBytes.values(try await backend.run(run.readingCounters())[0], as: UInt32.self)
        let vertices = Int(counts[ImplicitMeshShaderLibrary.Counter.vertices])
        guard vertices > 0, triangles > 0 else { return BrickMesh(positions: [], normals: [], triangles: []) }
        run.output = try InterpretedMeshOutput(vertices: vertices, triangles: triangles, on: backend)
        try await sweepSlots(run, .place, on: backend)
        progress(0.55)
        try await sweep(run, emitting: true, from: 0.55, to: 0.95, on: backend, progress: progress)
        guard let output = run.output else { return nil }
        return try output.mesh(from: try await backend.run(output.reading(run.counters)))
    }

    /// Every batch of bricks: sample, then classify (or emit); progress runs `from` to `to`.
    @_optimize(none) // Windows Swift 6.4 release: takes the progress closure; see `meshBricks`.
    private func sweep(_ run: InterpretedMeshRun, emitting: Bool, from: Double, to: Double, on backend: any ImplicitComputeBackend,
                       progress: @Sendable (Double) -> Void) async throws {
        let batches = ComputeBytes.ranges(count: run.job.brickCount, size: run.job.tuning.batchBricks)
        for index in batches.indices {
            _ = try await backend.run(run.brickBatch(batches[index], emitting: emitting))
            await run.job.tuning.afterBatch?(index + 1)
            try checkRunning(run.job)
            progress(from + (to - from) * Double(batches[index].upperBound) / Double(run.job.brickCount))
        }
    }

    /// Step 3 or 4 over the whole table, `slotsPerDispatch` slots a batch.
    private func sweepSlots(_ run: InterpretedMeshRun, _ kernel: ImplicitKernel, on backend: any ImplicitComputeBackend) async throws {
        let ranges = ComputeBytes.ranges(count: run.slots, size: run.job.tuning.slotsPerDispatch)
        for index in ranges.indices {
            _ = try await backend.run(run.slotBatch(ranges[index], kernel))
            try checkRunning(run.job)
        }
    }

    private func checkRunning(_ job: InterpretedMeshJob) throws {
        try Task.checkCancellation()
        if epoch != job.started { throw CancellationError() }
    }
}
```

- [ ] **Step 6: Run on the Mac and on Linux.**

Run:
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh shaders
swift test --filter "CreatorImplicitTests.(MeshCanonicalOrderTests|InterpretedMeshingTests|ImplicitShaderContractTests)" 2>&1 | tail -5
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter "InterpretedMeshingTests|MeshCanonicalOrderTests" 2>&1 | tail -3
```
Expected: PASS on both. A mesh that is not closed usually means a dispatch read another's output inside one pass (check that `SDLComputeRecording.record` begins a pass per dispatch) or a binding order wrong in one kernel (the contract test names it). `theSameRequestMeshesToTheSameArraysEveryTime` failing only on its last check means the batch size changed the tags: a tag must use `gFirstBrick + b`, the brick's place in the whole request.

- [ ] **Step 7: Asserts toolchain, lint, commit, push and read Windows CI.**

```bash
TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release 2>&1 | tail -3
swiftlint lint --strict
git add Shaders/implicit Sources/CreatorImplicit/Compute Tests/CreatorImplicitTests
git commit -m "feat(implicit): marching cubes on the interpreted engine, in a canonical order (xp-c task 5)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
git push origin xp-c
```
Then the Windows job, as in task 4 step 7 (the release build especially: `meshBricks`, `attempt` and `sweep` are the closure-taking `async` functions).

---

### Task 6: The mesh agreement and the limits, over every engine; the Face-mapped Voronoi item measured on the interpreter

**Files:**
- Modify (tests): `Tests/CreatorImplicitTests/GPUMeshAgreementTests.swift`, `Tests/CreatorImplicitTests/StreamingMesherGPUTests.swift` (both stop being Metal-only), `Tests/CreatorImplicitTests/InterpretedMeshingTests.swift` (the limits)

**Interfaces:**
- Consumes: `GPUEnginesUnderTest` (task 3), `InterpretedImplicitEngine.meshBricks`, `MeshTuning`, `tune(_:)` (task 5); the suites' existing helpers (`SamplesOnlyEvaluator`, `MeshComparison`, `GPUFixtures.meshAllowanceFactor`, `.singularSetAllowanceFactor`, `.nearSingularSet`, `ProgressLog`, `BrickMesh.triangleMesh`).
- Produces: the measured figures task 9's erratum D21 quotes (the interpreter's largest `worstScaledSurface` over D17's allowance on the Face-mapped Voronoi struts, and the slowest fixture's time on lavapipe).

- [ ] **Step 1: Make the mesh agreement suite run over every engine.**

In `GPUMeshAgreementTests.swift`:
- delete the first line `#if canImport(Metal)` and the last `#endif`;
- replace the suite attribute with `@Suite(.enabled(if: !GPUEnginesUnderTest.names.isEmpty, "needs a GPU engine: \(GPUEnginesUnderTest.unavailableReason)"))`;
- in the doc comment, after "meshed both ways.", add "Over every engine `GPUEnginesUnderTest.names` has: Metal, and the interpreted engine (plan xp-c) on the Mac's GPU, lavapipe or WARP, with the same tolerances.";
- give each of the three tests an engine argument and take the engine from it:

```swift
    @Test(arguments: GPUEnginesUnderTest.names, names)
    func theGPUMeshAgreesWithTheCPUMesh(_ engineName: String, _ name: String) async throws {
        let engine = try GPUEnginesUnderTest.engine(engineName)
        // … the body unchanged below this line, its messages prefixed "\(engineName), "
```
```swift
    @Test(arguments: GPUEnginesUnderTest.names, GPUFixtures.singularSetNames)
    func theGPUMeshAgreesAwayFromTheSingularSet(_ engineName: String, _ name: String) async throws {
        let engine = try GPUEnginesUnderTest.engine(engineName)
```
```swift
    @Test(arguments: GPUEnginesUnderTest.names, ["sphere", "box", "smooth union", "graded offset"])
    func withoutTheSnapTheVerticesStillAgreeAndTheNormalsAreZero(_ engineName: String, _ name: String) async throws {
        let engine = try GPUEnginesUnderTest.engine(engineName)
```
In each, the old first line `let engine = try #require(MetalImplicitEngine.shared)` is what these replace; `ImplicitEvaluators.make(for:choice:engine:)` already takes `engine`. Prefix every `#expect` message's `"\(name): …"` with `"\(engineName), \(name): …"` so a failure names its engine. The tolerances (`vertexTolerance`, `slideTolerance`, `slopeStep`, the normal dots, `volumeTolerance`, `triangleTolerance`) and the allowance factors are unchanged: the interpreter is held to exactly what Metal is (X-C6).

In `StreamingMesherGPUTests.swift` likewise: drop the `#if canImport(Metal)`/`#endif`, take the same suite attribute, and give both tests `(arguments: GPUEnginesUnderTest.names)` and an `_ engineName: String` parameter, with `ImplicitEvaluators.make(for: solid, choice: .automatic, engine: try GPUEnginesUnderTest.engine(engineName))` in place of `ImplicitEvaluators.make(for: solid, choice: .automatic)`.

- [ ] **Step 2: Write the interpreted engine's limit tests.**

Add to `InterpretedMeshingTests`:
```swift
    /// A fresh engine, tuned, and the program and request for a solid (the Metal suite's `Prepared`, for the interpreter).
    struct Job {
        let engine: InterpretedImplicitEngine
        let program: CompiledImplicit
        let request: BrickMeshRequest

        init(_ solid: ImplicitSolid = .sphere(radius: 10), resolution: Double = 0.53,
             tuning: InterpretedImplicitEngine.MeshTuning = InterpretedImplicitEngine.MeshTuning()) async throws {
            guard let engine = GPUEnginesUnderTest.makeInterpreted() else { throw ImplicitCompileError.engine("no interpreted engine") }
            await engine.tune(tuning)
            self.engine = engine
            program = try await engine.compile(solid)
            request = try await InterpretedMeshingTests.request(solid, resolution: resolution)
        }

        func mesh() async throws -> BrickMesh {
            try await engine.meshBricks(program, request) { _ in }
        }
    }

    /// With the canonical order, "the same mesh" is equality of the arrays, not of sets (Metal's tests compare sets).
    @Test func manySmallBatchesMakeTheMeshOneBigBatchDoes() async throws {
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.batchBricks = 7
        let small = try await Job(tuning: tuning)
        #expect(small.request.bricks.count > 50)
        #expect(try await small.mesh() == (try await Job().mesh()))
    }

    @Test func aTableThatIsTooSmallIsDoubledUntilItFits() async throws {
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        let mesh = try await Job(tuning: tuning).mesh()
        #expect(mesh.positions.count > 4096, "more vertices than the first table has slots")
        #expect(mesh == (try await Job().mesh()))
    }

    @Test func aMeshOfSeveralRangesOfSlotsIsTheMeshOneRangeMakes() async throws {
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.slotsPerDispatch = 1_000
        let ranges = try await Job(tuning: tuning).mesh()
        #expect(ranges.positions.count > 1_000 && ranges == (try await Job().mesh()))
    }

    /// Review Focus 3: past the largest table the request is the CPU mesher's, and the mesh is still made.
    @Test func aMeshBeyondTheLargestTableIsLeftToTheCPU() async throws {
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        tuning.largestTable = 4096
        let job = try await Job(tuning: tuning)
        await #expect(throws: ImplicitCompileError.self) { _ = try await job.mesh() }
        let (mesh, path) = try await ImplicitMesher(evaluator: GPUBatchEvaluator(engine: job.engine, program: job.program))
            .meshReportingPath(.sphere(radius: 10), resolution: 0.53, quality: .preview)
        #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
    }

    /// Review Focus 3: a table past the backend's 128 MiB buffer cap (2^25 slots, gap XP-G24) is unsupported before any GPU work, whatever
    /// `largestTable` allows, and the mesher then meshes on the CPU.
    @Test func aRequestPastTheBufferCapIsUnsupportedAndTheMesherFallsBack() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeInterpreted())
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.largestTable = 1 << 30
        tuning.slotsPerBrick = 1 << 25
        await engine.tune(tuning)
        let solid = ImplicitSolid.sphere(radius: 10)
        let program = try await engine.compile(solid)
        let request = BrickMeshRequest(origin: .zero, resolution: 0.5, bricks: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)], snap: true)
        await #expect(throws: ImplicitCompileError.unsupported("the edge table would pass \(1 << 25) slots")) {
            _ = try await engine.meshBricks(program, request) { _ in }
        }
        let (mesh, path) = try await ImplicitMesher(evaluator: GPUBatchEvaluator(engine: engine, program: program))
            .meshReportingPath(solid, resolution: 0.53, quality: .preview)
        #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
    }

    @Test func bricksTooFarApartForThirtyTwoBitKeysAreUnsupported() async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        let program = try await engine.compile(.sphere(radius: 10))
        let request = BrickMeshRequest(origin: .zero, resolution: 0.5, bricks: [SIMD3(0, 0, 0), SIMD3(1_200, 1_200, 1_200)], snap: true)
        await #expect(throws: ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")) {
            _ = try await engine.meshBricks(program, request) { _ in }
        }
    }

    @Test func aPartFarFromTheOriginIsMeshedInASmallWindow() async throws {
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        let move = RigidMove(origin: Vector3(4_000, -3_000, 2_500), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let far = ImplicitSolid.moved(.sphere(radius: 10), move)
        let selection = await ImplicitEvaluators.make(for: far, choice: .automatic, engine: engine)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator).meshReportingPath(far, resolution: 0.53, quality: .preview)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let bounds = try #require(mesh.bounds)
        #expect(abs(bounds.min.x - 3_990) < 1 && abs(bounds.max.z - 2_510) < 1)
    }

    /// A mesh of many small batches, so a cancel has somewhere to land between two of them.
    static func manyBatches() async throws -> Job {
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        let job = try await Job(.sphere(radius: 20), resolution: 0.4, tuning: tuning)
        #expect(job.request.bricks.count > 40, "ten batches or more")
        return job
    }

    static func expectTheNextMeshRuns(_ engine: InterpretedImplicitEngine) async throws {
        let small = try await request(.sphere(radius: 3), resolution: 0.5)
        let after = try await engine.meshBricks(try await engine.compile(.sphere(radius: 3)), small) { _ in }
        #expect(MeshTopology(after.triangleMesh).isClosedManifold)
    }

    /// Review Focus 4.
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
        #expect(seen.values.count == 1, "it ended at the next batch: \(seen.values.count) reports")
        try await Self.expectTheNextMeshRuns(job.engine)
    }

    /// Review Focus 4: an edit cancels the engine, which bumps its epoch.
    @Test func anEngineCancelEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        var tuning = InterpretedImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        tuning.afterBatch = { [engine = job.engine] batch in
            if batch == 1 { await engine.cancel() }
        }
        await job.engine.tune(tuning)
        let seen = ProgressLog()
        await #expect(throws: CancellationError.self) {
            _ = try await job.engine.meshBricks(job.program, job.request) { seen.append($0) }
        }
        #expect(seen.values.isEmpty, "the first batch's check ended it before its report")
        tuning.afterBatch = nil
        await job.engine.tune(tuning)
        try await Self.expectTheNextMeshRuns(job.engine)
    }
```
`ProgressLog` is the portable test helper `final class ProgressLog: Sendable` in `ImplicitMesherTests.swift`.

In `aRequestPastTheBufferCapIsUnsupportedAndTheMesherFallsBack` two adjacent bricks at 2^25 slots a brick ask for a first table of 2^26 slots; `largestTable` is raised to 2^30, so the cap that refuses is `backend.largestBuffer / 4` = 2^25, the buffer cap, before any batch runs.

- [ ] **Step 3: Run on the Mac, then on Linux, and measure.**

Run:
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh shaders
swift test --filter "CreatorImplicitTests.(GPUMeshAgreementTests|StreamingMesherGPUTests|InterpretedMeshingTests)" 2>&1 | tee .build/xp-c-mesh-mac.log | tail -5
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test --filter "GPUMeshAgreementTests|StreamingMesherGPUTests|InterpretedMeshingTests" 2>&1 | tee .build/xp-c-mesh-linux.log | tail -3
```
Expected: PASS on both, with the same tolerances for "Metal (HLSL)" and "Vulkan" as for "Metal". Record from the logs:
1. **The Face-mapped Voronoi struts item (D20's open item 3).** Add a temporary `print("XPC-MEASURE \(engineName) \(name) \(pipeline.worstScaledSurface) \(detail.along)")` after `let detail = pipeline.worstScaledDetail` in `theGPUMeshAgreesAwayFromTheSingularSet`, run it on each engine, write the figures into this task's commit message, and remove the print before committing. If the interpreter's figure for "voronoi struts, face of a cylinder" is also about 6e-4 mm (factor near 6), the divergence is Float sensitivity of the face chart's map and not a Metal bug: say so in D21 (task 9). If it is within 1 (D17's allowance) the divergence is specific to Metal's compiled code, and D21 says that. Do not change the factor in either case.
2. **The suite time on lavapipe**: the slowest test's duration from the Linux log (Swift Testing prints "passed after N seconds"). If the three suites together take more than 10 minutes in Docker, cut `GPUMeshAgreementTests.resolution(of:)`'s 60 voxels across to 40 **for the interpreted engine on Linux only** (`engineName == "Vulkan"`), re-measure, and say in the commit message which it is. Never loosen a tolerance to save time.

If an interpreted case fails a tolerance that Metal meets, it is a port error until shown otherwise: compare the fixture's values (`GPUAgreementTests` for that fixture), then the mesher alone (`theGPUMeshAgreesWithTheCPUMesh`'s first half compares the same samples), then the snap.

- [ ] **Step 4: Full suites, lint, commit, push and read Windows CI.**

```bash
swift test 2>&1 | tee .build/xp-c-task6-mac.log | grep -c "Test run with"     # 12, and no "recorded an issue"
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh all 2>&1 | tail -3
swiftlint lint --strict
git add Tests/CreatorImplicitTests
git commit -m "test(implicit): the mesh agreement, the streamed export and the limits over every GPU engine (xp-c task 6)

Face-mapped Voronoi struts, worst scaled surface: Metal …, Metal (HLSL) …, Vulkan (lavapipe) ….
Mesh suites on lavapipe: … s.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
git push origin xp-c
```
(Fill the measured figures in.) Then the Windows job: the agreement suites on "Direct3D 12" over WARP must pass, and the release build.

---

### Task 7: `--self-test` checks the kernels, and every package ships them

**Files:**
- Create: `Sources/CreatorImplicit/GPU/ImplicitShaderCheck.swift`
- Modify: `Sources/CreatorApp/SelfTest.swift`, `scripts/package-linux.sh`, `scripts/package-windows.ps1`, `scripts/linux-test.sh` (the clean-Ubuntu checks), `docs/packaging.md`
- Test: `Tests/CreatorImplicitTests/ImplicitShaderCheckTests.swift`

**Interfaces:**
- Consumes: `SDLImplicitShaders.verify(driver:sourceTree:)`, `.remedy` (task 4).
- Produces: `public enum ImplicitShaderCheck { public struct Failure: Error, CustomStringConvertible, LocalizedError, Equatable; public static func run() throws -> String?; static func run(sourceTree: URL) throws -> String? }`; packages with `ImplicitShaders/` beside the executable.

- [ ] **Step 1: Write the failing test.**

`Tests/CreatorImplicitTests/ImplicitShaderCheckTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorImplicit

/// `MetalCreator --self-test` asks the implicit engine whether its kernels were built and ship (plan xp-c): on Linux and Windows a build without them
/// meshes on the CPU and says "Running on the CPU"; the self-test fails, saying what to run (Review Focus 2). On a Mac there is nothing to find.
struct ImplicitShaderCheckTests {
    @Test func theCheckPassesOrHasNothingToFind() throws {
        #if canImport(MetalUISDLGPU)
        #expect(try ImplicitShaderCheck.run() == "the implicit engine's 7 SDL_GPU kernels were found")
        #else
        #expect(try ImplicitShaderCheck.run() == nil)
        #endif
    }

    @Test func aMissingDirectoryFailsTheSelfTestCheckWithAMessageThatSaysWhatToRun() throws {
        #if canImport(MetalUISDLGPU)
        let empty = FileManager.default.temporaryDirectory.appending(path: "xp-c-no-kernels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect {
            _ = try ImplicitShaderCheck.run(sourceTree: empty)
        } throws: { error in
            let text = String(describing: error)
            return text.contains("scripts/build-shaders.sh") && text.contains("ImplicitShaders") && text.contains("shadercross.env")
        }
        #endif
    }
}
```
(The second test only checks off macOS; on a Mac it has nothing to find, as the first says.)

- [ ] **Step 2: Run it to see it fail.**

Run: `swift test --filter CreatorImplicitTests.ImplicitShaderCheckTests 2>&1 | tail -3`
Expected: build failure ("cannot find 'ImplicitShaderCheck' in scope").

- [ ] **Step 3: Write the check and call it from the self-test.**

`Sources/CreatorImplicit/GPU/ImplicitShaderCheck.swift`:
```swift
import Foundation

/// `MetalCreator --self-test` asks the implicit engine whether its kernels were built and ship (plan xp-c): on macOS the Metal engine compiles its
/// source at run time, so there is nothing to find; on Linux and Windows the interpreted engine needs `Shaders/implicit/compiled` (made by
/// `scripts/build-shaders.sh`, git-ignored), shipped as `ImplicitShaders` beside the executable. Without them the app meshes on the CPU.
public enum ImplicitShaderCheck {
    /// The check failed: the message says where it looked and what to run.
    public struct Failure: Error, CustomStringConvertible, LocalizedError, Equatable {
        public let description: String
        public var errorDescription: String? { description }
    }

    /// What a passing check reports, or `nil` where there is nothing to find. Throws a ``Failure``.
    public static func run() throws -> String? {
        #if canImport(MetalUISDLGPU)
        try run(sourceTree: SDLImplicitShaders.sourceTree)
        #else
        nil
        #endif
    }

    /// The same check against another source-tree directory (the test points it at an empty one).
    static func run(sourceTree: URL) throws -> String? {
        #if canImport(MetalUISDLGPU)
        do {
            let kernels = try SDLImplicitShaders.verify(sourceTree: sourceTree)
            return "the implicit engine's \(kernels.formatted()) SDL_GPU kernels were found"
        } catch {
            throw Failure(description: "The implicit engine's compiled SDL_GPU kernels are missing or incomplete (\(error)). \(SDLImplicitShaders.remedy)")
        }
        #else
        return nil
        #endif
    }
}
```

In `Sources/CreatorApp/SelfTest.swift`, in `compileShaders()`'s `#elseif canImport(MetalUISDL)` branch, after `_ = try ViewportShaderCheck.run()` add `_ = try ImplicitShaderCheck.run()` (add `import CreatorImplicit` if the file lacks it), and change `shadersDetail`'s non-Metal string to `"MetalUI's SDL shaders, the viewport's and the implicit engine's were found"`. Search for the old string first (`grep -rn "the viewport's were found" Tests Sources`) and update any test that pins it.

- [ ] **Step 4: Ship the kernels in every package.**

In `scripts/package-linux.sh`, after the `cp -R "$APP_SHADERS" "$FOLDER/MetalUIAppShaders"` line add:
```bash
# The implicit engine's compute kernels (plan xp-c): ImplicitShaders beside the executable, where SDLImplicitShaders looks first. A build product,
# never in git: scripts/build-shaders.sh makes them with the viewport's.
IMPLICIT_SHADERS="$ROOT/Shaders/implicit/compiled"
[ -f "$IMPLICIT_SHADERS/SOURCE.sha256" ] || fail "the implicit engine's compiled kernels are missing ($IMPLICIT_SHADERS): run scripts/build-shaders.sh first"
cp -R "$IMPLICIT_SHADERS" "$FOLDER/ImplicitShaders"
```
and in its header comment, after "the 3D viewport's in MetalUIAppShaders", add ", the implicit engine's kernels in ImplicitShaders".

In `scripts/package-windows.ps1`, after `Copy-Item -Recurse $appShaders (Join-Path $folder 'MetalUIAppShaders')` add:
```powershell
# The implicit engine's compute kernels (plan xp-c): ImplicitShaders beside the executable. A build product: scripts\build-shaders.ps1 makes them.
$implicitShaders = Join-Path $root 'Shaders\implicit\compiled'
if (-not (Test-Path (Join-Path $implicitShaders 'SOURCE.sha256'))) { throw "the implicit engine's compiled kernels are missing ($implicitShaders): run scripts\build-shaders.ps1 first" }
Copy-Item -Recurse $implicitShaders (Join-Path $folder 'ImplicitShaders')
```
and in its self-test block move the source tree's `Shaders\implicit\compiled` aside too, so a zip without `ImplicitShaders` fails there:
```powershell
$implicitShadersAside = "$implicitShaders.aside"
```
beside `$appShadersAside`, `Rename-Item $implicitShaders $implicitShadersAside` after `Rename-Item $appShaders $appShadersAside`, and `Rename-Item $implicitShadersAside $implicitShaders` in the `finally` block before `Rename-Item $appShadersAside $appShaders`; and extend the comment above it ("…and the implicit engine falls back to this checkout's Shaders\implicit\compiled, which would hide one without ImplicitShaders; so all three are moved aside").

In `scripts/linux-test.sh`'s `do_package`, after `test -f MetalUIAppShaders/SOURCE.sha256 && test -s MetalUIAppShaders/mesh.vert.spv` add `        test -f ImplicitShaders/SOURCE.sha256 && test -s ImplicitShaders/implicit_evaluate.comp.spv`; after the two AppImage lines that extract and test `MetalUIAppShaders` add
```bash
        ./MetalCreator.AppImage --appimage-extract "usr/metalcreator/ImplicitShaders/*" >/dev/null
        test -s squashfs-root/usr/metalcreator/ImplicitShaders/implicit_evaluate.comp.spv
```
In `docs/packaging.md`, beside each mention of `MetalUIAppShaders/` (lines about the tarball, the AppImage's AppDir and the zip), add "`ImplicitShaders/` (the implicit engine's compute kernels, from the same script; plan xp-c)".

- [ ] **Step 5: Run the tests, the smoke, and the packages.**

Run:
```bash
swift test --filter "CreatorImplicitTests.ImplicitShaderCheckTests|CreatorAppTests.SelfTest" 2>&1 | tail -3
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh smoke 2>&1 | tail -5     # the self-test lists the implicit kernels
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh package 2>&1 | tail -4   # tarball and AppImage PASS in a clean ubuntu:24.04
```
Expected: PASS. Then the Windows job's "Package (zip), checked on its own" step after the push in step 6.

- [ ] **Step 6: Lint, commit, push.**

```bash
swiftlint lint --strict
git add Sources/CreatorImplicit/GPU/ImplicitShaderCheck.swift Sources/CreatorApp/SelfTest.swift scripts docs/packaging.md Tests
git commit -m "feat(app): --self-test checks the implicit kernels; the tarball, AppImage and zip ship them as ImplicitShaders (xp-c task 7)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
git push origin xp-c
```

---

### Task 8: Benchmarks: rows x-1 and x-2 on every engine, x-1h judged on this Mac

**Files:**
- Create: `Tests/CreatorImplicitTests/ImplicitBenchInterpreted.swift`
- Modify: `docs/verification/performance.md` (a section and its rows)

**Interfaces:**
- Consumes: `GPUEnginesUnderTest` (task 3), `ImplicitGPUEngines.meshesMade()` (task 4).
- Produces: the measured rows task 9's erratum and human check XP-27 cite; the cost of the canonical sort (X-C3).

- [ ] **Step 1: Write the bench suite.**

`Tests/CreatorImplicitTests/ImplicitBenchInterpreted.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// Rows x-1, x-2 and x-1h (plan xp-c, user decision X-C7): the implicit engines side by side on one solid, the mesher alone. Printed as `BENCH`
/// lines, judged only where X-C7 says. A plain `swift test` skips it; run `scripts/bench.sh ImplicitBench` on a Mac and, on Linux,
/// `DOCKER_EXTRA="-e METALCREATOR_BENCH=1" scripts/linux-test.sh test -c release --no-parallel --filter ImplicitBenchInterpreted`.
/// - x-1: a gyroid sheet filling a 100 mm cube (100 mm cells, 3 mm wall), meshed at 0.78 mm (128 voxels across: the preview's first pass), on a
///   warm engine; the median of six.
/// - x-2: the same sheet with a 2.5 mm wall, the engine warm (a thickness edit: the interpreter compiles nothing).
/// - x-1h: x-1 on "Metal (HLSL)", the interpreted engine on this Mac's GPU: judged against i-1's 1 s, a proxy for a desktop GPU (X-C7).
/// - x-1s: the canonical sort's share of x-1 (`MeshCanonicalOrder.mesh` alone on x-1's arrays), the price of X-C3.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["METALCREATOR_BENCH"] == "1", "set METALCREATOR_BENCH=1"))
struct ImplicitBenchInterpreted {
    static func sheet(wall: Double) -> ImplicitSolid {
        .tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeCells(size: .constant(100)), thickness: .constant(wall),
                          region: BoundingBox(min: Vector3(-50, -50, -50), max: Vector3(50, 50, 50))))
    }

    static let resolution = 100.0 / 128
    static let firstPassBudget = 1000.0

    static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// The mesher on `name`'s engine ("CPU" for the CPU evaluator), six warm runs; the median in milliseconds and the triangles.
    static func time(_ solid: ImplicitSolid, on name: String) async throws -> (milliseconds: Double, triangles: Int) {
        let evaluator: any ImplicitBatchEvaluator = name == "CPU"
            ? CPUBatchEvaluator(solid)
            : await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: try GPUEnginesUnderTest.engine(name)).evaluator
        let clock = ContinuousClock()
        var samples: [Double] = []
        var triangles = 0
        for round in 0..<7 {
            let start = clock.now
            let (mesh, path) = try await ImplicitMesher(evaluator: evaluator).meshReportingPath(solid, resolution: resolution, quality: .preview)
            if round > 0 { samples.append(milliseconds(clock.now - start)) }
            #expect(name == "CPU" || path == .gpu, "\(name) meshed on the GPU")
            triangles = mesh.triangleCount
        }
        return (median(samples), triangles)
    }

    /// A debug build's numbers are not benchmarks (`Bench.requireRelease` in `CreatorAppTests`, which this target cannot import).
    static func requireRelease() -> Bool {
        #if DEBUG
        Issue.record("Benchmarks run in a release build: scripts/bench.sh (swift test -c release).")
        return false
        #else
        return true
        #endif
    }

    @Test(arguments: GPUEnginesUnderTest.names + ["CPU"])
    func theFirstPassAndAThicknessEditOnEachEngine(_ name: String) async throws {
        guard Self.requireRelease() else { return }
        let first = try await Self.time(Self.sheet(wall: 3), on: name)
        print("BENCH x-1 \(name): first pass of a 100 mm gyroid sheet at 0.78 mm: median \(first.milliseconds.formatted(.number.precision(.fractionLength(2)))) ms, \(first.triangles) triangles")
        let edit = try await Self.time(Self.sheet(wall: 2.5), on: name)
        print("BENCH x-2 \(name): thickness edit, warm: median \(edit.milliseconds.formatted(.number.precision(.fractionLength(2)))) ms")
        if name == "Metal (HLSL)" {
            let met = first.milliseconds < Self.firstPassBudget
            print("BENCH x-1h Metal (HLSL): \(first.milliseconds.formatted(.number.precision(.fractionLength(2)))) ms; budget 1000.00 ms: \(met ? "met" : "missed")")
            #expect(met, "x-1h: the interpreted engine on this Mac's GPU misses i-1's 1 s")
        }
    }

    @Test(.enabled(if: GPUEnginesUnderTest.interpreted != nil))
    func theCanonicalSortsShareOfAFirstPass() async throws {
        guard Self.requireRelease() else { return }
        let engine = try #require(GPUEnginesUnderTest.interpreted)
        let solid = Self.sheet(wall: 3)
        let program = try await engine.compile(solid)
        let plan = try await BrickPlan.build(for: solid, resolution: Self.resolution, using: GPUBatchEvaluator(engine: engine, program: program))
        let mesh = try await engine.meshBricks(program, BrickMeshRequest(plan: plan, snap: true)) { _ in }
        let keys = (0..<UInt32(mesh.positions.count)).reversed().map { $0 }
        let tags = (0..<UInt32(mesh.triangles.count / 3)).map { $0 / 2 }
        let clock = ContinuousClock()
        let start = clock.now
        _ = MeshCanonicalOrder.mesh(positions: mesh.positions, normals: mesh.normals, keys: Array(keys), triangles: mesh.triangles, tags: tags)
        print("BENCH x-1s canonical order of \(mesh.triangles.count / 3) triangles: \(Self.milliseconds(clock.now - start).formatted(.number.precision(.fractionLength(2)))) ms")
    }
}
```
The sheet is built directly (the TPMS node's graph is `CreatorAppTests`'), so x-1 is not i-1 (which evaluates the graph and joins a skin): the rows compare engines with each other, not with i-1's history. `scripts/bench.sh ImplicitBench` runs it on a Mac (the filter matches `ImplicitBenchInterpreted`).

- [ ] **Step 2: Run it on the Mac and on Linux.**

Run (idle machine; the first lines are its load):
```bash
XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh shaders
scripts/bench.sh ImplicitBenchInterpreted
DOCKER_EXTRA="-e METALCREATOR_BENCH=1" XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test -c release --no-parallel --filter ImplicitBenchInterpreted 2>&1 | grep BENCH
DOCKER_EXTRA="-e METALCREATOR_BENCH=1" XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test -c release --no-parallel --filter "ImplicitBench/(theFirstPreview|aThicknessEdit)" 2>&1 | grep BENCH
```
Expected: `BENCH x-1`, `x-2` for Metal, Metal (HLSL) and CPU on the Mac, `x-1h … met`; `x-1`, `x-2` for Vulkan (lavapipe) and CPU on Linux; i-1 and i-2 on Linux (now on the SDL engine through the graph). x-1h missing its budget is a finding, not a test to loosen: record it and raise it in task 9's report (the interpreter needs work, or X-C7 needs another budget).

- [ ] **Step 3: Record the numbers.**

In `docs/verification/performance.md`, after the ImplicitBench section, add:
```markdown
## Implicit engines side by side (plan xp-c, rows x-1, x-2, x-1h, x-1s)

`ImplicitBenchInterpreted` (`Tests/CreatorImplicitTests`): a gyroid sheet filling a 100 mm cube (100 mm cells, 3 mm wall) meshed at 0.78 mm by the
mesher alone, warm, the median of six; x-2 the same with a 2.5 mm wall. Budgets (user decision X-C7): none in CI, where lavapipe and WARP are CPU
rasterizers; x-1h, the interpreted engine on this Mac's GPU (the MSL of the HLSL kernels), is held to i-1's 1 s as a proxy for a desktop GPU; on a
desktop GPU under Linux or Windows human check XP-27 asks for i-1's and i-2's budgets.

| Row | Machine | Engine | Median | Budget | Verdict |
|---|---|---|---|---|---|
| x-1 | (this Mac, load …) | Metal | … ms | recorded | n/a |
| x-1 | (this Mac) | Metal (HLSL) | … ms | 1000 ms (x-1h) | … |
| x-1 | (this Mac) | CPU | … ms | recorded | n/a |
| x-1 | Linux image (OrbStack, aarch64) | Vulkan (lavapipe) | … ms | recorded | n/a |
| x-1 | Linux image | CPU | … ms | recorded | n/a |
| x-2 | each of the above | … | … ms | recorded | n/a |
| x-1s | (this Mac) | the canonical sort of x-1's … triangles | … ms | recorded | n/a |
| i-1, i-2 | Linux image | Vulkan (lavapipe), through the graph | … ms, … ms | recorded (D11) | n/a |

The BENCH lines of the runs:
```
and paste the `BENCH` lines under it in a fenced block. Fill every "…" from the runs; a cell with nothing measured says "not run" and why.

- [ ] **Step 4: Commit.**

```bash
swiftlint lint --strict
git add Tests/CreatorImplicitTests/ImplicitBenchInterpreted.swift docs/verification/performance.md
git commit -m "bench(implicit): rows x-1, x-2, x-1h, x-1s: the implicit engines side by side (xp-c task 8)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

---

### Task 9: The errata, the human checks and the project notes

**Files:**
- Modify: `docs/superpowers/specs/2026-10-13-cross-platform-design.md` (erratum E8; the XP-G2 row), `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` (erratum D21), `docs/verification/human-checks.md` (group XPC: XP-27 to XP-29), `docs/metalui-gaps.md` (the XP-G2 row), `CLAUDE.md`

**Interfaces:**
- Consumes: the measured figures of tasks 6 and 8.
- Produces: the spec text the user approves with the plan's decisions.

- [ ] **Step 1: Add erratum E8 to the cross-platform spec.**

After E7, add:
```markdown
- **E8 (xp-c, XP-G2 and E7's last sentence). Implicit evaluation and meshing on SDL GPU.** E7's "Implicit evaluation and meshing stay on the CPU off
  macOS (xp-c)" no longer holds. On Linux and Windows `ImplicitGPUEngines.platformDefault` is `InterpretedImplicitEngine.sdl`, MetalUI's SDL_GPU compute
  (`MetalUISDLGPU`, S5) under an engine that runs a compiled solid as a program of fixed-size instructions (`ImplicitProgram`) through one HLSL
  interpreter, because SDL_GPU takes only shaders compiled before the app runs (E7, U1(b)) and the Metal engine's per-shape source cannot be compiled
  there (plan `2026-10-22-xp-c-sdl-gpu-meshing.md`, user decision X-C1). The kernels are HLSL in `Shaders/implicit`, compiled at build time with the
  viewport's (`scripts/build-shaders.sh`, `.ps1`) into `Shaders/implicit/compiled`, git-ignored, and shipped as `ImplicitShaders` beside the
  executable; `--self-test` checks them. The engine owns a headless device of its own, made on first use off the main actor. macOS keeps
  `MetalImplicitEngine`; the same HLSL, compiled to MSL by SDL_shadercross, runs on the Mac's GPU in the tests only (X-C2). No SDL_GPU device: the
  CPU, silently; missing kernels or a refused pipeline: the CPU with "Running on the CPU"; a solid beyond the interpreter (32 values or 8 points held at
  once, 4,096 steps, a distance to a profile): the CPU with the warning, as on Metal (X-C4). The badge says "Vulkan" on Linux and "Direct3D 12" on
  Windows (X-C8). CI runs the engine on Mesa's lavapipe and Direct3D 12's WARP with `XP_REQUIRE_GPU=1` (X-C5). Gaps XP-G23 (the adapter's name, whether
  it is a software rasterizer) and XP-G24 (compute limits) are open; until they are answered the inspector names the driver, a software device is
  used like a hardware one, and a storage buffer is at most 128 MiB.
```
In §5's table, replace the XP-G2 row's "Needed by" cell `after xp-3` with `after xp-3. **Answered by MetalUI S5** (\`SDLGPUComputePipeline\`, \`submitBatch\`, append buffers) and **used by xp-c** (erratum E8)`.

- [ ] **Step 2: Add erratum D21 to the implicit spec.**

After D20 (before "### Errata (7c-3 acceptance, measured)"), add:
```markdown
- **D21. The interpreted GPU engine (xp-c, plan `2026-10-22-xp-c-sdl-gpu-meshing.md`).** Amends §4.1, §6, D11, D13 and D15. (1) **Compilation.** §4.1's
  "sources are cached by the tree's shape" is the Metal engine's. On Linux and Windows a solid compiles to an `ImplicitProgram` (`ImplicitProgramCompiler`,
  which walks the tree as `ImplicitCompiler` does and writes the same five buffers, pinned by a test), run by one HLSL interpreter whose source is fixed:
  neither an edited value nor a changed shape compiles anything. (2) **Agreement.** The interpreted engine is held to the CPU by the same suites and the
  same tolerances as Metal, over the Mac's GPU, lavapipe and WARP: values within 1e-4 mm; D15's mesher 1e-4 mm and whole pipeline 2e-3 mm; D17's
  slope allowance; D20's amended allowance unchanged, including its 7× for the Face-mapped Voronoi struts on a cylinder, which measured
  <task 6's figure> on the interpreter against <Metal's> on Metal (<task 6's conclusion: the same Float sensitivity of the face chart's map on both, or
  Metal's alone>). (3) **Precision.** Float everywhere, never half; sine, cosine and arctangent are the engine's own (Cody–Waite reduction, Cephes
  polynomials), because Vulkan guarantees only an absolute 2^-11 for its sine; the noise's 64-bit hash is computed in pairs of 32-bit words, needing no
  64-bit integer support from the device. (4) **Order.** The interpreted engine's meshes come in a canonical order (vertices by lattice edge key,
  triangles by the brick's place in the request, the cube in the brick and the table's order), so a request meshes to the same arrays every run and an
  export made twice on Linux or Windows has the same bytes; Metal's order stays the threads' (D13). (5) **Budgets.** §6's i-1 and i-2 are Metal's (D11).
  The interpreted engine records x-1 and x-2 without a budget in CI (lavapipe and WARP rasterize on the CPU); on this Mac's GPU it is held to i-1's 1 s
  (x-1h, measured <task 8's figure>); on a desktop GPU under Linux or Windows human check XP-27 asks for i-1's and i-2's budgets. (6) **Limits.** A
  storage buffer is at most 128 MiB until MetalUI reports the device's limits (gap XP-G24), so the edge table has at most 2^25 slots (Metal's 2^27);
  past it, or past 8,388,607 bricks, a request is the CPU mesher's.
```
Replace each `<…>` with the measured value or conclusion from tasks 6 and 8 (their commit messages); none may remain.

- [ ] **Step 3: Add the human checks.**

In `docs/verification/human-checks.md`, after group XP3, add:
```markdown
## Group XPC — implicit evaluation and meshing on SDL GPU, Linux and Windows (xp-c)

**Status: NOT RUN.** Plan `2026-10-22-xp-c-sdl-gpu-meshing.md`; specs: cross-platform erratum E8, implicit erratum D21. CI holds the engine to the CPU
on Mesa's lavapipe (Linux) and Direct3D 12's WARP (Windows); these checks are what a real GPU, a person's eye and a stopwatch show. Linux: build as for
group XP after `scripts/build-shaders.sh` (or use the tarball or AppImage); Windows: the zip.

- [ ] **XP-27 Lattice previews on a desktop GPU (Linux and Windows).** On a machine with a real GPU (Linux: Vulkan on Mesa or the vendor's driver;
  Windows 11: Direct3D 12), open a graph with a TPMS node filling a 100 mm cube (the `ImplicitBench` sheet) and a Mesh node: the preview's badge says
  "Vulkan" (Linux) or "Direct3D 12" (Windows), never "Running on the CPU"; the first pass appears in under a second; dragging the thickness slider
  re-meshes within about a tenth of a second a pass (i-1, i-2). The surface looks as on a Mac: smooth, closed, no cracks between bricks, no flat spots.
  For numbers: `METALCREATOR_BENCH=1 swift test -c release --no-parallel --filter "ImplicitBenchInterpreted|ImplicitBench/(theFirstPreview|aThicknessEdit)"`
  on that machine, and add the BENCH lines to `docs/verification/performance.md`. **Pinned:** `GPUAgreementTests`, `GPUMeshAgreementTests` (lavapipe,
  WARP). **Observed:**
- [ ] **XP-28 The same export twice (Linux and Windows).** Export the sheet's Mesh as STL, then again to a second file without changing anything:
  the files are byte-identical (`cmp a.stl b.stl` on Linux, `fc /b a.stl b.stl` on Windows), and the same holds for 3MF. **Pinned:**
  `InterpretedMeshingTests.theSameRequestMeshesToTheSameArraysEveryTime`. **Observed:**
- [ ] **XP-29 A package without its kernels.** Unpack the tarball (or the zip), rename `ImplicitShaders` beside the executable, and launch it away from
  any checkout: the app runs, a Mesh node still meshes and its badge says "Running on the CPU"; `--self-test` fails, naming
  `scripts/build-shaders.sh` and `ImplicitShaders`. Rename it back: the badge says "Vulkan" (or "Direct3D 12") again after a relaunch. **Pinned:**
  `SDLComputeBackendTests.aDirectoryWithoutTheKernelsIsBrokenAndSaysWhatToRun`, `ImplicitShaderCheckTests`. **Observed:**
```

- [ ] **Step 4: The gaps file and CLAUDE.md.**

In `docs/metalui-gaps.md`'s summary table, change the XP-G2 row's status to `✅ answered (MetalUI S5); used by xp-c: implicit evaluation and meshing on SDL GPU (cross-platform erratum E8)`.

In `CLAUDE.md`:
- in the 7c-1g paragraph replace "The SDL3 engine for Linux and Windows is track xp-c." with "Linux and Windows mesh on the GPU too since xp-c (below).";
- after the xp-3 paragraph add:
```markdown
Cross-platform, sub-project xp-c (implicit evaluation and meshing on SDL GPU, Linux and Windows; plan `docs/superpowers/plans/2026-10-22-xp-c-sdl-gpu-meshing.md`,
cross-platform erratum E8, implicit erratum D21): `ImplicitGPUEngines.platformDefault` is `InterpretedImplicitEngine.sdl` off macOS. A solid compiles
to an `ImplicitProgram` (`CreatorImplicit/Interpreter`: `ImplicitProgramCompiler` mirrors `ImplicitCompiler.Generator` case for case and writes the
same five buffers, `ImplicitProgramCompilerTests` pins it; 37 ops, 32 scalar and 8 point registers, 4,096 steps; beyond them, `.unsupported`, the CPU
with "Running on the CPU"), run by one HLSL interpreter (`Shaders/implicit/interpreter.hlsli`) in seven compute kernels (`ImplicitKernel`), compiled
at build time with the viewport's shaders (`scripts/build-shaders.sh` compiles every set in `Shaders/`; `Shaders/implicit/compiled` is git-ignored,
shipped as `ImplicitShaders`, checked by `--self-test` through `ImplicitShaderCheck`). **Edit an op, a limit or a table offset on both sides:**
`ImplicitShaderContractTests` pins `contract.hlsli` to `ImplicitOp`, `ImplicitProgram`, `ImplicitKernel.bindings`, `KernelParameters` and the
marching-cubes constants, and forbids `half`, 64-bit integers, `GetDimensions` and the drivers' trigonometry (`accurate_math.hlsli` has the engine's own).
`InterpretedImplicitEngine` (`CreatorImplicit/Compute`, portable) talks to an `ImplicitComputeBackend`: `SDLComputeBackend` (`CreatorImplicit/SDL`,
behind `#if canImport(MetalUISDLGPU)`, an owned headless `SDLGPUDevice`, made on first use; each dispatch in a compute pass of its own, because SDL_GPU
does not synchronize dispatches inside one) and, in the tests on a Mac, `MSLComputeBackend` over the MSL shadercross made of the same HLSL (run
`XP_TRACK=… scripts/linux-test.sh shaders` first; without it the Mac's interpreted cases skip by name). `ImplicitGPUEngine.availability` (`.absent`:
no device, the CPU silently; `.broken`: no kernels or a refused pipeline, the CPU with the warning) is read by `ImplicitEvaluators.make`. The
interpreted engine's meshes are in a canonical order (`MeshCanonicalOrder`: vertices by edge key, triangles by brick, cube and table order), so they are
the same arrays every run; Metal's stay the threads'. `GPUAgreementTests`, `GPUMeshAgreementTests` and `StreamingMesherGPUTests` run over
`GPUEnginesUnderTest.names` (Metal, "Metal (HLSL)", "Vulkan" on lavapipe, "Direct3D 12" on WARP) at the 7c tolerances; `ImplicitGPUAvailabilityTests`
fails under `XP_REQUIRE_GPU=1` without a device. Gaps XP-G23 (adapter name, software rasterizer) and XP-G24 (compute limits: storage buffers are capped
at 128 MiB meanwhile) are open; rows x-1, x-2, x-1h, x-1s are in `docs/verification/performance.md`; human checks XP-27 to XP-29 (group XPC) are pending.
```
- in the module notes for `CreatorImplicit` replace "whose only implementation is `MetalImplicitEngine` (an actor that compiles each shape once; the one file that imports Metal, compiled only under `#if canImport(Metal)`)" with "implemented by `MetalImplicitEngine` on macOS (an actor that compiles each shape once; the one file that imports Metal, compiled only under `#if canImport(Metal)`) and by `InterpretedImplicitEngine` on Linux and Windows (xp-c, over `SDLComputeBackend`)", and "The agreement suite `GPUAgreementTests` holds Metal to the CPU within 1e-4 mm (skipped without a Metal device)" with "The agreement suite `GPUAgreementTests` holds every GPU engine the machine has to the CPU within 1e-4 mm (skipped without one)";
- in "Commands", change `scripts/build-shaders.sh`'s line to "compile every shader set (`Shaders/viewport`, `Shaders/implicit`) into its `compiled` directory (git-ignored) …", and add `scripts/linux-test.sh shaders   # compile the shader sets in the Linux image into the worktree: the Mac's tests read the implicit kernels' MSL from there` after the `linux-test.sh package` line;
- keep every phrase `CIPinTests` pins (`grep -n "CLAUDE" Tests/CreatorAppTests/*Pin*` lists them; run that test after editing).

- [ ] **Step 5: Check, commit.**

Run:
```bash
grep -n "<task\|<Metal\|<…" docs/superpowers/specs/2026-10-13-implicit-lattices-design.md    # nothing
swift test --filter CIPinTests 2>&1 | tail -2
git add docs CLAUDE.md
git commit -m "docs: errata E8 and D21, human checks XP-27 to XP-29, xp-c in CLAUDE.md (xp-c task 9)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

---

### Task 10 (waits for MetalUI): adopt XP-G23 and XP-G24

Runs only when MetalUI answers a gap (its entry in `docs/metalui-gaps.md` says so and names the commit). Until then the branch merges without it; nothing is worked around. Bump `METALUI_COMMIT` in `.github/workflows/xp.yml` to the answering commit in this task (the only xp-c change to it), after checking that commit's `MetalUISDLGPU` with `git -C ../MetalUI show <commit>:Backends/SDL/Sources/MetalUISDLGPU/SDLGPUDevice.swift`.

**Files:**
- Modify: `Sources/CreatorImplicit/SDL/SDLComputeBackend.swift`, `docs/metalui-gaps.md`, `.github/workflows/xp.yml`
- Test: `Tests/CreatorImplicitTests/SDLComputeBackendTests.swift`

**Interfaces:**
- Consumes: the names MetalUI's answer gives. The plan asks for `SDLGPUDevice.adapterName: String?`, `SDLGPUDevice.isSoftwareRasterizer: Bool` and `SDLGPUDevice.limits` with `maxStorageBufferBindingSize: Int` and `maxComputeWorkGroupCount: Int`; use the answer's real names.
- Produces: `deviceName` is the adapter's; `largestBuffer` and `ComputeBytes.maximumGroups` come from the device; the app's policy on software devices (X-C5).

- [ ] **Step 1: Write the failing tests** (in `SDLComputeBackendTests`, enabled with a device):
```swift
    @Test(.enabled(if: GPUEnginesUnderTest.interpreted != nil, "needs an SDL_GPU device"))
    func theDeviceNameIsTheAdaptersAndTheLimitsAreTheDevices() throws {
        guard case .ready(let backend) = GPUEnginesUnderTest.interpretedState, let sdl = backend as? SDLComputeBackend else { return }
        #expect(sdl.deviceName != sdl.name, "the adapter's name, not the driver's: \(sdl.deviceName)")
        #expect(sdl.largestBuffer >= 1 << 27, "at least Vulkan's guaranteed range")
    }

    /// X-C5: the app prefers the CPU engine on a software device; the tests' engine still runs on it.
    @Test func theAppsEngineIsAbsentOnASoftwareDeviceUnlessAllowed() {
        #expect(SDLComputeBackend.policy(isSoftware: true, allowingSoftware: false) == .preferCPU)
        #expect(SDLComputeBackend.policy(isSoftware: true, allowingSoftware: true) == .use)
        #expect(SDLComputeBackend.policy(isSoftware: false, allowingSoftware: false) == .use)
    }
```
- [ ] **Step 2: Run them to see them fail** (`scripts/linux-test.sh test --filter SDLComputeBackendTests`): "has no member 'policy'".
- [ ] **Step 3: Implement.** In `SDLComputeBackend`: `deviceName` returns the adapter's name when MetalUI gives one; `largestBuffer` is `min(device's maxStorageBufferBindingSize, 1 << 31)`; `ComputeBytes.maximumGroups` stays the 65,535 floor unless the device reports less. Add
```swift
    enum SoftwarePolicy: Equatable { case use, preferCPU }
    static func policy(isSoftware: Bool, allowingSoftware: Bool) -> SoftwarePolicy { isSoftware && !allowingSoftware ? .preferCPU : .use }
```
and `make(sourceTree:allowingSoftware: Bool = false)` returns `.absent("a software rasterizer (…): the CPU engine is faster")` under `.preferCPU`, **unless task 8's rows showed lavapipe faster than the CPU engine in the Linux image, in which case `allowingSoftware` defaults to `true` and the doc comment says why, citing the rows**. `GPUEnginesUnderTest.interpretedState` passes `allowingSoftware: true` (CI tests on lavapipe and WARP), and so does `ImplicitGPUAvailabilityTests` when it checks `InterpretedImplicitEngine.sdl`: make that test check a backend made with `allowingSoftware: true` rather than the app's engine.
- [ ] **Step 4: Run** the Linux and Windows suites (`scripts/linux-test.sh all`, a push and the Windows job): PASS; the inspector on lavapipe shows "llvmpipe (…)".
- [ ] **Step 5: Mark the gap adopted** in `docs/metalui-gaps.md` (its row: "✅ fixed by MetalUI <commit>, adopted by xp-c task 10"), update E8's last sentence in the cross-platform spec, lint, commit with the trailers.

---

## Execution order and verification

Tasks 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 in order (each consumes the one before; 1 and 2 could run in parallel, but 2's contract test reads 1's types). Task 10 waits for MetalUI.

The branch is done when, on its last commit:
- macOS: `swift test` exits 0 with 12 "Test run with" lines and no issue line, the total is the baseline plus the new tests; `swift test --filter CreatorImplicitTests` with and without `Shaders/implicit/compiled` present both pass (the interpreted cases skip by name without it); `swiftlint lint --strict` is clean; the asserts toolchain's release build completes.
- Linux: `XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh all` and `… package` PASS (12 lines; the agreement suites on "Vulkan").
- Windows (CI on `xp-c`): the build, the test step (12 lines; the agreement suites on "Direct3D 12"), the self-test and smoke, "Build release (for the zip)" and the zip's own check pass.
- `git status` is clean after a build: no compiled shader is tracked.
