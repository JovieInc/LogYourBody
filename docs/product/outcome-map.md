# LogYourBody product outcome map and IA proposal

**Status:** source-level audit and proposal for Tim, 2026-09-27. This is not an approved product decision. It describes the code at branch head 2f2f3b2 and maps it to current product docs; W2 owns the visual/device walk. No build, tests, or simulator were run for this document.

## Sources and authority

Product intent was reconciled from:

- [The Golden Path](../GOLDEN_PATH.md): sign in → subscribe → record a weight → see it on the timeline → trust it survives.
- [User Journeys](../USER_JOURNEYS.md): the broader iOS journey and current test map.
- [Product roadmap](../product-development-roadmap.md): activation, photo activation, D7/D30 retention, paid signal, reliability, and user-pull KPIs.
- [Brand ethos](brand-ethos.md) and [Evidence and Recommendation Standard](evidence-and-recommendation-standard.md): user-selected goals, honest labels for measured/estimated/interpolated values, and body-image safety.
- GBrain direct page reads on 2026-09-27: LYB’s aesthetics-focused product vision, “powered by Jovie” coach language, and the September 3 coach audit with later scope receipts. Keyword search was a clean miss and the one expanded-off query was not a useful discovery result; the known pages were retrieved directly by slug. The September 3 ideas are treated as vision/context, not as approved implementation decisions where later roadmap or code disagrees.
- Current code: WorldClassScreen in apps/ios/LogYourBody/DesignSystem/Theme.swift; onboarding flow in apps/ios/LogYourBody/Features/Onboarding; price/product contract in packages/product-registry/src/products/logyourbody.mjs; RevenueCat verification script and local StoreKit configuration.

Naming rule: no reference product or person names are used in this document.

## 1. Product goals and expected outcomes

### Primary user outcome

Help an adult answer “How am I doing?” from their own weight, body-composition measurements, HealthKit data, and progress photos, with minimal repeated effort. The output is one private chronological view that makes change legible, preserves the date and provenance of entries, and makes it easy to log the next datapoint.

### Primary product loop

A user can:

1. Continue securely with Apple and complete only the profile inputs needed for accurate calculations.
2. See clear trial and subscription terms, choose a plan, or restore an existing purchase.
3. Record or import a weight without friction.
4. See that entry immediately in its dated context on the body timeline, marked as measured.
5. Trust that it remains available after offline use, relaunch, migration, and sync.

A break anywhere in that chain is revenue-critical. A working sign-in or paywall alone is not product value.

### Expansion outcomes

- **Photo-first timeline:** connect a progress photo to its date and measurements; scrub photos and body-composition trends together. This is the clearest expansion of the Golden Path and the roadmap’s photo-activation KPI.
- **Useful analysis:** let a user inspect trends and compare them with their own selected targets. Do not turn population references, estimates, or interpolations into personal targets.
- **Engine-led coach:** the in-app coach is Jovie. It can explain a deterministic training plan and cite only the evidence IDs returned with it. The model must not invent or alter training quantities. The body-composition timeline remains the main product; training is a bounded second pillar.
- **User control and trust:** privacy, data export/deletion, accessible subscription restore/manage, accurate sync state, and opt-in reminders support reliability and continued use.
- **Safety guardrails:** no shame, coercive streaks, unsafe targets, medical claims, or prescriptive aesthetic coaching for users who fall inside the brand-ethos exclusions.

### Canonical KPI ladder

Use the roadmap definitions unless product analytics work formally supersedes them:

| KPI | Outcome definition | Current use in this map |
| --- | --- | --- |
| Activation | Sign in, complete a paywall/free-trial decision, and log or import a weight within 24 hours. | First successful value loop; reduce steps before the first entry. |
| Photo activation | Add or import at least one progress photo. | Keep photo entry easy and optional; distinguish photo activation from core activation. |
| Core retention | Open and view or log data on day 7 and day 30. | Prioritize clear timeline, low-effort repeat logging, and useful progress review. |
| Paid signal | Trial starts, paid conversion, refund/cancel reasons. | Price/offer comprehension, purchase, restore, and renewal health. |
| Reliability | Crash-free sessions >99.5% and no auth/paywall dead ends. | Treat sign-in, profile, purchase, restore, offline, and sync failures as core defects. |
| Pull signals | Support requests, bug reports, App Store reviews, repeated asks. | Evidence to promote secondary surfaces such as voice, bulk import, and deeper analytics. |

## 2. ICP proposal for Tim

**Proposal, not a settled ICP:** the likely first payer is an adult who is intentionally changing or maintaining physique, already weighs in or checks body composition, and wants a private, coherent account of whether that effort is working.

- **Who pays:** a weight/physique tracker who wants to understand change over weeks or months, rather than only record a number. They may be cutting, maintaining, or gaining, but the goal and acceptable range are the user’s.
- **Why they pay:** Pro combines weight, body-fat/lean-mass/FFMI trends, progress photos, HealthKit import, and a private timeline. The paid benefit is continuity and interpretation in one place, not a generic activity log.
- **What they likely use already — hypothesis to validate:** a bathroom scale and its app or Apple Health; the iPhone Photos library for progress pictures; occasional DEXA/body-composition reports; perhaps a notes or spreadsheet habit when the current tools do not connect those data. The repository documents HealthKit, manual entry, photo import, and body-composition PDF import, but it contains no validated customer research proving which alternatives a payer actually uses.
- **Who the product must protect:** adults who may use neutral tracking but should not receive prescriptive aesthetic coaching when the safety exclusions in the Brand Ethos apply. Minors are outside the proposed paid ICP for coaching.
- **Validation before treating this as fact:** interview recent activated and churned users; ask what they currently log, where photos/reports live, what decision they make with the data, and what made them pay or cancel. Segment results by manual versus HealthKit entry and photo activation.

The strongest documented fit is an adult with a user-selected appearance/body-composition goal. “Physique enthusiast,” “scale app user,” and “spreadsheet user” are hypotheses, not observed segments.

## 3. Revenue path to the $5k MRR company target

The $5,000 MRR target is from the LYB app-walk brief, not from the roadmap. This model assumes LYB contributes the full target; if other company products contribute, replace $5,000 with the remaining allocated LYB target.

### Product and offer contract found in the worktree

| Plan | Product ID | RevenueCat package | Intro offer | Reference price | MRR equivalent |
| --- | --- | --- | --- | ---: | ---: |
| Monthly Pro | com.logyourbody.app.pro1.monthly.3daytrial | $rc_monthly | 3 days free, then monthly renewal | $9.99/month | $9.99 |
| Annual Pro | com.logyourbody.app.pro1.annual.3daytrial | $rc_annual | 3 days free, then annual renewal | $69.99/year | $5.8325/month |

Source: packages/product-registry/src/products/logyourbody.mjs:335-363 and the generated iOS registry; apps/ios/LogYourBody.storekit has the same US test products/prices and three-day free introductory periods. Registry prices are USD reference prices; App Store Connect storefront prices and taxes can vary by region.

The plan entitlement is Premium and the current offering should contain both package/product pairs. The release runbook says the RevenueCat main offering must resolve. apps/ios/Scripts/verify_revenuecat_offerings.sh checks the live current offering against those pairs when given a public SDK key; I did not run it because REVENUE_CAT_PUBLIC_KEY is absent in this environment. apps/web/revenuecat-config.json is empty (0 bytes), so the current remote RevenueCat offering and localized prices are not proven by a checked-in config. Treat plan IDs and reference prices as the repository contract, not a fresh dashboard receipt.

### Explicit planning assumptions

| Assumption | Value used | Why it is an assumption |
| --- | ---: | --- |
| Annual / monthly mix among active payers | 70% / 30% | No current plan-mix report was found. |
| Activated users who start a trial | 30% | Planning input only; no observed funnel rate was found. |
| Trial starts that convert to paid | 45% | Planning input only; no observed cohort conversion was found. |
| Apple commission | 15% case | Assumes approved Small Business Program eligibility; eligibility is not verified here. |
| Taxes, refunds, billing failures, RevenueCat fees, and churn | Excluded | Storefront, plan tenure, taxes, cancellations, and refund data are absent from this code-only pass. |
| Activation count | Qualified activation events, not installs | Uses the roadmap’s sign-in + paywall decision + first weight within 24h definition; the activation-to-trial share below is cohort math, not proof that the events occur in that order. |

Apple’s current developer terms describe a 15% commission for approved Small Business Program participants, 30% as the standard rate, and 15% for auto-renewing subscription renewals after one year of paid service. See [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/). The calculations below use 15% as a planning scenario, not as a statement that LYB currently qualifies. Prices exclude any applicable tax effects.

### Contribution math

At a 70% annual / 30% monthly mix:

- Blended gross MRR per active payer = (0.70 × $69.99 ÷ 12) + (0.30 × $9.99) = **$7.07975**.
- At the assumed 15% Apple commission, blended proceeds before tax/refunds/other fees = **$6.01779 per active payer per month**.
- $5,000 ÷ $6.01779 = **831 active paid subscribers** (rounded up) to contribute $5,000 monthly proceeds under this simplified scenario.
- At 45% trial-to-paid, that requires **1,847 trial starts**. At a 30% activated-to-trial rate, it requires **6,157 qualified activations** across retained cohorts.
- Combined activation-to-paid conversion assumption = 30% × 45% = **13.5%**.

| Plan-mix scenario | Gross MRR per active payer | Active paid subscribers for $5k gross MRR | Subscribers for $5k after assumed Apple commission |
| --- | ---: | ---: | ---: |
| Monthly only | $9.99 | 501 | 589 at 15% |
| 70% annual / 30% monthly | $7.07975 | 707 | 831 at 15% |
| Annual only | $5.8325 | 858 | 1,009 at 15% |
| 70% annual / 30% monthly, standard 30% commission sensitivity | $7.07975 | 707 | 1,009 at 30% |

This is an active-subscriber base target, not a monthly acquisition forecast. Annual subscriptions contribute their contract value to normalized MRR over 12 months, even though the customer pays annually. Churn/refunds must be added to acquisition needs once real retention and billing-failure rates are measured. The company target should be reported both as customer-price gross MRR and as actual proceeds; the latter requires App Store Connect/RevenueCat receipts.

### Funnel instrumentation needed

The code records onboarding start/step progression and RevenueCat subscription-phase transitions, but the repo alone supplies no current event rates. Add or verify one shared cohort report for:

- installs/downloads → sign-in → paywall decision → first weight/import within 24h;
- qualified activation → trial start;
- trial start → paid at trial end;
- monthly/annual choice, cancellation/refund reason, and active paid retention;
- photo activation and D7/D30 view-or-log retention.

Resolve whether an explicit “activation completed” event exists and ensure its timestamp agrees with the roadmap’s combined definition. Do not compare a pre-paywall event with a post-paywall activation denominator.

## 4. Complete source-level screen and journey map

Verdicts describe product-scope alignment based on docs and code, not visual quality or device behavior:

- **delivers:** directly advances a current KPI or a Golden Path contract.
- **partially:** useful, but incomplete, secondary, gated, duplicated, or friction-heavy relative to its intended outcome.
- **off-outcome:** has no current roadmap/KPI fit or conflicts with the current core.
- **dead surface:** the named surface/registry ID has no active presentation binding. This can be an ID gap while a similar underlying capability exists elsewhere.

Every ID below is declared by WorldClassScreen in apps/ios/LogYourBody/DesignSystem/Theme.swift:87-134. The render/source column shows code evidence.

| WorldClassScreen | Journey → expected outcome | KPI | Verdict | Renderer/source evidence |
| --- | --- | --- | --- | --- |
| launch | Cold launch → reach the correct signed-out, onboarding, paywall, or paid state without a dead end. | Reliability; activation | delivers | DesignSystem/Organisms/LoadingScreen.swift |
| signIn | Authentication → establish a persistent Apple-backed session. | Activation; reliability | delivers | Views/LoginView.swift |
| legalConsent | Entry/privacy → user can review and accept required terms and privacy. | Reliability; activation | delivers | Views/LegalConsentView.swift |
| biometricLock | Return to app → protect private health/body data when the user enabled a lock. | Reliability; trust guardrail | partially | Views/BiometricLockView.swift |
| whatsNew | Return after a release → understand a material change and continue. | D7/D30 retention; no direct KPI | partially | ContentView.swift |
| bodyScoreIntro | New-user setup → understand why the app asks for initial measurements. | Activation | partially | Features/Onboarding/Views/BodyScoreHookView.swift |
| sexAtBirth | Setup/calculation → use the correct physiological comparison only where validated. | Activation; accuracy/safety guardrail | partially | Features/Onboarding/Views/BodyScoreBasicsView.swift |
| height | Setup/calculation → provide a required profile/body-composition input. | Activation; accuracy | delivers | Features/Onboarding/Views/BodyScoreHeightView.swift |
| appleHealth | Import → use existing HealthKit weight to avoid re-entry, with clear consent. | Activation; reliability | delivers | Features/Onboarding/Views/BodyScoreHealthConnectView.swift; Views/IntegrationsView.swift |
| confirmImportedData | Import → review the candidate datapoint before using it. | Activation; accuracy | partially | Features/Onboarding/Views/BodyScoreHealthConfirmationView.swift |
| weight | Setup → provide a body-score input; a durable timeline entry is created only on a photo-baseline path or later import/log. | Activation; reliability | partially | Features/Onboarding/Views/BodyScoreManualWeightView.swift; Features/Onboarding/ViewModels/OnboardingFlowViewModel+Part02.swift |
| bodyFatMethod | Setup → choose a source for an optional body-fat value. | Activation; accuracy/safety | partially | Features/Onboarding/Views/BodyScoreBodyFatChoiceView.swift |
| bodyFatValue | Setup → add a measured body-fat value with clear units/source. | Activation; accuracy | partially | Features/Onboarding/Views/BodyScoreBodyFatNumericView.swift |
| visualEstimate | Setup → optionally estimate body fat without implying measurement precision. | Activation; accuracy/safety | partially | Features/Onboarding/Views/BodyScoreBodyFatVisualView.swift |
| calculation | Setup → compute the initial result from supplied inputs. | Activation; reliability | partially | Features/Onboarding/Views/BodyScoreLoadingView.swift |
| bodyScoreReveal | First value → see an honest, source-labeled snapshot of the inputs/result. | Activation; accuracy/safety | partially | Features/Onboarding/Views/BodyScoreRevealView.swift |
| chooseHomeView | Setup → choose which home experience opens first. | No direct KPI; conflicts with pinned Home contract | off-outcome | Features/Onboarding/Views/BodyScoreOnboardingFlowView.swift |
| email | Account recovery → provide an optional recovery address. | Reliability; activation | partially | Features/Onboarding/Views/BodyScoreEmailCaptureView.swift |
| verifyAccount | Account creation → complete Apple authentication and preserve the session. | Activation; reliability | partially | Features/Onboarding/Views/BodyScoreAccountCreationView.swift |
| completeProfile | Profile completion → save name, DOB, height, and any required calculation field. | Activation; accuracy | partially | Features/Onboarding/Views/BodyScoreProfileDetailsView.swift; Features/Onboarding/Views/ProfileCompletionGateView.swift |
| firstProgressPhoto | Photo setup → attach an initial photo and start photo activation. | Photo activation | partially | Features/Onboarding/Views/BodyScoreFirstProgressPhotoView.swift |
| paywall | Monetization → understand both plans/trial terms, purchase or continue under policy, and reach the entitled app. | Paid signal; reliability | delivers | Views/PaywallView.swift; GeneratedProductRegistry.swift |
| home | Core loop → see current photo/metrics and open the weight logger quickly. | Activation; D7/D30; reliability | delivers | Views/DashboardViewLiquid+PhotoTimelineHUD.swift |
| photoTimeline | Core loop → review dated photos and scrub body-composition history. | Photo activation; D7/D30 | dead surface | ID has no direct attachment; live timeline is rendered under .home in DashboardViewLiquid+PhotoTimelineHUD.swift |
| stats | Progress review → inspect body-composition metric trends in context. | D7/D30 retention | partially | Views/DashboardViewLiquid+PhotoTimelineAnalytics.swift |
| chat | Ask/coach → get a concise answer and, when enabled, view engine-returned training output. | D7/D30; pull signals; no coach KPI yet | partially | Views/MainTabView.swift; Services/TrainingService.swift; Views/TrainingViews.swift |
| metricDetail | Progress drill-down → understand one metric’s trend and provenance. | D7/D30 retention | partially | Components/FullMetricChartView+Part01.swift |
| logWeight | Capture → save a valid weight and immediately show it on the timeline. | Activation; D7/D30; reliability | delivers | Views/AddEntrySheet+Part01.swift maps selected tab to the ID; Views/DashboardViewLiquid+HomeV2.swift |
| logBodyFat | Capture → save an optional composition datapoint with correct date/source. | D7/D30; accuracy | partially | Views/AddEntrySheet+Part01.swift maps selected tab to the ID |
| addProgressPhoto | Capture → attach a private photo to the selected date. | Photo activation; D7/D30 | delivers | Views/ProgressPhotoAttachSheet.swift |
| glp1CheckIn | Capture → privately record a medication/dose event, if supported. | No direct roadmap KPI; safety/reliability guardrail | off-outcome | Views/AddEntrySheet+Part01.swift maps the optional GLP-1 tab; Views/DashboardViewLiquid+PhotoTimelineAnalytics.swift |
| shareBodyScore | Sharing → share a score or summary externally. | No direct KPI; privacy/body-image guardrail | off-outcome | Components/BodyScoreShareCard.swift |
| syncDetails | Sync → know whether an entry is local, offline, or synced, and recover from failure. | Reliability; retention | delivers | Components/DashboardSyncComponents.swift |
| dailyReminder | Repeat use → opt into one quiet weigh-in reminder. | D7/D30 retention; reliability | partially | Views/DailyWeighInReminderPromptView.swift; Views/HomeV2/HomeV2SettingsDetailViews.swift |
| planUnavailable | Paywall failure → see a clear retry/restore route when offerings cannot load. | Paid signal; reliability | delivers | Views/PaywallView.swift |
| restorePurchases | Purchase recovery → restore the Premium entitlement after reinstall or account change. | Paid signal; reliability | delivers | Views/PaywallView.swift; Views/HomeV2/HomeV2SettingsDetailViews.swift |
| settings | Account/preferences → reach profile, subscription, data, reminders, and privacy controls. | Reliability; trust guardrail | partially | Views/PreferencesView.swift; Views/HomeV2/HomeV2SettingsView.swift |
| editProfile | Profile maintenance → update fields used by account and metric calculations. | Accuracy; reliability | partially | Views/PreferencesView+AccountSection.swift; Views/ProfileSettingsEditorSheets.swift |
| trackingAndGoals | Tracking setup → set units and goals the user explicitly chose. | D7/D30; accuracy/safety | partially | Views/PreferencesView+TrackingGoalsSection.swift; Views/HomeV2/HomeV2SettingsDetailViews.swift |
| integrations | Data import → connect Apple Health and use supported import sources. | Activation; reliability | delivers | Views/IntegrationsView.swift |
| importPhotos | Photo import → select and date-match existing progress photos. | Photo activation; reliability | delivers | Views/BulkPhotoImportView.swift |
| exportData | Data portability → produce a usable copy of the user’s records. | Trust/reliability guardrail | delivers | Views/ExportDataView.swift |
| activeSessions | Security → inspect devices with access to the account. | Reliability; trust guardrail | partially | Views/SecuritySessionsView.swift |
| privacyAndData | Privacy → control photo handling and reach deletion/data actions. | Trust/reliability guardrail | partially | Views/PreferencesView+Header.swift; Views/PreferencesView+PhotosAdvancedSection.swift |
| deleteAccount | Account control → confirm deletion and remove account data. | Reliability; user-agency guardrail | delivers | Views/DeleteAccountView.swift |
| bugReport | Support → submit a reproducible problem and surface product friction. | Pull signals; reliability | delivers | Views/BugReportViews.swift |

### Onboarding flow: every persisted Step case

The current enum is 17 cases, not 12. Branch-specific input screens are included separately below because they are separately persisted states. The stable progress sequence has 15 entries and omits loading/paywall; it includes mutually exclusive body-fat options as separate entries. The main branch path changes at HealthKit, body-fat method, authentication context, and whether the first-photo step is enabled.

| Step | Journey → expected outcome | KPI | Verdict | View evidence |
| --- | --- | --- | --- | --- |
| hook | Explain the first result and begin setup. | Activation | partially | BodyScoreHookView.swift |
| basics | Collect only the calculation reference the user consents to provide. | Activation; safety | partially | BodyScoreBasicsView.swift |
| height | Collect height for calculation/profile completeness, once. | Activation; accuracy | delivers | BodyScoreHeightView.swift |
| healthConnect | Offer HealthKit weight import with a manual alternative. | Activation | delivers | BodyScoreHealthConnectView.swift |
| healthConfirmation | Confirm an imported weight before using it. | Activation; accuracy | partially | BodyScoreHealthConfirmationView.swift |
| manualWeight | Capture a weight for the initial body-score calculation; this does not by itself guarantee a durable dated timeline entry. | Activation; reliability | partially | BodyScoreManualWeightView.swift; OnboardingFlowViewModel+Part01.swift; OnboardingFlowViewModel+Part02.swift |
| bodyFatChoice | Offer measured, numeric, or skip paths with source clarity. | Activation; accuracy | partially | BodyScoreBodyFatChoiceView.swift |
| bodyFatNumeric | Capture the numeric value only when the user knows it. | Activation; accuracy | partially | BodyScoreBodyFatNumericView.swift |
| bodyFatVisual | Optional estimate with prominent estimate labeling and no implied precision. | Activation; safety | partially | BodyScoreBodyFatVisualView.swift |
| loading | Compute the body-score result and persist progress. | Reliability; activation | partially | BodyScoreLoadingView.swift |
| bodyScore | Reveal a first result that clearly distinguishes observations and estimates. | Activation; accuracy | partially | BodyScoreRevealView.swift |
| defaultHomeMode | Choose the initial home mode. | No direct KPI | off-outcome | BodyScoreOnboardingFlowView.swift |
| emailCapture | Save a recovery email before account creation where required. | Activation; reliability | partially | BodyScoreEmailCaptureView.swift |
| account | Continue with Apple and create/restore the account. | Activation; reliability | partially | BodyScoreAccountCreationView.swift |
| profileDetails | Complete name, date of birth, sex if needed, and height. | Activation; accuracy | partially | BodyScoreProfileDetailsView.swift |
| firstPhoto | Attach a first progress photo when this branch is enabled. | Photo activation | partially | BodyScoreFirstProgressPhotoView.swift |
| paywall | Choose the 3-day-trial monthly or annual plan and purchase/restore. | Paid signal; reliability | delivers | PaywallView.swift |

Code evidence: OnboardingFlowViewModel.swift declares Step and progressSequence; BodyScoreOnboardingFlowView.swift renders each case; OnboardingFlowViewModel+Part01.swift routes forward/back and records step progression; Part02.swift restores progress and conditionally omits the photo step.

### Settings surface inventory

The current code has two settings systems connected to one another:

1. The photo-timeline menu opens HomeV2SettingsView: Profile, Subscription, Apple Health, Units, Target, Reminders, Face ID lock, Export data, Delete account. This is a custom grouped SwiftUI table.
2. HomeV2’s Profile route opens PreferencesView, which is a classic inset-grouped List with another settings launcher: Profile, Tracking, Integrations, Account & subscription, Privacy & data. Its child views cover:
   - Profile: email, avatar, logout, name, date of birth, height; name/DOB/height use editor sheets.
   - Tracking: units, step goal, weight/body-fat/FFMI targets, daily weigh-in reminder/time.
   - Integrations: Apple Health, body-composition import, and related data flows.
   - Account & subscription: entitlement/renewal, manage in App Store, restore purchases, active sessions.
   - Privacy & data: photo handling and delete account.
3. Shared/overlapping surfaces are subscription, HealthKit, units, targets, reminders, restore, export, delete, and profile. Settings IDs do not fully match the visible HomeV2 routes: WorldClassScreen.settings is attached to PreferencesView, not the HomeV2SettingsView root.

Evidence: Views/DashboardViewLiquid+HomeV2Settings.swift:104-179, Views/HomeV2/HomeV2SettingsView.swift:194-266, Views/PreferencesView.swift:50-130, Views/PreferencesView+Header.swift:9-70, PreferencesView+AccountSection.swift, PreferencesView+TrackingGoalsSection.swift, PreferencesView+SecuritySubscriptionSection.swift, PreferencesView+PhotosAdvancedSection.swift, and Views/HomeV2/HomeV2SettingsDetailViews.swift.

| Settings surface | Journey → expected outcome | KPI / guardrail | Verdict | IA direction |
| --- | --- | --- | --- | --- |
| HomeV2 Settings root | Reach daily preferences and account controls from the timeline menu. | Reliability; trust | partially | Refactor into one native iOS grouped-list root; de-duplicate links into PreferencesView. |
| Profile | Correct user identity and calculation fields. | Activation; accuracy | partially | Keep name, DOB, height and photo together; make email a recovery field, not a separate auth screen. |
| Subscription | See current plan, renewal, change plan, restore, and manage in App Store. | Paid signal; reliability | delivers | Keep one subscription destination and one paywall/restore implementation. |
| Apple Health / Integrations | Connect or inspect import source and permissions. | Activation; reliability | delivers | Merge duplicated HealthKit entry points under Data Sources; explain permission before request. |
| Units | See consistent weight/height/circumference units. | Accuracy; retention | delivers | Keep one unit preference; remove duplicate control. |
| Target / Tracking & Goals | Set a user-owned weight/body-fat/FFMI target. | Retention; safety | partially | Merge two goal surfaces; keep targets separate from population references. Move step goal out of physique core. |
| Reminders | Choose one opt-in reminder and its time. | D7/D30; safety | partially | Keep quiet and optional; use one preference and one reminder prompt. |
| Face ID lock | Protect sensitive app access. | Reliability; privacy | partially | Keep as one privacy preference; verify system-native behavior in W2. |
| Export data | Obtain a portable data copy. | Trust; reliability | delivers | Keep under Privacy & Data. |
| Delete account | Permanently remove the account and data with a clear confirmation. | Trust; reliability | delivers | Keep visibly reachable but separate from routine settings. |
| Profile editor sheets | Update name, DOB, height. | Accuracy; reliability | partially | Use one profile destination with focused native field editors. |
| Account & subscription legacy detail | See entitlement, renewal, manage, restore, sessions, sign out. | Paid signal; reliability | partially | Merge subscription actions into Subscription; move sessions/sign-out under Account. |
| Photos privacy | Choose whether originals remain in Photos after import. | Privacy guardrail | delivers | Keep under Privacy & Data and clarify destructive effect. |
| Active sessions | Revoke/inspect active account sessions. | Security guardrail | partially | Move beneath Account > Security. |
| Bug report / Help | Report friction or a product defect. | Pull signals; reliability | delivers | Keep in Help/support, reachable from the timeline menu. |

### Coach chat and Talk entry

- **Coach chat:** the live ChatTabView has a persistent conversation, composer, loading/error/retry/delete handling, and a training card that appears only when the hypertrophy coach Statsig gate is enabled. The deterministic training API supplies sessions; the chat layer must explain authorized output rather than prescribe. It fits the roadmap’s second pillar but has no dedicated engagement/quality KPI or complete first-party user-outcome measurement in the roadmap. Verdict: **partially**. Evidence: Views/MainTabView.swift:708-803, 1011-1059; Services/TrainingService.swift; Views/TrainingViews.swift.
- **Talk entry:** no Talk control, voice screen, speech-recognition/audio service, microphone permission, or voice interaction was found in apps/ios/LogYourBody. The older vision mentions voice logging/coaching, but the current roadmap does not define a voice KPI or release scope. Verdict: **dead surface** as a product entry point. Add it only after a defined user job, consent/permission path, safety handling, and pull signal are agreed; do not advertise it as implemented.

## 5. Ranked per-screen IA refactor proposal

Proposed order by effect on core completion and revenue. “Keep” means preserve the job and simplify its route; all items are proposals for Tim.

| Rank | Screen ID | Remove, merge, or move proposal |
| --- | --- | --- |
| P0 | launch | Keep one state router to sign-in, onboarding, paywall, or the paid timeline. |
| P0 | signIn | Merge with verifyAccount so there is one Apple authentication action. |
| P1 | legalConsent | Keep a single explicit consent gate with short policy links; remove repeated consent copy. |
| P2 | biometricLock | Keep as an automatic privacy gate only when enabled; move its control to Privacy. |
| P3 | whatsNew | Move to a dismissible, non-blocking update sheet. |
| P1 | bodyScoreIntro | Shorten to one clear sentence in the first input step; remove a standalone hook if it delays value. |
| P1 | sexAtBirth | Keep only where a validated calculation needs it; retain the explanation and never derive user goals from it. |
| P1 | height | Collect once and reuse for profile completion; remove duplicate height entry. |
| P1 | appleHealth | Explain the value, request permission contextually, and keep manual entry available. |
| P1 | confirmImportedData | Merge into a compact imported-weight confirmation; skip when there is no import. |
| P0 | weight | Keep as the simplest body-score input, but route to a durable first log/import; do not count a BodyScoreInput alone as activation. |
| P1 | bodyFatMethod | Merge method, numeric entry, visual estimate, and skip into one optional branch. |
| P1 | bodyFatValue | Keep as a measured-value editor within the shared add-measurement flow. |
| P2 | visualEstimate | Move under optional estimates; label estimate/source/confidence, or remove if it creates false precision. |
| P1 | calculation | Remove as a destination; use a short progress state before the result. |
| P1 | bodyScoreReveal | Move the useful numbers to the timeline and remove any unsupported composite score; otherwise label its inputs and uncertainty. |
| P1 | chooseHomeView | Remove from onboarding; keep the Golden Path’s photo-timeline landing. |
| P2 | email | Move recovery email into Profile and keep optional where Apple identity suffices. |
| P0 | verifyAccount | Merge with signIn; rename/remove the misleading verification step because the screen is Apple account creation, not email verification. |
| P0 | completeProfile | Replace serial profile substeps with one concise form and reuse earlier values. |
| P2 | firstProgressPhoto | Move to the first timeline session as an optional add; do not gate first use on photo permission. |
| P0 | paywall | Keep one canonical paywall after initial value; consolidate HomeV2PaywallView and PaywallView with identical price/restore rules. |
| P0 | home | Keep one Today surface and make latest datapoint/photo the immediate answer. |
| P0 | photoTimeline | Bind this ID to the real timeline or remove the unused ID; do not leave a second canonical name. |
| P2 | stats | Move under one Progress destination and defer advanced charts until core retention is healthy. |
| P2 | chat | Make one Ask destination, with the home composer as its shortcut; keep training engine output distinct from general chat. |
| P2 | metricDetail | Move under the metric card that opened it; return to the same timeline date. |
| P0 | logWeight | Keep one entry sheet invoked from Today and immediately reflect the saved value/date. |
| P2 | logBodyFat | Merge into the same Add Entry flow as an optional, source-labeled metric. |
| P2 | addProgressPhoto | Share one date-aware photo attach flow with first-photo and bulk-import entry points. |
| P4 | glp1CheckIn | Remove from the core add-entry path until a roadmap KPI and safe, explicit medication scope justify it. |
| P4 | shareBodyScore | Remove by default; if retained, make sharing user-initiated and preview exactly what leaves the device. |
| P0 | syncDetails | Show quiet saved/offline/synced state inline; move diagnostics to a failure-only detail. |
| P3 | dailyReminder | Keep one opt-in setting and one quiet reminder prompt; no streaks or repeated pressure. |
| P0 | planUnavailable | Merge into the canonical paywall’s inline retry/restore error state. |
| P0 | restorePurchases | Use one restore operation exposed on both paywall and subscription settings. |
| P1 | settings | Consolidate HomeV2SettingsView and PreferencesView into one native iOS Settings hierarchy. |
| P1 | editProfile | Keep one Profile route with small field-edit sheets. |
| P1 | trackingAndGoals | Merge units and target editors; move the step goal outside the body-composition core. |
| P1 | integrations | Merge duplicate HealthKit/import routes under Data Sources. |
| P2 | importPhotos | Move bulk import under the timeline’s Add Photo action. |
| P2 | exportData | Keep under one Privacy & Data route. |
| P2 | activeSessions | Move under Account > Security rather than a peer setting. |
| P1 | privacyAndData | Make one privacy destination for photo handling, export, and account actions. |
| P2 | deleteAccount | Keep one clearly destructive destination and confirmation flow. |
| P2 | bugReport | Move to Help/support and keep it discoverable from the timeline menu. |
| P2 | Talk entry (not a WorldClassScreen case) | Keep out of navigation until voice has a measured user job and a working permission/safety path. |

The requested visual direction is native SwiftUI settings with the current Liquid Glass system look. Repository guidance names iOS 26 Glass APIs and availability gates; this document does not claim iOS 27 SDK support or replace W2’s device verification.

## 6. Document/code gaps and evidence caveats

1. **Onboarding count:** the walk brief’s 12-step summary is stale against this checkout: Step has 17 enum cases. The progress sequence has 15 entries because it includes three mutually exclusive body-fat paths and omits loading/paywall from the visible denominator.
2. **Screen registry vs product naming:** Theme.swift declares 46 WorldClassScreen cases. The live timeline is tagged .home; .photoTimeline has no active binding. Weight/body-fat/GLP-1 entry IDs are selected dynamically in AddEntrySheet, so they do have a route despite not using a literal worldClassScreen(.id) call.
3. **Duplicate paywall implementation:** onboarding uses PaywallView, while ContentView also has a HomeV2PaywallView route. The same product/restore contract must hold in both; only the first carries the WorldClassScreen.paywall modifier.
4. **Settings IA:** HomeV2SettingsView and PreferencesView expose overlapping account, subscription, units, goals, HealthKit, reminders, restore, export, and delete actions. The registry’s settings ID currently decorates PreferencesView, not the HomeV2 settings root.
5. **Goal settings mismatch:** the HomeV2 Target surface edits weight and body-fat goals, while legacy Tracking also exposes FFMI and step goals. Decide which goals belong in the current paid body-composition loop, then expose one consistent preference set.
6. **Product vision vs code:** the vision includes a Talk/voice entry; no voice implementation or entry exists in the iOS source. Coach chat and gated engine-returned training output do exist.
7. **Roadmap priority vs implemented surfaces:** GLP-1 dose logging and share-body-score flows are present and tested/documented in the journey inventory, but neither has a direct KPI or place in the current roadmap’s Phase 0/1 core. GLP-1 must remain tracking-only and within the medical/safety boundary if retained.
8. **Profile duplication:** onboarding asks height for a first result and profile completion also contains height/name/DOB/sex substeps; reuse earlier inputs and avoid asking twice.
9. **Funnel definition:** activation combines paywall decision and first log within 24 hours, and onboarding can collect a weight before the paywall. The activation-to-trial figure is therefore a planning cohort share, not a verified chronological step. Define one completion event, timestamps, and denominator before reporting observed rates.
10. **RevenueCat evidence:** current offering contents were not fetched. Local config is empty; verifier requirements and StoreKit test configuration establish expected identifiers/prices, not a live RevenueCat or storefront receipt.
11. **Static audit boundary:** verdicts are based on source and product docs. W2 must confirm actual navigation, current visible hierarchy, and visual execution. No user-facing screen is certified by this map.
12. **First-weight persistence:** manual onboarding weight updates BodyScoreInput; completeOnboardingIfNeeded writes profile data. A dated BodyMetrics baseline is created on the photo-baseline path, while HealthKit sync is deferred when requested. If photo is skipped and sync is off, this onboarding input alone does not prove a timeline log, despite the User Journeys description of onboarding arriving at the first log. Verify the skipped-photo path against GoldenPathTests and the device walkthrough.
