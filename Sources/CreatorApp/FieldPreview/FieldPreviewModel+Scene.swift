import CreatorGraph
import CreatorStyle
import CreatorViewport

extension FieldPreviewModel {
    /// Whether the followed field has a plane of its own for the slice to lie on.
    var hasOwnPlane: Bool { field?.ownPlane != nil }

    /// The smallest to the largest finite value sampled on the parts and, while it is shown, on the slice.
    var extent: ClosedRange<Double>? {
        var extents = tints.values.compactMap(\.tint.extent)
        if choice != .hidden, let slice = grid?.extent { extents.append(slice) }
        guard let low = extents.map(\.lowerBound).min(), let high = extents.map(\.upperBound).max() else { return nil }
        return low...high
    }

    /// The ramp's range for what is sampled: automatic, centred on 0 for a signed distance, or fixed to 0…1.
    var range: FieldPreviewRange? {
        guard let field else { return nil }
        return FieldPreviewRange.make(extent: extent, centredOnZero: field.isSignedDistance, fixedToUnit: usesUnitRange)
    }

    /// What the legend draws, or `nil` while there is nothing to show (nothing followed, or nothing sampled yet).
    var legend: FieldLegend? {
        guard node != nil, let field, range != nil || failure != nil else { return nil }
        return FieldLegend(range: range, unit: field.unit, isCoarse: tints.values.contains { $0.tint.isCoarse },
                           usesUnitRange: usesUnitRange, choice: choice, hasOwnPlane: hasOwnPlane, failure: failure)
    }

    /// `items` with the tint on each opaque, non-guide item the model has sampled; the others as they are.
    func tinted(_ items: [ViewportItem], colors: ThemeColors) -> [ViewportItem] {
        guard !tints.isEmpty, let ramp = range?.ramp(colors: colors) else { return items }
        return items.map { item in
            guard !item.isGhost, !item.isGuide, let entry = tints[ObjectIdentifier(item.solid)] else { return item }
            var tinted = item
            tinted.fieldValues = entry.tint.values
            tinted.fieldRamp = ramp
            return tinted
        }
    }

    /// The slice for the viewport in the theme's ramp, or `nil` while it is hidden or not yet sampled.
    func viewportSlice(colors: ThemeColors) -> ViewportSlice? {
        guard choice != .hidden, var slice = grid?.slice, let ramp = range?.ramp(colors: colors) else { return nil }
        slice.ramp = ramp
        return slice
    }

    /// The handle that moves the slice along its normal, from the plane at offset 0.
    var sliceHandle: ViewportHandle? {
        guard let pose else { return nil }
        return ViewportHandle(id: Self.sliceHandleID, anchor: pose.plane.origin, direction: pose.plane.normal, value: offset,
                              range: -pose.offsetLimit...pose.offsetLimit, style: .linear, tint: .solid)
    }
}
