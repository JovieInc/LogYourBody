# Widget Setup

LogYourBody does not currently ship a Widget Extension target. The previous
widget scaffolding was retired because the app target was still doing recurring
widget refresh work even though no widget binary existed.

Do not re-add `WidgetDataManager` or background widget refresh timers unless a
new Widget Extension target is added to `LogYourBody.xcodeproj` and validated as
part of the release plan.
