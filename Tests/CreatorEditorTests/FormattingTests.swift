import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

struct FormattingTests {
    @Test func numbersShowUpToThreeDecimalsWithTheirUnit() {
        #expect(ValueText.format(60, unit: .millimetres) == "60 mm")
        #expect(ValueText.format(0.25, unit: .none) == "0.25")
        #expect(ValueText.format(1.23456, unit: .degrees) == "1.235°")
        #expect(ValueText.format(12000, unit: .count) == "12000")
        #expect(ValueText.format(.bool(true), unit: .none) == "On")
        #expect(ValueText.format(.plane(.yz), unit: .none) == "YZ")
        #expect(ValueText.format(nil, unit: .millimetres) == "—")
        #expect(ValueText.format(.edgePicks([]), unit: .none) == "0 picks")
    }

    @Test func typedNumbersMayCarryTheirUnit() {
        #expect(ValueText.parse("12.5") == 12.5)
        #expect(ValueText.parse(" 12.5 mm ") == 12.5)
        #expect(ValueText.parse("45°") == 45)
        #expect(ValueText.parse("-3") == -3)
        #expect(ValueText.parse("abc") == nil)
        #expect(ValueText.parse("12 apples") == nil)
        #expect(ValueText.parse("") == nil)
        #expect(ValueText.parse("1e999") == nil)
    }

    @Test func formattingIgnoresTheCurrentLocale() {
        #expect(ValueText.locale.identifier == "en_US_POSIX")
        #expect(ValueText.format(1234.5, unit: .none) == "1234.5")
        // What the inspector shows, it can read back.
        #expect(ValueText.parse(ValueText.format(0.25, unit: .millimetres)) == 0.25)
        #expect(StatusBadge.text(for: .ok(duration: .milliseconds(1500))) == "1500 ms")
    }

    @Test func wholeNumbersRoundAndRefuseWhatNoIntHolds() {
        #expect(ValueText.wholeNumber(4.4) == 4)
        #expect(ValueText.wholeNumber(-2.5) == -3)
        #expect(ValueText.wholeNumber(1e300) == nil)
        #expect(ValueText.wholeNumber(-1e300) == nil)
        #expect(ValueText.wholeNumber(.nan) == nil)
    }

    @Test func statusBadges() {
        #expect(StatusBadge.text(for: .ok(duration: .milliseconds(12))) == "12 ms")
        #expect(StatusBadge.text(for: .ok(duration: .microseconds(300))) == "<1 ms")
        #expect(StatusBadge.text(for: .evaluating) == "")
        #expect(StatusBadge.isBusy(.evaluating))
        let quiet: [NodeState?] = [.idle(nil), .ok(duration: .zero), .warning("w"), .error("e"), nil]
        #expect(!quiet.contains(where: StatusBadge.isBusy))
        #expect(StatusBadge.text(for: .warning("matched 6 edges, expected 4")) == "⚠")
        #expect(StatusBadge.text(for: .error("Boom")) == "✕")
        #expect(StatusBadge.text(for: .idle(nil)) == "")
        #expect(StatusBadge.text(for: nil) == "")
        #expect(StatusBadge.message(for: .warning("matched 6 edges, expected 4")) == "matched 6 edges, expected 4")
        #expect(StatusBadge.message(for: .idle("Connect or set “profile”.")) == "Connect or set “profile”.")
        #expect(StatusBadge.message(for: .ok(duration: .zero)) == nil)
    }

    @Test func labelsComeFromSocketNames() {
        #expect(InspectorLabel.text(for: "cornerRadius") == "Corner radius")
        #expect(InspectorLabel.text(for: "width") == "Width")
        #expect(InspectorLabel.text(for: "holeCountX") == "Hole count x")
    }

    @Test func planeChoicesMatchOrientationNotOrigin() {
        #expect(PlaneChoice(Plane.xz.offset(by: 5)) == .xz)
        #expect(PlaneChoice(Plane(origin: .zero, normal: .unitZ, xAxis: .unitY)) == nil)
    }
}
