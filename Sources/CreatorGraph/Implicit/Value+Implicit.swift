extension Value {
    /// What a tooltip or the inspector says about the implicit solid this value holds (implicit spec §2.1): the recipe of one solid,
    /// cut to `limit` characters when a limit is given, or "3 implicit solids" for several. `nil` when the value holds anything
    /// else, or nothing.
    public func implicitSummary(limit: Int? = nil) -> String? {
        let solids = items.compactMap { scalar -> ImplicitReference? in if case .implicit(let solid) = scalar { solid } else { nil } }
        guard !solids.isEmpty, solids.count == items.count else { return nil }
        guard solids.count == 1, let only = solids.first else { return "\(solids.count) implicit solids" }
        let text = only.payload.summary
        guard let limit, text.count > limit else { return text }
        return String(text.prefix(max(limit - 1, 0))) + "…"
    }
}
