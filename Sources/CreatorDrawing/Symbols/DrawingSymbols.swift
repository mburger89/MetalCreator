import CreatorGeometry
import Foundation

/// Drawn symbols (plan R17), never glyphs.
public enum DrawingSymbols {
    /// The projection symbol's box: 6h by 2h, the centre line's overrun included.
    public static func projectionSymbolSize(h: Double) -> Vector2 { Vector2(6 * h, 2 * h) }

    /// ISO 5456-2's projection symbol about `center`: a truncated cone seen side on and end on (two circles, diameters 2h
    /// and h), 1.5h apart, with a thin centre line running 0.25h past each end. First angle has the cone on the left with
    /// its big end at the left; third angle has the circles on the left and the cone's big end toward them.
    public static func projectionSymbol(
        firstAngle: Bool, center: Vector2, h: Double, thin: Double = DrawingStyle.iso.thin
    ) -> [SheetStroke] {
        let cx = center.x, cy = center.y
        let coneBig: Double, coneSmall: Double, circleX: Double
        if firstAngle {
            coneBig = cx - 2.75 * h
            coneSmall = cx - 0.75 * h
            circleX = cx + 1.75 * h
        } else {
            coneBig = cx + 0.75 * h
            coneSmall = cx + 2.75 * h
            circleX = cx - 1.75 * h
        }
        let cone: [Vector2] = [
            Vector2(coneBig, cy - h), Vector2(coneSmall, cy - h / 2), Vector2(coneSmall, cy + h / 2),
            Vector2(coneBig, cy + h), Vector2(coneBig, cy - h),
        ]
        let circleCentre = Vector2(circleX, cy)
        func stroke(_ segment: SheetSegment) -> SheetStroke {
            SheetStroke(segments: [segment], width: thin, layer: .frame)
        }
        return [
            stroke(.polyline(cone)),
            stroke(.arc(center: circleCentre, radius: h, start: 0, sweep: 2 * .pi)),
            stroke(.arc(center: circleCentre, radius: h / 2, start: 0, sweep: 2 * .pi)),
            stroke(.line(Vector2(cx - 3 * h, cy), Vector2(cx + 3 * h, cy))),
        ]
    }
}
