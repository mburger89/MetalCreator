import Testing

/// Records an issue unless `variants` holds exactly one value for each stored property of `base`, each unequal to `base`
/// (so `==` reads that property), and `base` equals `twin`, a second value built separately from the same inputs. An `.equatable()` component skips its content
/// while `==` holds, so a stored property missing from `==` would leave the screen stale; this makes adding a property to
/// a view fail here until the property has a variant.
@MainActor
func expectEqualityCovers<Value: Equatable>(_ base: Value, equalTo twin: Value, _ variants: [String: Value],
                                            sourceLocation: SourceLocation = #_sourceLocation) {
    let stored = Set(Mirror(reflecting: base).children.compactMap(\.label))
    #expect(Set(variants.keys) == stored, "one variant per stored property", sourceLocation: sourceLocation)
    #expect(base == twin, "equal inputs are equal", sourceLocation: sourceLocation)
    for (name, other) in variants {
        #expect(other != base, "\(name) is part of ==", sourceLocation: sourceLocation)
    }
}
