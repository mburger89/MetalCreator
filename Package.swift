// swift-tools-version: 6.4
import PackageDescription

/// Homebrew's OpenCascade install. The bottle ships CMake configs but no pkg-config file,
/// so the shim is pointed at it directly. Only the COCCT target uses these flags.
let occtPrefix = "/opt/homebrew/opt/opencascade"
let occtLibraries = [
    "TKernel", "TKMath", "TKG2d", "TKG3d", "TKGeomBase", "TKGeomAlgo", "TKBRep", "TKTopAlgo",
    "TKPrim", "TKBO", "TKBool", "TKFillet", "TKOffset", "TKMesh", "TKShHealing",
    "TKXSBase", "TKDE", "TKDESTEP", "TKDESTL",
]

/// The UI framework (spec §3.1). Its gaps are logged in docs/metalui-gaps.md and fixed in MetalUI.
let metalUI: Target.Dependency = .product(name: "MetalUI", package: "MetalUI")

let package = Package(
    name: "MetalCreator",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../MetalUI"),
    ],
    targets: [
        .target(
            name: "COCCT",
            cxxSettings: [.unsafeFlags(["-isystem", "\(occtPrefix)/include/opencascade"])],
            linkerSettings: [
                .unsafeFlags(["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"]),
            ] + occtLibraries.map { .linkedLibrary($0) }
        ),
        .target(name: "CreatorOCCT", dependencies: ["COCCT", "CreatorKernel", "CreatorGeometry"]),
        .target(name: "CreatorGeometry"),
        .target(name: "CreatorSketch", dependencies: ["CreatorGeometry"]),
        .target(name: "CreatorKernel", dependencies: ["CreatorGeometry"]),
        // CreatorSketch: `ConstantValue.sketch` (S4). The Sketch node in CreatorNodes solves it.
        .target(name: "CreatorGraph", dependencies: ["CreatorKernel", "CreatorGeometry", "CreatorSketch"]),
        .target(name: "CreatorNodes", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorSketch"]),
        // Colour themes (spec §6.6, Dracula by default): the roles, the built-in themes and the `ThemeStore` that
        // the editor's views and the viewport's GPU colours read.
        .target(name: "CreatorStyle", dependencies: [metalUI]),
        .target(name: "CreatorViewport", dependencies: ["CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
        // A dev window for the viewport's human checks (docs/verification/human-checks.md, group V). Not the app (M6).
        .executableTarget(name: "ViewportHarness",
                          dependencies: ["CreatorViewport", "CreatorOCCT", "CreatorKernel", "CreatorGeometry", metalUI]),
        .target(name: "CreatorEditor", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
        .executableTarget(
            name: "GraphPanelPreview",
            dependencies: ["CreatorEditor", "CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUI]
        ),
        // The in-viewport sketch editor (sketcher spec §8, S5): `SketchEditorModel`, its tools and its views. Graph-free:
        // the app shell turns its commits into graph commands. CreatorStyle for the theme's colours.
        .target(name: "CreatorSketchEditor",
                dependencies: ["CreatorSketch", "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
        // The app shell (M6): the one target that joins the graph, the nodes, the viewport and the editors. A library,
        // so its model is tested; the executable below only opens the window.
        .target(
            name: "CreatorApp",
            dependencies: [
                "CreatorEditor", "CreatorViewport", "CreatorNodes", "CreatorGraph", "CreatorKernel", "CreatorGeometry",
                "CreatorStyle", "CreatorSketch", "CreatorSketchEditor", metalUI,
            ]
        ),
        .executableTarget(name: "MetalCreatorApp", dependencies: ["CreatorApp", "CreatorOCCT", metalUI]),
        // CreatorOCCT is a test-only dependency: the app-level acceptance test runs the §7.2 bracket on OCCT.
        .testTarget(
            name: "CreatorAppTests",
            dependencies: [
                "CreatorApp", "CreatorEditor", "CreatorViewport", "CreatorNodes", "CreatorGraph", "CreatorKernel",
                "CreatorGeometry", "CreatorOCCT", "CreatorStyle", "CreatorSketch", "CreatorSketchEditor", metalUI,
            ]
        ),
        // CreatorNodes is a test-only dependency: BuiltInNodesInspectorTests runs the real M3
        // definitions through the inspector; the CreatorEditor library never imports it.
        .testTarget(
            name: "CreatorEditorTests",
            dependencies: [
                "CreatorEditor", "CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorNodes", "CreatorStyle", metalUI,
            ]
        ),
        .testTarget(name: "CreatorStyleTests", dependencies: ["CreatorStyle", metalUI]),
        .testTarget(
            name: "CreatorSketchEditorTests",
            dependencies: [
                "CreatorSketchEditor", "CreatorSketch", "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI,
            ]
        ),
        .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT", "CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorGeometryTests", dependencies: ["CreatorGeometry"]),
        .testTarget(name: "CreatorSketchTests", dependencies: ["CreatorSketch", "CreatorGeometry"]),
        .testTarget(name: "CreatorKernelTests", dependencies: ["CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorGraphTests", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorSketch"]),
        .testTarget(name: "CreatorNodesTests",
                    dependencies: ["CreatorNodes", "CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorSketch", "CreatorOCCT"]),
        // CreatorOCCT is a test-only dependency: the offscreen ID-pass test renders a real OCCT box (spec §8).
        .testTarget(name: "CreatorViewportTests",
                    dependencies: ["CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorOCCT", "CreatorStyle", metalUI]),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
