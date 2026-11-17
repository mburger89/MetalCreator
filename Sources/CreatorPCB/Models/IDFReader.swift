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

    public static func read(_ data: Data, isCancelled: () -> Bool) throws(KiCadProblem) -> IDFOutline {
        guard data.count <= maximumBytes else { throw KiCadProblem("This IDF file is larger than 16 MB.") }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        var state = IDFParseState()
        var lineCount = 0
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            lineCount += 1
            if lineCount % cancelEvery == 0, isCancelled() { throw KiCadProblem("Reading the IDF file was cancelled.") }
            let tokens = tokenize(rawLine)
            guard let first = tokens.first else { continue }
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
        guard tokens.count >= 4, let loop = Int(tokens[0]), let x = Double(tokens[1]), let y = Double(tokens[2]),
              let angle = Double(tokens[3]), x.isFinite, y.isFinite, angle.isFinite else {
            throw KiCadProblem("This IDF file has a point line that isn't a loop number, x, y and angle.")
        }
        let point = Vector2(x * scale, y * scale)
        guard let start = firstPoint, let from = previous else {
            (label, firstPoint, previous, segments) = (loop, point, point, [])
            return
        }
        guard loop == label else { throw unclosed }
        if angle == 360 {
            let radius = (point - from).length
            guard radius > 1e-9 else { throw KiCadProblem("This IDF file has a circle with no size.") }
            loops.append((label, [ArcGeometry.circle(center: from, radius: radius)]))
            firstPoint = nil
            previous = nil
            return
        }
        guard abs(angle) < 360 else { throw KiCadProblem("This IDF file has an arc that turns a whole circle or more.") }
        let chord = (point - from).length
        if chord < 1e-9 && abs(angle) > 0 { throw KiCadProblem("This IDF file has an arc with no chord.") }
        if chord > 1e-9 { segments.append(segment(from: from, to: point, degrees: angle)) }
        previous = point
        if (point - start).length < 1e-9 {
            guard segments.count >= 2 else { throw KiCadProblem("This IDF file has an outline of fewer than three sides.") }
            loops.append((label, segments))
            firstPoint = nil
            previous = nil
        }
    }

    var unclosed: KiCadProblem { KiCadProblem("This IDF file has an outline that doesn't close.") }

    func segment(from: Vector2, to: Vector2, degrees: Double) -> Segment2D {
        if degrees == 0 { return .line(from, to) }
        let theta = degrees * .pi / 180
        let chord = to - from
        let length = chord.length
        let normal = Vector2(-chord.y, chord.x) * (1 / length)
        let middle = Vector2((from.x + to.x) / 2, (from.y + to.y) / 2)
        let centre = middle + normal * (length / 2 / tan(theta / 2))
        let start = atan2(from.y - centre.y, from.x - centre.x)
        return .arc(center: centre, radius: (from - centre).length, start: Angle(radians: start),
                    end: Angle(radians: start + theta))
    }

    func finish() throws(KiCadProblem) -> IDFOutline {
        guard phase == .done || phase == .points, height > 0 else {
            throw KiCadProblem("This IDF file has no part outline (.ELECTRICAL or .MECHANICAL section).")
        }
        if firstPoint != nil { throw unclosed }
        guard let outerIndex = loops.firstIndex(where: { $0.label == 0 }) else {
            throw KiCadProblem("This IDF file's part has no outer outline (loop 0).")
        }
        let outer = Self.oriented(loops[outerIndex].segments, counterClockwise: true)
        var holes: [[Segment2D]] = []
        for (index, loop) in loops.enumerated() where index != outerIndex {
            holes.append(Self.oriented(loop.segments, counterClockwise: false))
        }
        return IDFOutline(profile: Profile2D(plane: .xy, outer: outer, holes: holes), height: height)
    }

    static func oriented(_ loop: [Segment2D], counterClockwise: Bool) -> [Segment2D] {
        let area = ArcGeometry.signedArea(loop)
        guard (area > 0) != counterClockwise else { return loop }
        return loop.reversed().map { ArcGeometry.reversed($0) }
    }
}
