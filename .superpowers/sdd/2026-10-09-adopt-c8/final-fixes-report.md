# Final fixes report (adopt-c8)

Finding (important): 08ef7e1 hidden title bar merged unverified (AS-5 not run); docs written as if merged.

Ruling: default to not merging 4b until AS-5 runs. 08ef7e1 reverted (own commit); 4a (clearance code, zero in a standard window) stays.
Ruling: the plan's "held back" edits applied, except the C8-a row is not marked "confirmed by AS-5" because AS-5 has not run; it says "predicted from reading MetalUI, AS-5 not run".
Docs changed: metalui-gaps.md (M6-c row and entry open, C8-a row, M6-a note, C8-a entry), roadmap row, spec Errata (M6), CLAUDE.md (two sentences), human-checks.md (decision 1, AS-4, AS-5 now say how to apply the line to run AS-5). packaging docs had no title-bar wording.
Verification: swiftlint --strict 0 violations; swift test exit 0, 11 "Test run with" lines, no failures.
