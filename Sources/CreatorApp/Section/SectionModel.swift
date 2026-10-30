import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Observation

/// What the viewport is told to show for the section: the plane, the clip and its handle, and the face's title for the panel.
struct SectionShown: Equatable {
    var frame: SectionFrame
    var clip: ViewportClip
    var handle: ViewportHandle?
    var faceTitle: String?
}

/// The section view's derived state (section spec §3, §5): the settings live on the document (`DocumentModel.section`, view state,
/// no undo step); this resolves them against the scene into a plane, a clip and a handle. It also remembers the last plane a
/// picked face had, so a section whose face is gone (or still evaluating) keeps cutting where it was and says so.
/// It cuts wherever the viewport can draw a clip, which is on every platform.
@MainActor
@Observable
final class SectionModel {
    nonisolated static let handleID = "section-plane"

    /// `nil` when the section is off, hidden (sketch mode), has nothing to cut or its face is lost and was never seen.
    private(set) var shown: SectionShown?
    /// The panel's line about the face; `nil` when the face is fine.
    private(set) var note: String?
    /// The last plane each picked face had.
    private var remembered: [(pick: FacePick, frame: SectionFrame)] = []

    func update(_ settings: SectionSettings?, items: [ViewportItem], bounds: BoundingBox?, hidden: Bool,
                nodeName: (NodeID) -> String? = { _ in nil }) {
        var next: SectionShown?
        var nextNote: String?
        if let settings, settings.isOn, !hidden, let bounds {
            var frame: SectionFrame?
            var title: String?
            switch settings.reference {
            case .origin(let origin):
                frame = SectionGeometry.frame(of: origin)
            case .face(let pick):
                if let found = SectionGeometry.resolveFace(pick, in: items), let resolved = SectionGeometry.frame(ofFace: found.face) {
                    frame = resolved
                    remember(pick, resolved)
                    if found.isGuess {
                        nextNote = "The picked face was merged with a face from another part of the model that has since changed, "
                            + "so it isn't clear which part was picked. The section sits on the closest one; "
                            + "use Section from Face again to settle it."
                    }
                    title = Self.title(of: found.face, nodeName: nodeName)
                } else {
                    frame = remembered.first { $0.pick == pick }?.frame
                    nextNote = "The section's face no longer exists."
                    if frame != nil { title = "Face" }
                }
            }
            if let frame {
                next = SectionShown(frame: frame,
                                    clip: SectionGeometry.clip(frame, offset: settings.offset, isFlipped: settings.isFlipped),
                                    handle: SectionGeometry.handle(frame, offset: settings.offset, bounds: bounds),
                                    faceTitle: title)
            }
        }
        if shown != next { shown = next }
        if note != nextNote { note = nextNote }
    }

    /// Forgets the remembered face planes (New, Open).
    func reset() {
        remembered = []
        shown = nil
        note = nil
    }

    private func remember(_ pick: FacePick, _ frame: SectionFrame) {
        if let index = remembered.firstIndex(where: { $0.pick == pick }) {
            remembered[index].frame = frame
        } else {
            remembered.append((pick, frame))
        }
    }

    /// "Face of Box" when exactly one node made the face, else "Face".
    private static func title(of face: FaceInfo, nodeName: (NodeID) -> String?) -> String {
        let nodes = Set(face.tags.map(\.node))
        if nodes.count == 1, let node = nodes.first, let name = nodeName(node), !name.isEmpty { return "Face of \(name)" }
        return "Face"
    }
}
