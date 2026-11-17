import CreatorKernel
import Testing
@testable import CreatorPCB

struct KiCadKeyTests {
    @Test func publishedVectors() {
        #expect(KiCadKey.fnv1a64("") == 0xCBF2_9CE4_8422_2325)
        #expect(KiCadKey.fnv1a64("a") == 0xAF63_DC4C_8601_EC8C)
        #expect(KiCadKey.fnv1a64("foobar") == 0x8594_4171_F739_67E8)
    }

    @Test func itemsAreNegativeAndNeverAPath() {
        for index in 0..<1_000 {
            let item = KiCadKey.item(for: "pad:H\(index):1")
            #expect(item < 0)
            #expect(item.magnitude <= UInt(1) << 60)
            #expect(InstancePath.indices(ofItem: item) == nil)
        }
    }

    @Test func padKeyIsPinned() {
        #expect(KiCadKey.item(for: "pad:H1:1") == -370_230_786_866_024_679)
    }
}
