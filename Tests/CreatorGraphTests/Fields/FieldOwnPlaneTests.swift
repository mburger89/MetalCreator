import CreatorGeometry
import Testing
@testable import CreatorGraph

/// `Field.ownPlane`: the plane a gradient or an image lies on, which the preview's slice plane (7b-3) starts on.
struct FieldOwnPlaneTests {
    let tilted = Plane(origin: Vector3(0, 0, 5), normal: .unitX, xAxis: .unitY)
    let picture = GreyImage(width: 1, height: 1, pixels: [100])

    @Test func aGradientAndAnImageLieOnTheirOwnPlane() throws {
        #expect(Field.linearGradient(plane: tilted, length: 10).ownPlane == tilted)
        let image = Field.image(try #require(picture), plane: tilted, width: 4, height: 4, edges: .tile)
        #expect(image.ownPlane == tilted)
    }

    @Test func theOtherSourcesHaveNone() {
        #expect(Field.constant(1).ownPlane == nil)
        #expect(Field.radialGradient(center: .zero, radius: 3).ownPlane == nil)
        #expect(Field.noise(seed: 1, scale: 5, octaves: 2).ownPlane == nil)
        #expect(Field.distance(.point(.zero), signed: false).ownPlane == nil)
    }

    @Test func anExpressionTakesTheFirstPlaneFoundFromTheLeft() throws {
        let image = Field.image(try #require(picture), plane: tilted, width: 4, height: 4, edges: .clamp)
        let gradient = Field.linearGradient(plane: .xy, length: 2)
        let noise = Field.noise(seed: 1, scale: 5, octaves: 2)
        #expect(Field.add(noise, .remap(image, fromLow: 0, fromHigh: 1, toLow: 0, toHigh: 5, clamped: true)).ownPlane == tilted)
        #expect(Field.multiply(gradient, image).ownPlane == .xy)
        #expect(Field.multiply(image, gradient).ownPlane == tilted)
        #expect(Field.clamp(.smoothMinimum(noise, .constant(2), width: 1), low: 0, high: 1).ownPlane == nil)
    }
}
