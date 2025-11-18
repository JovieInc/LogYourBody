# CRITICAL: DO NOT REVERT CODE WITHOUT EXPLICIT USER PERMISSION

## NEVER DO THIS:
- **NEVER** use `git checkout` to revert files without explicit user request
- **NEVER** replace new/modern implementations with old/legacy code
- **NEVER** assume that reverting to an older version is the solution
- **NEVER** undo work that was clearly intentional (like the BodyScore onboarding flow)

## EXAMPLES OF WHAT NOT TO DO:
1. ❌ Reverting `OnboardingContainerView.swift` to use old `OnboardingViewModel` instead of fixing the build to include new `OnboardingFlowViewModel`
2. ❌ Using `git checkout` to undo changes when the solution is to properly configure the build
3. ❌ Replacing modern implementations with legacy code because the modern code has missing dependencies

## CORRECT APPROACH:
1. ✅ Fix the underlying issue (add missing files to build, fix imports, update paths)
2. ✅ Ask the user if they want to revert if truly necessary
3. ✅ Preserve newer implementations and fix the dependencies
4. ✅ Add missing files to the build system rather than removing references to them

## WHY THIS MATTERS:
- Users spend time building new features/implementations
- Reverting destroys their work and wastes their time
- The correct solution is almost always to **add** or **fix** rather than **remove** or **revert**
- If newer code exists alongside old code, the newer code is usually intentional

## WHEN REVERTING IS OK:
- User explicitly requests: "revert this file" or "undo my changes"
- User says: "go back to the previous version"
- User indicates the new code was a mistake

## DEFAULT ASSUMPTION:
If modern code exists alongside legacy code, assume:
1. The modern code is intentional
2. The legacy code is deprecated but not yet removed
3. The solution is to complete the migration, not revert it
