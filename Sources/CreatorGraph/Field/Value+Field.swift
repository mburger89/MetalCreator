extension Value {
    /// What a tooltip or the inspector says about the field this value holds (fields spec §2.1): the recipe of one field, cut to
    /// `limit` characters when a limit is given, or "3 fields" for several. `nil` when the value holds anything else, or nothing.
    public func fieldSummary(limit: Int? = nil) -> String? {
        let fields = items.compactMap { scalar -> Field? in if case .field(let field) = scalar { field } else { nil } }
        guard !fields.isEmpty, fields.count == items.count else { return nil }
        guard fields.count == 1, let only = fields.first else { return "\(fields.count) fields" }
        return limit.map { only.description(limit: $0) } ?? only.description
    }
}
