import CreatorKernel

/// The OCCT shape behind a `Solid`.
final class OCCTSolidStorage: SolidStorage {
    let shape: OCCTShape
    let estimatedBytes: Int

    init(shape: OCCTShape, faceCount: Int) {
        self.shape = shape
        // Rough: B-rep plus geometry per face, plus a fixed overhead.
        self.estimatedBytes = 4096 + faceCount * 2048
    }
}
