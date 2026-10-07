import Testing
@testable import CreatorKernel
@testable import CreatorOCCT

struct KernelErrorMappingTests {
    @Test func rawOCCTTextBecomesAGenericSentence() {
        let generic = "the geometry could not be built with these inputs."
        #expect(KernelError.plainReason("occt: gp_Ax2() - parallel vectors") == generic)
        #expect(KernelError.plainReason("occt: Standard_ConstructionError") == generic)
    }

    @Test func shimMessagesKeepTheirText() {
        #expect(KernelError.plainReason("a line in the profile has zero length") == "a line in the profile has zero length.")
    }
}
