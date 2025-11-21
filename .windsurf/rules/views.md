---
trigger: always_on
---

When generating or editing screens, keep each view/controller focused on a single responsibility. If a screen contains multiple distinct sections, repeated patterns, or section-specific state/logic, split it into subviews/components and move non-UI logic into a ViewModel. Use line counts only as guardrails: aim for ≤500 lines per view/controller and ≤40 lines per function; if exceeded, refactor into named components. Always reuse existing components instead of re-implementing similar UI.