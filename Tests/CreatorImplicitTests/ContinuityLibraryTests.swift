import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// `ContinuityLibrary.strutCopy` makes the copy of `strutBody` that joins its struts with a higher smooth minimum. It must never be empty.
struct ContinuityLibraryTests {
    static let libraries: [(name: String, lattices: String)] = [
        ("MSL", ImplicitShaderLibrary.lattices), ("HLSL", HLSLShaderLibrary.lattices),
    ]

    @Test(arguments: [BlendContinuity.g2, .g3], libraries.indices)
    func theStrutCopyIsRenamedAndUsesOneSmoothMinimum(_ continuity: BlendContinuity, _ index: Int) {
        let (name, lattices) = Self.libraries[index]
        let copy = ContinuityLibrary.strutCopy(in: lattices, for: continuity)
        let strut = ContinuityLibrary.strutName(continuity)
        let smooth = ContinuityLibrary.smoothMinName(continuity)
        #expect(!copy.isEmpty, "\(name) \(continuity.label): the copy is empty")
        #expect(copy.contains("float \(strut)("), "\(name) \(continuity.label): the renamed signature")
        #expect(!copy.contains("float strutBody("))
        #expect(copy.components(separatedBy: "\(smooth)(").count - 1 == 1, "\(name) \(continuity.label): exactly one \(smooth)( call")
        #expect(!copy.contains(" smoothMin("))
    }
}
