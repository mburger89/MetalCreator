import Testing
@testable import CreatorKernel
@testable import CreatorOCCT

struct KernelErrorMappingTests {
    @Test func rawOCCTTextBecomesAGenericSentence() {
        let generic = "the geometry could not be built with these inputs."
        #expect(KernelError.plainReason("occt: gp_Ax2() - parallel vectors") == generic)
        #expect(KernelError.plainReason("occt: Standard_ConstructionError") == generic)
    }

    @Test func unknownOCCTErrorBecomesAGenericSentence() {
        let generic = "the geometry could not be built with these inputs."
        // The shim's and Swift's fallback text when OCCT gave no message.
        #expect(KernelError.plainReason("unknown OCCT error") == generic)
        #expect(KernelError.plainReason("Unknown occt error.") == generic)
    }

    @Test func shimMessagesKeepTheirText() {
        #expect(KernelError.plainReason("a line in the profile has zero length") == "a line in the profile has zero length.")
    }
}
