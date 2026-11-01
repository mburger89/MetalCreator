import CreatorGraph
import CreatorKernel
import CreatorViewport

extension AppModel {
    /// Switches the zebra stripes on or off (the top bar's toggle, View menu and Z). Off keeps the settings; view state, so no
    /// command, no undo step and no edit.
    func setZebra(_ on: Bool) {
        if document.zebra == nil {
            guard on else { return }
            document.zebra = ZebraSettings()
        }
        document.zebra?.isOn = on
    }

    func setZebraDirection(_ direction: ZebraDirection) {
        guard document.zebra != nil else { return }
        document.zebra?.direction = direction
    }

    func setZebraStripes(_ count: Int) {
        guard document.zebra != nil else { return }
        document.zebra?.stripes = count
    }

    func setZebraBlackShare(_ share: Double) {
        guard document.zebra != nil else { return }
        document.zebra?.blackShare = share
    }

    /// Lock fixes the stripes to the camera as it is now (the live pose's right, up and toward-the-eye); unlocking clears it.
    func setZebraLock(_ on: Bool) {
        guard document.zebra != nil else { return }
        let pose = viewport.pose
        document.zebra?.lock = on ? ZebraFrame(right: pose.right, up: pose.up, toEye: pose.toEye) : nil
    }

    /// Whether the stripes are drawn: on, and no sketch open.
    var showsZebra: Bool { document.zebra?.isOn == true && sketch == nil }

    /// Follows the zebra with the display meshes' angle (sketch mode drops back to the standard one: its scene is all ghosts,
    /// which are never striped). The finer meshes apply at the next `show(_:)`, so `refreshScene` calls this first.
    /// Returns whether the mesh angle changed.
    func followZebraAngle() -> Bool {
        let angle = showsZebra ? DisplayAngle.zebra : DisplayAngle.standard
        guard viewport.displayAngle != angle else { return false }
        viewport.displayAngle = angle
        return true
    }

    func followZebra() {
        guard showsZebra, let settings = document.zebra else {
            viewport.showZebra(nil)
            return
        }
        let frame = settings.lock.map { ViewportZebra.Frame(right: $0.right, up: $0.up, toEye: $0.toEye) }
        viewport.showZebra(ViewportZebra(direction: settings.direction == .horizontal ? .horizontal : .vertical,
                                         stripes: settings.stripes, blackShare: settings.blackShare, lock: frame))
    }
}
