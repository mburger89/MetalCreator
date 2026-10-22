// swift-tools-version: 6.4
import PackageDescription

// Two lists, like MetalUI's manifest (cross-platform spec §2.1, PC-A). The first holds the targets that import no Apple
// framework (a file that needs Metal gates itself with `#if canImport(Metal)`) and, since xp-2, the OpenCascade shim and its
// kernel; they are declared on every platform. The second holds the two dev windows, declared on macOS only.

/// MetalUI's SDL backend and AccessKit are traits, asked for on Linux and Windows only (MetalUI `getting-started.md`,
/// "Linux and Windows"): a macOS build never needs SDL.
#if os(Linux) || os(Windows)
let metalUITraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
#else
let metalUITraits: Set<Package.Dependency.Trait> = [.defaults]
#endif

/// The UI framework (spec §3.1). Its gaps are logged in docs/metalui-gaps.md and fixed in MetalUI.
let metalUI: Target.Dependency = .product(name: "MetalUI", package: "MetalUI")

/// MetalUI's headless test harness (`docs/testing.md` in MetalUI): a dependency of test targets only, never of a product.
let metalUITesting: Target.Dependency = .product(name: "MetalUITesting", package: "MetalUI")

/// MetalUI's portable text, named on every platform and not only where it is used (MetalUI ruling `SG-D`: a conditional
/// dependency drops its C modules' module maps from a test target on macOS). Tests measure text with it off macOS.
let metalUIPortableText: Target.Dependency = .product(name: "MetalUIPortableText", package: "MetalUI")

/// The platform's installed fonts as a resolver for the portable text system. Named on every platform (`SG-D`).
let metalUISystemFonts: Target.Dependency = .product(name: "MetalUISystemFonts", package: "MetalUI")

/// The SDL3 backend, on Linux and Windows only.
let metalUISDL: Target.Dependency = .product(name: "MetalUISDL", package: "MetalUI", condition: .when(platforms: [.linux, .windows]))

/// MetalUI's SDL_GPU layer (`SDLGPUDevice`, textures, pipelines, render passes, shader library): the 3D viewport's renderer on Linux
/// and Windows (xp-3). A dependency of `CreatorViewport` and its tests only.
let metalUISDLGPU: Target.Dependency = .product(name: "MetalUISDLGPU", package: "MetalUI", condition: .when(platforms: [.linux, .windows]))

/// The OpenCascade kernel (xp-2): a dependency on every platform.
let occt: [Target.Dependency] = ["CreatorOCCT"]

/// Where OpenCascade 7.9 is installed on this machine: `include/opencascade` and `lib`, under one prefix. Set `OCCT_PREFIX` to
/// use another. The defaults are Homebrew's `opencascade` formula (macOS, which ships CMake configs but no pkg-config file, so
/// the shim is pointed at it directly), the prefix the Linux test image builds into (`scripts/linux/Dockerfile`), and vcpkg's
/// `x64-windows` install root as `.github/workflows/xp.yml` makes it (`packaging/windows/vcpkg.json`; `debug/lib` beside `lib`).
#if os(macOS)
let occtDefaultPrefix = "/opt/homebrew/opt/opencascade"
#elseif os(Windows)
let occtDefaultPrefix = "C:/occt"
#else
let occtDefaultPrefix = "/opt/occt"
#endif
let occtPrefix = Context.environment["OCCT_PREFIX"] ?? occtDefaultPrefix

var targets: [Target] = [
    .target(name: "CreatorGeometry"),
    .target(name: "CreatorSketch", dependencies: ["CreatorGeometry"]),
    .target(name: "CreatorKernel", dependencies: ["CreatorGeometry"]),
    // CreatorSketch: `ConstantValue.sketch` (S4). The Sketch node in CreatorNodes solves it.
    .target(name: "CreatorGraph", dependencies: ["CreatorKernel", "CreatorGeometry", "CreatorSketch"]),
    // Implicit solids and meshes (implicit spec §2 to §4): the value types, the CPU evaluator, the Metal compiler, the sparse
    // octree and the mesher. Depends on CreatorGraph for `Field`; CreatorGraph holds them only as `ImplicitPayload` and
    // `MeshPayload`. Portable: the Metal compiler is gated with `#if canImport(Metal)`.
    .target(name: "CreatorImplicit", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry"]),
    // MetalUI only for `DecodedImage`, the picture decoder (`GreyImageDecoder+MetalUI.swift`, the one file that imports it).
    .target(name: "CreatorNodes",
            dependencies: ["CreatorGraph", "CreatorImplicit", "CreatorKernel", "CreatorGeometry", "CreatorSketch", metalUI]),
    // Colour themes (spec §6.6, Dracula by default): the roles, the built-in themes and the `ThemeStore` that
    // the editor's views and the viewport's GPU colours read.
    .target(name: "CreatorStyle", dependencies: [metalUI]),
    // The viewport's model, camera and tools are portable; its Metal renderer is gated with `#if canImport(Metal)`.
    // MetalUIPortableText and MetalUISystemFonts only for the view cube's face names off macOS (`CubeLabelFonts`), named on every
    // platform for the reason above (SG-D).
    .target(
        name: "CreatorViewport",
        dependencies: [
            "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI, metalUIPortableText, metalUISystemFonts, metalUISDL, metalUISDLGPU,
        ]
    ),
    .target(name: "CreatorEditor", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
    // The in-viewport sketch editor (sketcher spec §8, S5): `SketchEditorModel`, its tools and its views. Graph-free:
    // the app shell turns its commits into graph commands. CreatorStyle for the theme's colours.
    .target(name: "CreatorSketchEditor",
            dependencies: ["CreatorSketch", "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
    // The app shell (M6): the one target that joins the graph, the nodes, the viewport and the editors. A library,
    // so its model is tested; the executable below only opens the window.
    .target(
        name: "CreatorApp",
        dependencies: [
            "CreatorEditor", "CreatorViewport", "CreatorNodes", "CreatorGraph", "CreatorImplicit", "CreatorKernel", "CreatorGeometry",
            "CreatorStyle", "CreatorSketch", "CreatorSketchEditor", metalUI, metalUISDL,
        ]
    ),
    .executableTarget(
        name: "MetalCreatorApp",
        dependencies: ["CreatorApp", "CreatorGraph", "CreatorKernel", metalUI, metalUISDL, metalUIPortableText, metalUISystemFonts] + occt
    ),
    // CreatorOCCT is a test-only dependency: the app-level acceptance test runs the §7.2 bracket on OCCT.
    .testTarget(
        name: "CreatorAppTests",
        dependencies: [
            "CreatorApp", "CreatorEditor", "CreatorViewport", "CreatorNodes", "CreatorGraph", "CreatorImplicit", "CreatorKernel",
            "CreatorGeometry", "CreatorStyle", "CreatorSketch", "CreatorSketchEditor", metalUI, metalUITesting,
            metalUIPortableText, metalUISystemFonts,
        ] + occt
    ),
    // CreatorNodes is a test-only dependency: BuiltInNodesInspectorTests runs the real M3
    // definitions through the inspector; the CreatorEditor library never imports it.
    .testTarget(
        name: "CreatorEditorTests",
        dependencies: [
            "CreatorEditor", "CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorNodes", "CreatorStyle", metalUI,
            metalUIPortableText, metalUISystemFonts,
        ]
    ),
    .testTarget(name: "CreatorStyleTests", dependencies: ["CreatorStyle", metalUI]),
    .testTarget(
        name: "CreatorSketchEditorTests",
        dependencies: [
            "CreatorSketchEditor", "CreatorSketch", "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI,
            metalUIPortableText, metalUISystemFonts,
        ]
    ),
    .testTarget(name: "CreatorGeometryTests", dependencies: ["CreatorGeometry"]),
    .testTarget(name: "CreatorSketchTests", dependencies: ["CreatorSketch", "CreatorGeometry"]),
    .testTarget(name: "CreatorImplicitTests",
                dependencies: ["CreatorImplicit", "CreatorGraph", "CreatorKernel", "CreatorGeometry"]),
    .testTarget(name: "CreatorKernelTests", dependencies: ["CreatorKernel", "CreatorGeometry"]),
    .testTarget(name: "CreatorGraphTests", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorSketch"]),
    .testTarget(
        name: "CreatorNodesTests",
        dependencies: ["CreatorNodes", "CreatorGraph", "CreatorImplicit", "CreatorKernel", "CreatorGeometry", "CreatorSketch"] + occt
    ),
    // CreatorOCCT is a test-only dependency: the offscreen ID-pass test renders a real OCCT box (spec §8).
    .testTarget(
        name: "CreatorViewportTests",
        dependencies: [
            "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI, metalUIPortableText, metalUISystemFonts,
            metalUISDL, metalUISDLGPU,
            // CreatorGraph's SHA256 hashes the shader sources for the freshness check against the build's SOURCE.sha256.
            "CreatorGraph",
        ] + occt
    ),
]

/// The OpenCascade toolkits the shim and the data exchange link, in the same order on every platform.
let occtLibraries = [
    "TKernel", "TKMath", "TKG2d", "TKG3d", "TKGeomBase", "TKGeomAlgo", "TKBRep", "TKTopAlgo",
    "TKPrim", "TKBO", "TKBool", "TKFillet", "TKOffset", "TKMesh", "TKShHealing",
    "TKXSBase", "TKDE", "TKDESTEP", "TKDESTL",
]

/// The linker flags per target platform (xp-2, spec section 3). macOS and Linux add the install's `lib` to the run-time search
/// path, so `swift run` and `swift test` find the libraries; Linux also searches `lib` beside the executable first
/// (`$ORIGIN/lib`, where `scripts/package-linux.sh` puts them). Windows has no rpath: the DLLs are found on `PATH` (CI adds the
/// install's `debug/bin`, or `bin` for a release build) or beside the executable (`scripts/package-windows.ps1`).
let occtLinkerFlags: [LinkerSetting] = [
    .unsafeFlags(["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"], .when(platforms: [.macOS])),
    .unsafeFlags(
        ["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "$ORIGIN/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"],
        .when(platforms: [.linux])
    ),
    // vcpkg's `x64-windows` triplet installs the release libraries in `lib` and `bin` and the debug ones in `debug/lib` and
    // `debug/bin`. A debug build (`swift test`) links the debug set, so Swift's and the shim's debug C runtime meets OpenCascade
    // built with the same one; a release build (the zip) links the release set.
    .unsafeFlags(["-L\(occtPrefix)/debug/lib"], .when(platforms: [.windows], configuration: .debug)),
    .unsafeFlags(["-L\(occtPrefix)/lib"], .when(platforms: [.windows], configuration: .release)),
]

targets += [
    .target(
        name: "COCCT",
        cxxSettings: [
            .unsafeFlags(["-isystem", "\(occtPrefix)/include/opencascade"]),
            // OCCT's headers include <windows.h>, whose min and max macros break std::min and std::max.
            .define("NOMINMAX", .when(platforms: [.windows])),
        ],
        linkerSettings: occtLinkerFlags + occtLibraries.map { .linkedLibrary($0) }
    ),
    .target(name: "CreatorOCCT", dependencies: ["COCCT", "CreatorKernel", "CreatorGeometry"]),
    .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT", "CreatorKernel", "CreatorGeometry"]),
]

#if os(macOS)
targets += [
    // A dev window for the viewport's human checks (docs/verification/human-checks.md, group V). Not the app (M6).
    .executableTarget(name: "ViewportHarness",
                      dependencies: ["CreatorViewport", "CreatorOCCT", "CreatorKernel", "CreatorGeometry", metalUI]),
    .executableTarget(
        name: "GraphPanelPreview",
        dependencies: ["CreatorEditor", "CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUI]
    ),
]
#endif

let package = Package(
    name: "MetalCreator",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../MetalUI", traits: metalUITraits),
    ],
    targets: targets,
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
