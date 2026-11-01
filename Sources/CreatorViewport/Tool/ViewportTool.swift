import CreatorGeometry

/// Something that takes the viewport's primary pointer input while it is set (`ViewportModel.tool`): the sketch
/// editor (sketcher spec §8). The viewport keeps navigation: right-drag orbits, middle-drag pans, scroll and pinch
/// zoom, Shift- and ⌥-drags pan and zoom, and the view cube and handles work as before, unless the tool asks for
/// `.planar` navigation (`navigation`), which never turns the camera. Everything else a primary button does is
/// offered to the tool first. Each call carries the camera it was made in.
@MainActor
public protocol ViewportTool: AnyObject {
    /// How the camera moves while this tool is set (default: `.free`).
    var navigation: ViewportNavigation { get }
    /// What F frames while this tool is set, instead of the selection or the scene (default: `nil`, the usual).
    var framingBounds: BoundingBox? { get }
    /// The pointer is over `point` with no drag under way (`nil`: it left the view), with `modifiers` held: it moved, the
    /// camera moved under it, or a modifier changed while it stayed still (`ViewportModel.modifiersChanged(_:)`, MetalUI
    /// C16's `onModifierKeysChanged`). Only `ViewportModifiers.hoverMask` is reported.
    func pointerMoved(to point: ScreenPoint?, modifiers: ViewportModifiers, projector: ViewportProjector)
    /// A click off the view cube and the handles, with the modifiers held at its press (MetalUI C16's
    /// `SpatialTapGesture.Value.modifiers`). Return true to claim it; unclaimed, the viewport reports the pick
    /// under it as usual (`ViewportEvents.clicked`).
    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    /// A click `clicked(at:…)` declined, with the face or edge the ID pass found under it (`nil`: empty space), for a
    /// tool that works on the model (the sketch editor's Project). Return true to claim it; unclaimed, the viewport
    /// reports the pick as usual (`ViewportEvents.clicked`). It is not called for a click the view cube or a handle took.
    func clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                      projector: ViewportProjector) -> Bool
    /// A primary drag with no navigating modifier (Shift, ⌥) begins at `point`, off the cube and the handles.
    /// Return true to take it: its moves and release then come here, and the camera stays put. Declined, it orbits
    /// (pans with `.planar` navigation).
    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    /// A primary drag with no navigating modifier begins on the text of the drawn dimension `id`. Offered before
    /// `dragBegan(at:…)` (default: false). Claimed, its moves and release come to `dragMoved`/`dragEnded` as for any claimed drag.
    func dragBegan(onDimension id: OverlayDimensionID, at point: ScreenPoint, modifiers: ViewportModifiers,
                   projector: ViewportProjector) -> Bool
    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector)
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector)
    /// The entries the tool adds to a right-click at `point` (default: none). They follow the viewport's own, and also appear where
    /// the viewport has none (off the model).
    func menuActions(at point: ScreenPoint) -> [HostMenuAction]
    /// Runs an entry from `menuActions(at:)` (default: nothing).
    func performMenuAction(_ action: HostMenuAction)
    /// The model element under the pointer changed (`nil`: nothing, or the pointer left). Called after
    /// `ViewportModel.hovered` is set, on every platform (on SDL when a hover pick lands), with the last hover point
    /// (default: nothing).
    func hoverChanged(_ target: PickTarget?, at point: ScreenPoint?, projector: ViewportProjector)
    /// Whether the face menu offers Section from Face while this tool is set; Look At is always offered (default: false).
    var offersSectionFromFace: Bool { get }
}

extension ViewportTool {
    public var navigation: ViewportNavigation { .free }
    public var framingBounds: BoundingBox? { nil }
    public func dragBegan(onDimension id: OverlayDimensionID, at point: ScreenPoint, modifiers: ViewportModifiers,
                          projector: ViewportProjector) -> Bool {
        false
    }
    public func hoverChanged(_ target: PickTarget?, at point: ScreenPoint?, projector: ViewportProjector) {}
    public var offersSectionFromFace: Bool { false }
    public func menuActions(at point: ScreenPoint) -> [HostMenuAction] { [] }
    public func performMenuAction(_ action: HostMenuAction) {}
    public func clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                             projector: ViewportProjector) -> Bool {
        false
    }
}
