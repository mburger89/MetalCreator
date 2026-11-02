import CreatorGeometry

/// What a shader adds to its library for the blend continuities its tree uses (G-a of the G2 surfacing spec), in either dialect: the smooth
/// minimum of each higher continuity, and a copy of `strutBody` that joins its struts with it. G1 is the library's own `smoothMin` and
/// `strutBody`, whose text never changes, so a tree that uses G1 alone adds nothing and its source is what it always was. The
/// continuity is part of the source, so a G1 tree and a G2 tree of one shape do not share a compiled kernel.
enum ContinuityLibrary {
    static func smoothMinName(_ continuity: BlendContinuity) -> String {
        switch continuity {
        case .g1: "smoothMin"
        case .g2: "smoothMin2"
        case .g3: "smoothMin3"
        }
    }

    static func strutName(_ continuity: BlendContinuity) -> String {
        switch continuity {
        case .g1: "strutBody"
        case .g2: "strutBody2"
        case .g3: "strutBody3"
        }
    }

    /// The text to follow the library: `smoothMinimum(c)` for each higher continuity a tree's blends or struts use, then
    /// `strutBody`'s copy for each higher continuity its struts use. Empty when there is none.
    static func extras(smoothMinimums: Set<BlendContinuity>, struts: Set<BlendContinuity>,
                       smoothMinimum: (BlendContinuity) -> String, strutBody lattices: String) -> String {
        let higher = BlendContinuity.allCases.filter { $0 != .g1 }
        var pieces: [String] = []
        for continuity in higher where smoothMinimums.contains(continuity) || struts.contains(continuity) {
            pieces.append(smoothMinimum(continuity))
        }
        for continuity in higher where struts.contains(continuity) {
            pieces.append(strutCopy(in: lattices, for: continuity))
        }
        return pieces.isEmpty ? "" : "\n\n" + pieces.joined(separator: "\n\n")
    }

    /// The library's `strutBody` with its name and its `smoothMin` changed to the continuity's.
    static func strutCopy(in lattices: String, for continuity: BlendContinuity) -> String {
        guard let name = lattices.range(of: "float strutBody("),
              let start = lattices[..<name.lowerBound].lastIndex(of: "\n"),
              let end = lattices.range(of: "\n}\n", range: name.upperBound..<lattices.endIndex) else { return "" }
        let text = String(lattices[lattices.index(after: start)..<end.upperBound])
        return text.replacingOccurrences(of: "strutBody(", with: strutName(continuity) + "(")
            .replacingOccurrences(of: "smoothMin(", with: smoothMinName(continuity) + "(")
            .trimmingCharacters(in: .newlines)
    }
}

extension ImplicitCompiler.Generator {
    /// What follows the library: the smooth minimums and strut bodies of the higher continuities this tree used; empty for G1 alone.
    func libraryExtras(dialect: ShaderDialect) -> String {
        switch dialect {
        case .msl: ImplicitShaderLibrary.extras(smoothMinimums: blendContinuities, struts: strutContinuities)
        case .hlsl: HLSLShaderLibrary.extras(smoothMinimums: blendContinuities, struts: strutContinuities)
        }
    }
}
