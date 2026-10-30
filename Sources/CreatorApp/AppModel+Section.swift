import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport

extension AppModel {
    /// Switches the section on or off (the top bar's toggle and View ▸ Show Section). The first time it starts on the axis plane
    /// nearest the camera, through the part's centre; with nothing shown and no settings it stays off. Off keeps the settings.
    func setSection(_ on: Bool) {
        if on {
            if document.section != nil {
                document.section?.isOn = true
            } else if let bounds = viewport.sceneBounds {
                document.section = SectionGeometry.starting(origin: nil, bounds: bounds, toEye: viewport.pose.toEye)
            }
        } else {
            document.section?.isOn = false
        }
        refreshScene()
    }

    /// "Section from Face" (section spec §3.2): the section on a flat face, at its surface and cutting the outside away. A face of a
    /// solid that is gone does nothing, and nothing starts while a sketch is open.
    func sectionFromFace(_ ref: ViewportFaceRef, _ pick: FacePick) {
        guard sketch == nil, viewport.items.indices.contains(ref.solidIndex) else { return }
        document.section = SectionSettings(isOn: true, reference: .face(pick), offset: 0, isFlipped: false)
        refreshScene()
    }

    /// Cuts away the other side.
    func flipSection() {
        guard document.section != nil else { return }
        document.section?.isFlipped.toggle()
        refreshScene()
    }

    /// Moves the plane to `millimetres` from its reference. Non-finite values are ignored.
    func setSectionOffset(_ millimetres: Double) {
        guard document.section != nil, millimetres.isFinite else { return }
        document.section?.offset = millimetres
        refreshScene()
    }

    /// Switches the section to an origin plane, through the part's centre (the reference alone changes without a scene).
    func setSectionOrigin(_ origin: SectionOrigin) {
        guard var settings = document.section else { return }
        settings.reference = .origin(origin)
        if let bounds = viewport.sceneBounds {
            let normal = SectionGeometry.frame(of: origin).normal
            settings.offset = bounds.center.dot(normal)
        }
        document.section = settings
        refreshScene()
    }

    /// A typed offset in the document's units; text that is not a finite length leaves the section as it is.
    @discardableResult
    func commitSectionOffset(text: String) -> Bool {
        guard document.section != nil, let value = document.units.parse(text, quantity: .length), value.isFinite else { return false }
        setSectionOffset(value)
        return true
    }
}
