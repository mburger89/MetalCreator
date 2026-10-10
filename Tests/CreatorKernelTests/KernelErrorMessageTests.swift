import Foundation
import Testing
@testable import CreatorKernel

/// Kernel messages read the same on every machine: numbers use `Locale.messages` (en_US), as node messages do, so a
/// German host doesn't get "Radius 2,5 mm" beside a node's "2.5". The messages take their locale as a parameter, so a
/// German one can be passed in and the test fails on any machine if a number is written in another locale.
struct KernelErrorMessageTests {
    let tooLarge = KernelError.filletFailed(radius: 2.5, maxRadius: 5.9, reason: "")
    let unapplied = KernelError.filletFailed(radius: 2.5, maxRadius: nil, reason: "it can't.")
    let german = Locale(identifier: "de_DE")

    @Test func aFilletFailureWritesEachNumberInTheLocaleItIsGiven() {
        #expect(tooLarge.message(locale: german) == "Radius 2,5 mm is too large for the selected edges (max ≈ 5,9 mm).")
        #expect(unapplied.message(locale: german) == "Radius 2,5 mm could not be applied: it can't.")
    }

    @Test func userMessageWritesItsNumbersInLocaleMessages() {
        #expect(tooLarge.userMessage == tooLarge.message(locale: .messages))
        #expect(tooLarge.userMessage == "Radius 2.5 mm is too large for the selected edges (max ≈ 5.9 mm).")
        #expect(unapplied.userMessage == "Radius 2.5 mm could not be applied: it can't.")
    }

    @Test func aSizeIsWrittenInTheLocaleItIsGiven() {
        #expect(1234.5.millimetreText(locale: german) == "1.234,5")
        #expect(2.5.millimetreText() == "2.5", "Locale.messages unless told otherwise")
        #expect(2.456.millimetreText(locale: .messages) == "2.46")
    }
}
