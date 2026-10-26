# LYB-189 Apple Health disclosure review

Routing: Tim/legal, through [LYB-189](https://linear.app/jovie/issue/LYB-189).
Status: factual type-list draft; final public prose review remains pending.
The policy edit is limited to that list, read/write directions, source-backed
purpose labels, and its update date. No legal approval is recorded here.
Tim/legal must review the Health Data bullet before publication.

| HealthKit type                            | Current access                                                     | Purpose supported by source |
| ----------------------------------------- | ------------------------------------------------------------------ | --------------------------- |
| Weight (`bodyMass`)                       | Read and write requested                                           | Sync body metrics           |
| Body fat percentage (`bodyFatPercentage`) | Read and write requested                                           | Sync body metrics           |
| Height (`height`)                         | Read requested                                                     | Body-metric context         |
| Step count (`stepCount`)                  | Read requested                                                     | Activity context            |
| Date of birth (`dateOfBirth`)             | Read requested                                                     | Fill in profile birth year  |
| Biological sex (`biologicalSex`)          | Existing-permission read path; absent from the current request set | Fill in profile sex         |

Source: the type properties, `requestAuthorization`, sample queries/saves and
characteristic getters in
[`HealthKitManager+Part01.swift`](../../apps/ios/LogYourBody/Services/HealthKitManager+Part01.swift),
step queries in
[`HealthKitManager+Part03.swift`](../../apps/ios/LogYourBody/Services/HealthKitManager+Part03.swift),
and `applyHealthCharacteristics` in the
[onboarding view model](../../apps/ios/LogYourBody/Features/Onboarding/ViewModels/OnboardingFlowViewModel+Part01.swift).
Biological sex is included because the getter is called during onboarding;
this change adds no authorization request and changes no native behavior.

The draft lives in the canonical
[privacy policy](../../shared/legal/privacy-policy.md), loaded by the web privacy
page and copied into the iOS bundle with `apps/ios/copy-legal-docs.sh`.
The existing required privacy scanner rejects missing types in that bullet;
mentions in Profile Information or other sections do not satisfy it.
`pnpm product:check` verifies legal-copy synchronization. These source checks
do not prove that the live website has deployed or that final prose was reviewed.
