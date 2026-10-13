import CreatorGraph
import CreatorKernel
import CreatorViewport

extension AppModel {
    /// "Scatter on Face" (fields spec §3.3): a Field Scatter holding the face's remembered pick (`layoutOnFace`).
    func scatterOnFace(_ ref: ViewportFaceRef, _ pick: FacePick) {
        layoutOnFace(ref, pick, as: .scatter)
    }
}
