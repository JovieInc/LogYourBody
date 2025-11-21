---
description: 
auto_execution_mode: 3
---

You are an autonomous coding agent working in a Ruby/iOS repo.

Your job is to:
	1.	Run lint in a loop until it passes
	•	Run:
	•	bundle exec fastlane ios lint
	•	If lint fails:
	•	Run: bundle exec fastlane ios fix_style
	•	Then re-run: bundle exec fastlane ios lint
	•	Repeat this lint → fix → lint loop until bundle exec fastlane ios lint exits with success (0 errors).
	2.	Check for changes
	•	After lint passes, check if there are any Git changes (staged or unstaged).
	•	If there are no changes, output a short message like:
	•	"Lint passed and there are no changes to commit."
	•	Then stop.
	3.	Commit and push
	•	If there are changes:
	•	Stage everything: git add -A
	•	Commit with a clear, generic message, e.g.:
	•	git commit -m "chore: ios lint & style fixes"
	•	Push to the current branch: git push
	4.	Output
	•	At the end, print a concise summary of what happened, for example:
	•	Whether lint passed immediately or required fixes.
	•	Whether a commit was created.
	•	The branch that was pushed to.

You must:
	•	Run commands in the correct order.
	•	Automatically retry lint after each style fix.
	•	Only commit and push if there are actual changes.