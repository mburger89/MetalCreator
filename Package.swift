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

let package = Package(
    name: "MetalCreator",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "COCCT",
            cxxSettings: [.unsafeFlags(["-isystem", "\(occtPrefix)/include/opencascade"])],
            linkerSettings: [
                .unsafeFlags(["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"]),
            ] + occtLibraries.map { .linkedLibrary($0) }
        ),
        .target(name: "CreatorOCCT", dependencies: ["COCCT"]),
        .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT"]),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
