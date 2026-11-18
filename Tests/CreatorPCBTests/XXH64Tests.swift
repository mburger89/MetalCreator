import Testing
@testable import CreatorPCB

struct XXH64Tests {
    private func hash(_ bytes: [UInt8], seed: UInt64 = 0) -> UInt64 {
        bytes.withUnsafeBytes { XXH64.hash($0, seed: seed) }
    }

    /// Values from an independent reference implementation; the low 32 bits of each also match the checksum `zstd` wrote.
    @Test func vectors() {
        #expect(hash([]) == 0xEF46_DB37_51D8_E999)
        #expect(hash(Array("a".utf8)) == 0xD24E_C4F1_A98C_6E5B)
        #expect(hash(Array(0..<5)) == 0xDD02_7438_6E26_030C)
        #expect(hash(Array(0..<40)) == 0xF5DA_40F1_B117_41E9)
        #expect(hash(Array(0..<100)) == 0x6AC1_E580_3216_6597)
        #expect(hash((0..<300).map { UInt8($0 * 7 % 256) }) == 0x240B_95ED_F72F_18E0)
    }
}
