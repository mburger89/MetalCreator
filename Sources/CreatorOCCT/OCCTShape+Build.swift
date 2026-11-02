import COCCT
import CreatorGeometry
import CreatorKernel

extension OCCTShape {
    /// Runs a shim builder that returns a shape and fills a history; frees the history.
    static func building(_ body: (UnsafeMutablePointer<occt_history>, UnsafeMutablePointer<occt_status>) -> OpaquePointer?)
        throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        var history = occt_history()
        defer { occt_history_free(&history) }
        let shape = try make { status in body(&history, status) }
        return (shape, OCCTHistoryRecord.read(history))
    }

    static func extrude(_ profile: Profile2D, distance: Double) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        try OCCTProfile.with(profile) { cProfile throws(OCCTError) in
            try building { history, status in occt_extrude(cProfile, distance, history, status) }
        }
    }

    static func revolve(_ profile: Profile2D, axis: Axis, angle: Angle) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        let origin = [axis.origin.x, axis.origin.y, axis.origin.z]
        let direction = [axis.direction.x, axis.direction.y, axis.direction.z]
        return try OCCTProfile.with(profile) { cProfile throws(OCCTError) in
            try building { history, status in occt_revolve(cProfile, origin, direction, angle.radians, history, status) }
        }
    }

    static func loft(_ sections: [Profile2D], ruled: Bool) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        try OCCTProfile.withAll(sections) { profiles, count throws(OCCTError) in
            try building { history, status in occt_loft(profiles, Int32(count), ruled ? 1 : 0, history, status) }
        }
    }

    /// `occt_loft_ends` for the kernel's ends (face indexes are the topology table's, one-based in OCCT's map).
    static func loftEnds(part: OCCTShape?, start: LoftEnd?, end: LoftEnd?, sections: [Profile2D])
        throws(OCCTError) -> (shape: OCCTShape, history: [OCCTHistoryRecord], report: occt_loft_report) {
        func raw(_ loftEnd: LoftEnd?) -> occt_loft_end? {
            loftEnd.map {
                occt_loft_end(face_index: Int32($0.face.rawValue + 1), continuity: Int32($0.continuity.rawValue), weight: $0.weight)
            }
        }
        return try loftEnds(part: part, start: raw(start), end: raw(end), sections: sections)
    }

    /// `occt_loft_ends`, a loft from an optional face of `part`, through `sections`, to an optional face of
    /// `part` (each end's `face_index` 1-based; below 1, or nil, no face).
    static func loftEnds(part: OCCTShape?, start: occt_loft_end?, end: occt_loft_end?, sections: [Profile2D])
        throws(OCCTError) -> (shape: OCCTShape, history: [OCCTHistoryRecord], report: occt_loft_report) {
        var report = occt_loft_report()
        var first = start ?? occt_loft_end(face_index: -1, continuity: 0, weight: 1)
        var last = end ?? occt_loft_end(face_index: -1, continuity: 0, weight: 1)
        let raw = part?.raw
        func call(_ profiles: UnsafePointer<occt_profile>?, _ count: Int) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
            try building { history, status in
                occt_loft_ends(raw, &first, &last, profiles, Int32(count), history, &report, status)
            }
        }
        let (shape, history) = sections.isEmpty
            ? try call(nil, 0)
            : try OCCTProfile.withAll(sections) { profiles, count throws(OCCTError) in try call(profiles, count) }
        return (shape, history, report)
    }
}
