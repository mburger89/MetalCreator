import Testing
@testable import CreatorGraph

/// `GreyImage` (fields spec §5): bilinear reads, tiling and clamping, and the inputs a hostile or careless caller can give.
struct GreyImageTests {
    /// Two columns, two rows: black and white on the top row, white and black below.
    static let checker = GreyImage(width: 2, height: 2, pixels: [0, 65_535, 65_535, 0])

    @Test func anImageNeedsPositiveSidesAndExactlyAsManyValuesAsPixels() {
        #expect(GreyImage(width: 0, height: 2, pixels: []) == nil)
        #expect(GreyImage(width: 2, height: -1, pixels: []) == nil)
        #expect(GreyImage(width: 2, height: 2, pixels: [1, 2, 3]) == nil)
        #expect(GreyImage(width: Int.max, height: 2, pixels: [1, 2]) == nil, "the product overflows")
        #expect(Self.checker?.byteCount == 8)
    }

    @Test func pixelCentresReadBackExactlyAndTheMiddleIsTheMean() throws {
        let image = try #require(Self.checker)
        #expect(image.value(u: 0.25, v: 0.25, edges: .clamp) == 0)
        #expect(image.value(u: 0.75, v: 0.25, edges: .clamp) == 1)
        #expect(image.value(u: 0.25, v: 0.75, edges: .clamp) == 1)
        #expect(image.value(u: 0.75, v: 0.75, edges: .clamp) == 0)
        #expect(image.value(u: 0.5, v: 0.5, edges: .clamp) == 0.5)
        #expect(image.value(u: 0.5, v: 0.25, edges: .clamp) == 0.5, "halfway along the top row")
    }

    @Test func clampHoldsTheEdgePixelsOutsideThePicture() throws {
        let image = try #require(Self.checker)
        let cases = [
            (-3.0, 0.25, 0.0), (0.0, 0.25, 0.0), (1.0, 0.25, 1.0), (40.0, 0.25, 1.0), (0.75, -9.0, 1.0),
            (0.75, 9.0, 0.0), (-1e300, -1e300, 0.0), (1e300, 1e300, 0.0),
        ]
        for (u, v, expected) in cases {
            #expect(image.value(u: u, v: v, edges: .clamp) == expected, "u \(u), v \(v)")
        }
    }

    @Test func tileRepeatsThePictureAndBlendsAcrossTheSeam() throws {
        let image = try #require(Self.checker)
        #expect(image.value(u: 1.25, v: 0.25, edges: .tile) == image.value(u: 0.25, v: 0.25, edges: .tile))
        #expect(image.value(u: -0.75, v: 1.75, edges: .tile) == image.value(u: 0.25, v: 0.75, edges: .tile))
        #expect(image.value(u: 1.0, v: 0.25, edges: .tile) == 0.5, "the right edge's white meets the left edge's black")
        #expect(image.value(u: 1.0, v: 0.25, edges: .clamp) == 1, "clamp does not wrap")
    }

    @Test func theBrightestAndDarkestPixelsAreExactlyOneAndZero() throws {
        let image = try #require(GreyImage(width: 1, height: 1, pixels: [65_535]))
        for edges in ImageEdges.allCases {
            #expect(image.value(u: 0.3, v: 0.9, edges: edges) == 1)
            #expect(image.value(u: -7.5, v: 12.5, edges: edges) == 1)
        }
    }

    @Test func nonFiniteAndHugeCoordinatesNeverTrapAndStayInRange() throws {
        let image = try #require(Self.checker)
        let odd = [
            Double.nan, .infinity, -.infinity, 1e300, -1e300, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
            .leastNonzeroMagnitude,
        ]
        for edges in ImageEdges.allCases {
            for u in odd {
                for v in odd {
                    let value = image.value(u: u, v: v, edges: edges)
                    #expect((0.0...1.0).contains(value), "u \(u), v \(v), \(edges)")
                    if !u.isFinite || !v.isFinite { #expect(value == 0) }
                }
            }
        }
    }

    @Test func theEdgeModesHaveTheirSegmentedControlOrder() {
        #expect(ImageEdges.options == ["Tile", "Clamp"])
        #expect(ImageEdges(rawValue: 0) == .tile && ImageEdges(rawValue: 1) == .clamp && ImageEdges(rawValue: 2) == nil)
    }
}
