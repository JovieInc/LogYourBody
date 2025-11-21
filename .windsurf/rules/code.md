---
trigger: always_on
---

	•	This is a Swift iOS project. All code must compile and respect the repository’s .swiftlint.yml and .swiftformat configs, which are enforced locally (pre-commit hooks) and in CI via swiftformat . and swiftlint (and bundle exec fastlane ios ci where relevant).
	•	When generating or editing Swift code:
	•	Write it so that running swiftformat . and swiftlint will not introduce new violations, as far as can be inferred from context.
	•	Follow standard Swift conventions: PascalCase for types, camelCase for variables/properties/functions, and clear, descriptive names (no random abbreviations unless the file already uses them).
	•	Prefer safe patterns: avoid ! and try! unless absolutely necessary; use guard let / guard for early exits; keep functions reasonably small and focused; avoid deep nesting and dead code; avoid unused variables/arguments.
	•	Use appropriate access control (private / fileprivate) to prevent unused symbol warnings and to match the existing file’s structure.
	•	Match the existing style of the file and the project (spacing, brace style, imports, etc.), assuming it conforms to SwiftLint/SwiftFormat.
	•	Do not reformat entire files or unrelated code; limit changes to what is needed for the current task while keeping the file in a state that passes SwiftLint/SwiftFormat.
	•	Do not leave debug prints, TODOs, commented-out large blocks, or temporary code in the final answer unless explicitly requested.