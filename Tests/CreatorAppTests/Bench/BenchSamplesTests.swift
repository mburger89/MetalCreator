import Testing

/// The statistics the §7.3 benchmarks print. These run in the default test run: they time nothing.
struct BenchSamplesTests {
    func samples(_ values: [Double]) -> BenchSamples {
        var samples = BenchSamples("test")
        for value in values { samples.append(value) }
        return samples
    }

    @Test func theMedianOfAnOddCountIsTheMiddleValue() {
        #expect(samples([5, 1, 3]).median == 3)
    }

    @Test func theMedianOfAnEvenCountIsTheMeanOfTheMiddleTwo() {
        #expect(samples([4, 1, 3, 2]).median == 2.5)
    }

    @Test func thePercentileIsTheNearestRank() {
        let hundred = samples((1...100).map(Double.init))
        #expect(hundred.percentile95 == 95)
        #expect(samples((1...20).map(Double.init)).percentile95 == 19)
        #expect(samples([7]).percentile95 == 7)
    }

    @Test func emptySamplesSummariseToZero() {
        let empty = samples([])
        #expect(empty.median == 0 && empty.percentile95 == 0 && empty.maximum == 0)
    }

    @Test func theLineJudgesTheMedianAgainstTheBudget() {
        let fast = samples([10, 12, 30])
        #expect(fast.line(budget: 16.67) == "BENCH test: median 12.00 ms, p95 30.00 ms, max 30.00 ms (n 3); budget 16.67 ms: met")
        #expect(fast.line(budget: 11).hasSuffix("budget 11.00 ms: missed"))
        #expect(fast.line() == "BENCH test: median 12.00 ms, p95 30.00 ms, max 30.00 ms (n 3)")
    }

    @Test func aTimeSpanIsRecordedInMilliseconds() {
        var timed = BenchSamples("span")
        let start = ContinuousClock.now
        timed.append(from: start, to: start + .microseconds(2_500))
        #expect(timed.values == [2.5])
    }
}
