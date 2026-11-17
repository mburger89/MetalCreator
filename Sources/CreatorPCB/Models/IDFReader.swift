import CreatorGeometry
import Foundation

/// A component's outline from an IDF 3.0 library file: the footprint of its body and how tall it stands, in millimetres.
public struct IDFOutline: Sendable, Equatable {
    /// On `Plane.xy`: the outer loop runs counter-clockwise, holes clockwise.
    public var profile: Profile2D
    public var height: Double

    public init(profile: Profile2D, height: Double) {
        self.profile = profile
        self.height = height
    }
}

/// Reads the first `.ELECTRICAL` or `.MECHANICAL` section of an IDF library file. **The file is untrusted input**:
/// 16 MB, cancellation asked every 65,536 lines, and every refusal a full sentence.
public enum IDFReader {
    public static let maximumBytes = 16 * 1024 * 1024
    static let cancelEvery = 65_536

    public static func read(_ data: Data, isCancelled: () -> Bool) throws -> IDFOutline {
        guard data.count <= maximumBytes else { throw KiCadProblem("This IDF file is larger than 16 MB.") }
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var state = IDFParseState()
        var lineCount = 0
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            lineCount += 1
            if lineCount % cancelEvery == 0, isCancelled() { throw CancellationError() }
            let tokens = tokenize(rawLine)
            guard let first = tokens.first, !first.hasPrefix("#") else { continue }
            if try state.accept(first: first, tokens: tokens) { break }
        }
        return try state.finish()
    }

    // MARK: Lines

    /// Splits a line into words, a quoted name being one word (quotes removed).
    static func tokenize(_ line: Substring) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var hasWord = false
        for character in line {
            if character == "\"" {
                inQuotes.toggle()
                hasWord = true
            } else if !inQuotes, character == " " || character == "\t" {
                if hasWord { tokens.append(current) }
                current = ""
                hasWord = false
            } else {
                current.append(character)
                hasWord = true
            }
        }
        if hasWord { tokens.append(current) }
        return tokens
    }
}

private struct IDFParseState {
    enum Phase { case start, header, between, sectionName, points, done }

    static let largestRadius = 1e6
    var phase = Phase.start
    var scale = 1.0
    var height = 0.0
    var loops: [(label: Int, segments: [Segment2D])] = []
    var firstPoint: Vector2?
    var previous: Vector2?
    var segments: [Segment2D] = []
    var label = 0

    /// Takes one line; true once the section has ended.
    mutating func accept(first: String, tokens: [String]) throws(KiCadProblem) -> Bool {
        let keyword = first.uppercased()
        switch phase {
        case .start, .between:
            try acceptOutside(keyword)
        case .header:
            if keyword == "BOARD_FILE" || keyword == "PANEL_FILE" { throw wholeBoard }
            if keyword == ".END_HEADER" { phase = .between }
        case .sectionName:
            try readSectionLine(tokens)
            phase = .points
        case .points:
            if keyword.hasPrefix(".END_") {
                phase = .done
                return true
            }
            try readPoint(tokens)
        case .done:
            return true
        }
        return false
    }

    mutating func acceptOutside(_ keyword: String) throws(KiCadProblem) {
        switch keyword {
        case ".HEADER": phase = .header
        case ".BOARD_OUTLINE", ".PLACEMENT", ".DRILLED_HOLES": throw wholeBoard
        case ".ELECTRICAL", ".MECHANICAL": phase = .sectionName
        default: break
        }
    }

    var wholeBoard: KiCadProblem { KiCadProblem("This IDF file is a whole board, not a part.") }

    mutating func readSectionLine(_ tokens: [String]) throws(KiCadProblem) {
        guard tokens.count >= 3 else { throw KiCadProblem("This IDF file's part has no unit and height.") }
        switch tokens[tokens.count - 2].uppercased() {
        case "MM": scale = 1
        case "THOU": scale = 0.0254
        default: throw KiCadProblem("This IDF file's part names a unit other than MM or THOU.")
        }
        guard let value = Double(tokens[tokens.count - 1]), value.isFinite, value > 0 else {
            throw KiCadProblem("This IDF file's part has no usable height.")
        }
        height = value * scale
    }

    mutating func readPoint(_ tokens: [String]) throws(KiCadProblem) {
        let (loop, point, angle) = try parsePoint(tokens)
        guard let start = firstPoint, let from = previous else {
            (label, firstPoint, previous, segments) = (loop, point, point, [])
            return
        }
        guard loop == label else { throw unclosed }
        if angle == 360 {
            try addCircle(centre: from, through: point)
            return
        }
        guard abs(angle) < 360 else { throw KiCadProblem("This IDF file has an arc that turns a whole circle or more.") }
        let chord = (point - from).length
        if chord < 1e-9 && abs(angle) > 0 { throw KiCadProblem("This IDF file has an arc with no chord.") }
        if chord > 1e-9 { segments.append(try segment(from: from, to: point, degrees: angle)) }
        previous = point
        if (point - start).length < 1e-9 {
            guard segments.count >= 2 else { throw KiCadProblem("This IDF file has an outline of fewer than three sides.") }
            loops.append((label, segments))
            firstPoint = nil
            previous = nil
        }
    }

    func parsePoint(_ tokens: [String]) throws(KiCadProblem) -> (Int, Vector2, Double) {
        guard tokens.count >= 4, let loop = Int(tokens[0]), let x = Double(tokens[1]), let y = Double(tokens[2]),
              let angle = Double(tokens[3]), x.isFinite, y.isFinite, angle.isFinite else {
            throw KiCadProblem("This IDF file has a point line that isn't a loop number, x, y and angle.")
        }
        guard abs(x * scale) <= 1e9, abs(y * scale) <= 1e9 else {
            throw KiCadProblem("This IDF file has a coordinate beyond 1,000 kilometres.")
        }
        return (loop, Vector2(x * scale, y * scale), angle)
    }

    mutating func addCircle(centre: Vector2, through point: Vector2) throws(KiCadProblem) {
        guard segments.isEmpty else {
            throw KiCadProblem("This IDF file has a circle that starts partway through an outline.")
        }
        let radius = (point - centre).length
        guard radius > 1e-9, radius <= Self.largestRadius else {
            throw KiCadProblem("This IDF file has a circle with no usable size.")
        }
        loops.append((label, [ArcGeometry.circle(center: centre, radius: radius)]))
        firstPoint = nil
        previous = nil
    }

    var unclosed: KiCadProblem { KiCadProblem("This IDF file has an outline that doesn't close.") }

    func segment(from: Vector2, to: Vector2, degrees: Double) throws(KiCadProblem) -> Segment2D {
        if abs(degrees) < 1e-6 { return .line(from, to) }
        let theta = degrees * .pi / 180
        let chord = to - from
        let length = chord.length
        let normal = Vector2(-chord.y, chord.x) * (1 / length)
        let middle = Vector2((from.x + to.x) / 2, (from.y + to.y) / 2)
        let centre = middle + normal * (length / 2 / tan(theta / 2))
        let start = atan2(from.y - centre.y, from.x - centre.x)
        let radius = (from - centre).length
        guard radius <= Self.largestRadius else { throw KiCadProblem("This IDF file has an arc with a radius over 1,000 metres.") }
        return .arc(center: centre, radius: radius, start: Angle(radians: start),
                    end: Angle(radians: start + theta))
    }

    func finish() throws(KiCadProblem) -> IDFOutline {
        guard phase == .done || phase == .points, height > 0 else {
            throw KiCadProblem("This IDF file has no part outline (.ELECTRICAL or .MECHANICAL section).")
        }
        if firstPoint != nil { throw unclosed }
        // A loop's label is IDF 3.0's winding flag (0 counter-clockwise, 1 clockwise), not outline against hole: the first
        // closed loop is the outline whatever its label, the others are holes, and the orientation is fixed here.
        guard let first = loops.first else {
            throw KiCadProblem("This IDF file's part has no outer outline.")
        }
        let outer = Self.oriented(first.segments, counterClockwise: true)
        let holes = loops.dropFirst().map { Self.oriented($0.segments, counterClockwise: false) }
        return IDFOutline(profile: Profile2D(plane: .xy, outer: outer, holes: holes), height: height)
    }

    static func oriented(_ loop: [Segment2D], counterClockwise: Bool) -> [Segment2D] {
        let area = ArcGeometry.signedArea(loop)
        guard (area > 0) != counterClockwise else { return loop }
        return loop.reversed().map { ArcGeometry.reversed($0) }
    }
}
