import Testing
@testable import CreatorOCCT

/// `occt_is_valid` answers 1, 0 or -1 (the checker itself threw); the kernel tells the last from a rejection.
struct OCCTValidityTests {
    @Test func theCheckersAnswerMapsToThreeStates() {
        #expect(OCCTValidity(status: 1) == .valid)
        #expect(OCCTValidity(status: 0) == .invalid)
        #expect(OCCTValidity(status: -1) == .unchecked)
    }

    @Test func aBoxIsValidAndIsValidAgreesWithValidity() throws {
        let box = try OCCTShape.box(10, 20, 30)
        let validity = OCCTKernel.serialized { box.validity }
        #expect(validity == .valid)
        #expect(OCCTKernel.serialized { box.isValid })
    }
}
