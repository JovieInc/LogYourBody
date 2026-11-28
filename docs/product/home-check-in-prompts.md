# Home check-in prompts and tutorials (LYB-325)

Parent: [LYB-311](https://linear.app/jovie/issue/LYB-311).
Status: recommended default adopted; no override.

## Decision

Home never requires a tutorial to take, save, or view a weekly progress photo.
Any existing guidance stays contextual and skippable, and one ordinary mirror
selfie is sufficient. Side or back photos and measurements remain optional.

When this week's photo is already current, do not ask for another selfie:
no repeat request on Home and no outbound prompt. When a weekly photo is
missing and useful, the [existing LYB-173 action](https://linear.app/jovie/issue/LYB-173)
may ask for it only as Home's single useful next action, not as a second
prompt or a separate tutorial flow.

## Boundary

This records the product decision only. It does not change native app code,
notification schedules, or message copy. [LYB-87](https://linear.app/jovie/issue/LYB-87)
retains the empty stage and first-photo repair.
