/// An input that varies by instance (patterns spec §5): one value per item of a list, and a shorter list repeats its
/// last item, as broadcasting does everywhere (spec §4.2). A shortcut node takes its sizes as lists so it can make
/// one kernel call for all its instances, and reads them through this.
struct PerInstance<Value> {
    let values: [Value]

    init(_ values: [Value]) {
        self.values = values
    }

    var count: Int { values.count }

    /// The value for instance `index`, repeating the last. Only call it on a list with a value in it.
    subscript(index: Int) -> Value { values[min(index, values.count - 1)] }

    /// The number of instances that inputs of these lengths make together: the longest, or none if any is empty.
    static func instances(_ lengths: [Int]) -> Int {
        lengths.contains(0) ? 0 : lengths.max() ?? 0
    }
}
