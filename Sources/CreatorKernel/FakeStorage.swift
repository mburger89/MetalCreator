/// Storage for `FakeKernel` solids, which carry no real geometry.
final class FakeStorage: SolidStorage {
    var estimatedBytes: Int { 64 }
}
