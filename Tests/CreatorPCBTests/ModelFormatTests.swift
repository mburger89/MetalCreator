import Foundation
import Testing
@testable import CreatorPCB

struct ModelFormatTests {
    @Test func extensions() {
        let table: [(String, ModelFormat)] = [
            ("a.stp", .step), ("a.STEP", .step), ("a.stpz", .stepGzip), ("a.stepz", .stepGzip),
            ("a.stp.gz", .stepGzip), ("a.STEP.GZ", .stepGzip), ("a.igs", .iges), ("a.iges", .iges),
            ("a.wrl", .vrml), ("a.wrz", .vrmlGzip), ("a.x3d", .x3d), ("a.idf", .idf),
            ("a.emn", .unknown), ("a.png", .unknown), ("noext", .unknown),
        ]
        for (name, format) in table { #expect(ModelFormat(fileName: name) == format, "\(name)") }
    }

    private static let iges: Data = {
        var line = String(repeating: " ", count: 72) + "S      1"
        line += "\n"
        return Data(line.utf8)
    }()

    private static let samples: [(ModelFormat, Data)] = [
        (.step, Data("\n  ISO-10303-21;\nHEADER;".utf8)),
        (.stepGzip, Data([0x1F, 0x8B, 0x08, 0x00])),
        (.iges, iges),
        (.vrml, Data("#VRML V2.0 utf8\n".utf8)),
        (.vrmlGzip, Data([0x1F, 0x8B, 0x08])),
        (.x3d, Data("<?xml version='1.0'?><X3D version='3.3'>".utf8)),
        (.idf, Data("\n.HEADER\nBOARD_FILE".utf8)),
    ]

    @Test func matchesOwnBytes() {
        for (format, bytes) in Self.samples { #expect(format.matches(bytes), "\(format)") }
        #expect(ModelFormat.vrml.matches(Data("#VRML V1.0 ascii".utf8)))
    }

    @Test func pngMatchesNothing() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
        for format in [ModelFormat.step, .stepGzip, .iges, .vrml, .vrmlGzip, .x3d, .idf, .unknown] {
            #expect(!format.matches(png), "\(format)")
        }
    }

    @Test func nearMisses() {
        let igesWrong = Data((String(repeating: " ", count: 72) + "G      1\n").utf8)
        #expect(!ModelFormat.iges.matches(igesWrong))
        #expect(!ModelFormat.iges.matches(Data("short S\n".utf8)))
        #expect(!ModelFormat.step.matches(Data("ISO-10303-22;".utf8)))
        var late = Data(repeating: 0x20, count: 4096)
        late.append(Data("<X3D>".utf8))
        #expect(!ModelFormat.x3d.matches(late))
        #expect(!ModelFormat.step.matches(Data([0x1F, 0x8B, 0x08, 0x00])))
        #expect(!ModelFormat.vrml.matches(Data(" #VRML V2.0 utf8".utf8)))
        #expect(!ModelFormat.vrml.matches(Data("#VRML V3.0".utf8)))
        #expect(!ModelFormat.stepGzip.matches(Data([0x1F])))
        #expect(!ModelFormat.idf.matches(Data("BOARD\n.HEADER".utf8)))
    }
}
