/// What `ViewportView`'s `onGeometryChange` watches: the view's size and which model it is for. The model is part of
/// the value so that a replaced viewport (New, Open build a fresh `ViewportModel` under the same view) is told the
/// size again, though the size itself has not changed.
struct ViewSizeReport: Equatable {
    let model: ObjectIdentifier
    let size: ViewportSize
}
