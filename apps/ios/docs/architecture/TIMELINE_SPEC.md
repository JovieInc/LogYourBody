# Global Timeline Scrubber – Specification

## 1. Overview

The **global timeline scrubber** is a shared header component that appears on the:

- **Home** screen
- **Photos** tab
- **Metrics** tab

It exposes a single **global time cursor** that lets the user scrub from their most recent history back to the beginning of their data with minimal effort. All major surfaces subscribe to this cursor so the experience feels like one continuous timeline instead of three separate screens.

This document defines:

- Time scales and zones (weeks → months → years)
- Data model and bucket construction
- Metric aggregation and interpolation rules
- Body score integration (full / partial / none)
- Per-screen behavior contracts
- No-data and low-data states

The body score algorithm itself is **out of scope** here and is treated as a black box function which can evolve over time.

---

## 2. Concepts & Terminology

### 2.1 Core types (conceptual)

All types below are **conceptual contracts**, not final Swift APIs.

- **TimelineScale**
  - `.week` – recent weekly history (fine resolution)
  - `.month` – recent month-level history (medium resolution)
  - `.year` – older year-level history (coarse resolution)

- **TimelineCursor**
  - Represents "where we are" on the timeline.
  - Fields:
    - `date: Date` – any date inside the selected bucket
    - `scale: TimelineScale` – current zoom level (week / month / year)
    - `bucketId: String` – stable identifier for the selected bucket (e.g. `2025-W42`, `2025-07`, `2023`)

- **MetricPresence**
  - `.present` – metric has direct observations in the bucket window
  - `.estimated` – metric is derived from interpolation / carry-forward
  - `.missing` – no reasonable value can be produced

- **BodyScoreCompleteness**
  - `.full` – all core metrics are present (or high-confidence estimates)
  - `.partial` – body score computed from a subset of core metrics
  - `.none` – not enough data to compute a reasonable score

- **MetricValue** (per metric, per bucket)
  - `value: Double?`
  - `presence: MetricPresence`

- **MetricsSnapshot** (per bucket)
  - Scalar metrics (examples – not exhaustive):
    - `weight: MetricValue`
    - `bodyFat: MetricValue`
    - `ffmi: MetricValue`
    - `steps: MetricValue` (or activity)
  - Visual / media:
    - `canonicalPhotoId: String?` – representative photo for bucket, if any
    - `hasPhotosInRange: Bool`
  - Body score:
    - `bodyScore: Double?` – output of the current body score algorithm
    - `bodyScoreCompleteness: BodyScoreCompleteness`

- **TimelineBucket**
  - Defines one selectable unit in the timeline.
  - Fields:
    - `id: String` – stable key (week / month / year based)
    - `scale: TimelineScale`
    - `startDate: Date`
    - `endDate: Date`
    - `metrics: MetricsSnapshot`

### 2.2 Events vs. buckets

Source data is stored as **atomic events**, not pre-bucketed check-ins:

- `WeightEvent(date, weight)`
- `BodyFatEvent(date, bodyFat)`
- `DexaEvent(date, ffmi, leanMass, fatMass, …)`
- `PhotoEvent(date, photoId, tags…)`
- `StepsEvent(date, steps)`
- Additional metrics over time

Timeline buckets (weeks / months / years) are **derived views** over these events. Users do not need to perform a perfect "full" check-in for a bucket to exist; buckets can be computed from partial, irregular data across streams.

---

## 3. Time Scales & Zones

The header timeline is divided into three logical zones, arranged from right (most recent) to left (oldest):

### 3.1 Zone A – Recent weeks (fine)

- **Coverage**
  - Up to the **last 3–4 check-in weeks** with any meaningful data.
  - A week is defined as a `DateInterval` based on the user's preferred check-in weekday (e.g. Monday–Sunday) or a fixed invariant (e.g. ISO week).
- **Bucket type**
  - `TimelineScale.week`
  - Each bucket represents a single check-in week.
- **Inclusion rules**
  - Include the most recent weeks (up to 4) that contain at least one event from any of:
    - Weight / body composition events
    - DEXA events
    - Steps / activity
    - Progress photos
  - Weeks with absolutely no events are **not** rendered as buckets in Zone A.
- **Interpolation**
  - No interpolation between weekly buckets in Zone A.
  - All `MetricValue` instances in Zone A are either:
    - `.present` – directly derived from events in that week
    - `.estimated` – via short-range carry-forward within a bounded window (per-metric)
    - `.missing` – if nothing usable is available

### 3.2 Zone B – Recent months (medium)

- **Coverage**
  - **6 calendar months** immediately preceding the oldest week in Zone A.
  - Example: If Zone A covers weeks in Oct–Nov 2025, Zone B might cover Apr–Sep 2025.
- **Bucket type**
  - `TimelineScale.month`
  - One bucket per calendar month.
- **Inclusion rules**
  - All months within the 6-month window are conceptually part of Zone B.
  - UI may visually de-emphasize months with no data.

### 3.3 Zone C – Older years (coarse)

- **Coverage**
  - All calendar years from the current year back to the **year of the first data point**.
- **Bucket type**
  - `TimelineScale.year`
  - One bucket per calendar year.
- **Inclusion rules**
  - Do not render years entirely before the first recorded event.
  - Consider optional "bridge years" only between two strong data years (see interpolation rules below).

---

## 4. Bucket Construction & Aggregation Rules

### 4.1 Weekly buckets (Zone A)

Each weekly bucket is built from events in its `DateInterval`.

**Per-metric aggregation (examples):**

- **Weight**
  - `weight.value` = median of all weight events in the week (or the last event if only one).
  - `weight.presence`:
    - `.present` if ≥1 weight event in week.
    - `.estimated` if no weight events this week but a recent week (within N weeks) has weight (carry-forward with decay).
    - `.missing` if the last weight measurement is older than the acceptable freshness window.

- **Body fat**
  - Similar to weight.
  - DEXA events can populate both `bodyFat` and `ffmi` when present.

- **FFMI / composition metrics**
  - Derived from DEXA or other composition events.
  - If composition last measured within a longer freshness window (e.g. several months), can be treated as `.estimated` in more recent weeks.

- **Steps / activity**
  - `steps.value` = mean daily steps across the week (from daily step events).
  - `steps.presence` is `.present` if steps coverage is sufficient (e.g. ≥5 of 7 days).

- **Photos**
  - `hasPhotosInRange` = true if any `PhotoEvent` in the week.
  - `canonicalPhotoId` picks a single representative photo:
    - Prefer a photo closest to the center of the week.
    - If multiple, arbitrary but stable tie-breaker (e.g. earliest ID).

**Weekly body score:**

- We treat the body score function as `f(metrics, version)`.
- Inputs come from the weekly `MetricsSnapshot`.
- Completeness rules:
  - `.full` – all core metrics for `f` are `.present` (or high-confidence `.estimated`).
  - `.partial` – at least one core metric is `.present` but others are `.estimated` or `.missing`.
  - `.none` – not enough core metrics to compute a meaningful score.

### 4.2 Monthly buckets (Zone B)

Monthly buckets aggregate across weekly buckets that fall in the given calendar month.

**Per-metric aggregation:**

- Use precomputed weekly `MetricValue`s as inputs.
- For each metric:
  - Consider only weeks where `presence` is `.present` or high-confidence `.estimated`.
  - Compute a representative monthly value, e.g.:
    - `weightMonth.value` = median of `weightWeekly.value` for eligible weeks in the month.
    - `bodyFatMonth.value` = median of body fat weekly values.
    - `stepsMonth.value` = mean of weekly steps.
  - `presence` rules:
    - `.present` if ≥1 eligible weekly value in the month.
    - `.estimated` if derived mainly from estimated weekly inputs but still reasonably grounded.
    - `.missing` if no eligible weekly values exist.

**Monthly interpolation:**

- Only interpolate **between months that have data**.
- For a month with no data but neighbors with present values:
  - Interpolate each metric separately (e.g. linear interpolation on the aggregated values).
  - Mark `presence = .estimated` for that metric.
  - Cap the interpolation window (e.g. do not interpolate across gaps of >2 consecutive missing months).

**Monthly body score:**

- Inputs are the per-metric monthly representatives.
- The same `f(metrics, version)` function is used.
- Completeness is computed as in the weekly case.

### 4.3 Yearly buckets (Zone C)

Yearly buckets aggregate across monthly buckets in the given calendar year.

**Per-metric aggregation:**

- Use final monthly `MetricValue`s as inputs.
- For each metric:
  - `weightYear.value` = median of `weightMonth.value` for all months with present values.
  - Similar logic for body fat, FFMI, steps, etc.
  - `presence` rules:
    - `.present` if enough months have present values.
    - `.estimated` if primarily derived from estimated months.
    - `.missing` if the year has almost no usable data.

**Yearly interpolation:**

- Prefer **real** yearly aggregates.
- Optionally interpolate **one or two bridge years** only when:
  - The year has no data.
  - Surrounding years both have strong data.
- Bridge years are always `presence = .estimated` for all metrics and visually de-emphasized.

**Yearly body score:**

- Inputs are per-metric yearly representatives.
- Uses the same body score function `f` and completeness rules.

---

## 5. Body Score Integration

### 5.1 Black-box algorithm

The body score algorithm is not defined here. We assume an API like:

- `bodyScore = f(metricsSnapshot, version)`

Where `version` can be used to A/B test and evolve weighting without changing the timeline contract.

### 5.2 Versioning

- Maintain an internal `bodyScoreVersion` so historical scores can be recomputed consistently when the algorithm changes.
- Analytics can log which version produced which scores.

### 5.3 Full, partial, none

Every `TimelineBucket.metrics` carries:

- `bodyScore: Double?`
- `bodyScoreCompleteness: BodyScoreCompleteness`

UI behavior:

- `.full` – normal visual state.
- `.partial` – subtle badge or caption, e.g. "Based on weight only".
- `.none` – hero shows a friendly message instead of a number, e.g. "No body score for this week".

---

## 6. Per-Screen Behavior Contracts

All three main surfaces subscribe to the same `TimelineCursor` and `TimelineBucket` stream. They should **not** implement their own independent time cursors.

### 6.1 Home Screen

- **Header**
  - Displays the global timeline scrubber.
  - Shows current selection label:
    - Week: "Week of Oct 21"
    - Month: "July 2025"
    - Year: "2023"

- **Body Score hero**
  - Binds to `bucket.metrics.bodyScore` and `bodyScoreCompleteness`.
  - Animates the value when the cursor snaps to a new bucket.
  - Shows descriptive caption:
    - Weekly: "vs last week"
    - Monthly: "vs last month"
    - Yearly: "vs last year"

- **Secondary metric tiles**
  - Each tile reads its `MetricValue` from the bucket snapshot.
  - Deltas are always computed **relative to the previous bucket at the same scale**.
  - Tiles must handle `present`, `estimated`, and `missing` states explicitly.

### 6.2 Photos Tab

- **Header**
  - Uses the same global timeline.

- **Primary photo view**
  - Binds to `bucket.metrics.canonicalPhotoId` and `hasPhotosInRange`.
  - If no photo exists for the bucket:
    - Show an empty state for that bucket: "No photo near this date yet".
    - Offer CTA to add a photo anchored to a date inside the bucket.

- **Secondary photo rail (optional)**
  - Shows nearby photos around the bucket interval for scrubbing-like behavior when data is dense.

### 6.3 Metrics Tab

- **Header**
  - Same as Home and Photos.

- **Metric hero cards**
  - Each card:
    - Reads its value and presence state from the bucket.
    - Highlights the selected bucket on its chart:
      - Week: single point.
      - Month: shaded month region.
      - Year: shaded year region or year dot.
  - If a metric is `.missing` for the selected bucket, card should show a friendly informative state rather than 0.

---

## 7. No-Data and Low-Data States

### 7.1 Zero data (brand-new user)

- **Timeline**
  - Render a placeholder, non-interactive bar:
    - Text: "Your timeline will appear after your first check-in".
    - No knob, no scrubbing.

- **Home**
  - Body score hero shows "No body score yet".
  - CTA: "Log first weekly check-in".

- **Photos**
  - Empty state inviting the first progress photo.

- **Metrics**
  - Skeleton cards or empty states instead of real numbers.

### 7.2 Very little data (1–3 weeks total)

- **Timeline**
  - Zone A contains 1–3 week buckets.
  - Zones B and C are hidden or visually minimized until enough history exists.

- **Body score**
  - Weekly body scores only; conceptually, month/year could reuse them but are not exposed yet.

### 7.3 Some data but not enough for all zones

- **Fewer than 6 months**
  - Zone B displays only the months that actually contain data.
  - Months without data inside that short history window may be omitted or rendered as faint placeholders.

- **Sparse early history**
  - Zone C shows only years with sufficient data.
  - Avoid long runs of empty years; prefer fewer, more meaningful buckets.

---

## 8. Partial & Missing Data Behavior

The system must support weeks/months/years where only **some** data types exist:

- Weight but no body fat.
- DEXA but no photo.
- Photo only.

Rules:

- Buckets are constructed from **all available events**, not only "full check-ins".
- Each metric independently tracks `MetricPresence`.
- Body score uses whatever subset of metrics is available and reports `BodyScoreCompleteness`.
- Screens must visually distinguish:
  - Real values.
  - Estimated values.
  - Missing values.

Examples:

- **Weight only** week:
  - Weight: `.present`.
  - Body fat: `.missing` or `.estimated` (if recently measured elsewhere).
  - Body score: `.partial` (weight-driven).

- **Photo only** week:
  - Photos: `.present` in the bucket.
  - All scalar metrics: `.missing`.
  - Body score: `.none`.
  - Photos tab still shows that week as a meaningful timeline position.

- **DEXA without photo**:
  - Composition metrics: `.present`.
  - Photos: `.missing`.
  - Body score: likely `.full` due to rich composition inputs.

---

## 9. Interaction & UX Notes (High-Level)

While visual implementation details live in design system docs, the timeline must obey these interaction contracts:

- **Snapping**
  - Dragging moves a knob across buckets; on release, it snaps to the nearest bucket (week/month/year).
  - Haptics trigger on each bucket snap.

- **Tap to jump**
  - Tapping a bucket region selects it immediately.

- **Today affordance**
  - A clear affordance (e.g. "Today" chip) resets the cursor to the most recent week bucket.

- **Performance**
  - Aggregated `TimelineBucket` and `MetricsSnapshot` values should be precomputed or cached so that scrubbing feels instant.

---

## 10. Implementation Notes & Next Steps

- Implement the timeline data layer as a **shared service** that:
  - Watches underlying metric/photo events.
  - Maintains weekly/monthly/yearly aggregates.
  - Exposes a stream of `TimelineBucket` + `TimelineCursor` to interested views.

- Keep the body score function versioned and decoupled from the timeline logic.
- Ensure all three main surfaces (Home, Photos, Metrics) bind to the same cursor for a coherent multi-tab experience.
