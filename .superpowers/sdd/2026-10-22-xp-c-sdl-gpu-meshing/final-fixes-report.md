# xp-c final fixes report

Finding (important): spec xp-c fall-back paragraph said the CPU fall-back shows "Running on the CPU" and the reason.

Ruling: the user ruling and the code (ImplicitEvaluators.Selection) put the reason in Selection.diagnostic and --self-test; the node text is just "Running on the CPU". The spec was wrong, the code right. Fixed the spec wording only (docs/superpowers/specs/2026-10-13-cross-platform-design.md), commit 6db683f.

Verification: full `swift test` on macOS: exit 0, 12 "Test run with" lines, 785 tests in 148 suites passed, no "recorded an issue" or "failed after".
