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
        .target(name: "CreatorKernel", dependencies: ["CreatorGeometry"]),
        .target(name: "CreatorGraph", dependencies: ["CreatorKernel", "CreatorGeometry"]),
        .target(name: "CreatorNodes", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry"]),
        .target(name: "CreatorViewport", dependencies: ["CreatorKernel", "CreatorGeometry", metalUI]),
        .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT", "CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorGeometryTests", dependencies: ["CreatorGeometry"]),
        .testTarget(name: "CreatorKernelTests", dependencies: ["CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorGraphTests", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorNodesTests",
                    dependencies: ["CreatorNodes", "CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorOCCT"]),
        // CreatorOCCT is a test-only dependency: the offscreen ID-pass test renders a real OCCT box (spec §8).
        .testTarget(name: "CreatorViewportTests",
                    dependencies: ["CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorOCCT", metalUI]),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
