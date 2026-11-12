# Home body-stage and shape-control wording (LYB-367)

Recorded: 2026-11-11. Parent: LYB-311.
Status: recommended default adopted for this decision-only slice; no override.

## Stage kinds

Use these exact names for the three Home body-stage kinds:

| Kind                  | User-facing name |
| --------------------- | ---------------- |
| Authentic photo       | Photo            |
| Generic wireframe     | Illustration     |
| Personalized estimate | Estimate         |

## Shape controls

Use these exact names for the three shape controls:

| Control concept | User-facing name |
| --------------- | ---------------- |
| Adiposity       | Fullness         |
| Muscularity     | Build            |
| Proportion      | Proportions      |

Control names contain no percent sign, body-fat wording, or FFMI wording.
They name shape controls, not composition measurements.

## Boundary

This records wording only. The later feature-gated Home stage UI uses these
names. Application source, layout, model math, tutorials, and prompts are
unchanged. This adds no tutorial or repeated prompt.

The health-claim decision remains separate in
[body-composition visual claims (LYB-322)](body-composition-visual-claims.md).
Naming a kind Estimate does not promote personalized estimates or change their
evidence gates. All other LYB-311 work remains outside this slice.

## Verification

Run from the repository root after staging this file. The diff check fails for
any change outside this decision document, including application source. The
text check reads the control names from the table and rejects prohibited wording.

```sh
git diff --exit-code origin/main -- . ':!docs/product/home-body-stage-wording.md'
python3 - <<'PY'
from pathlib import Path
import re

text = Path("docs/product/home-body-stage-wording.md").read_text()
controls = re.findall(
    r"^\| (Adiposity|Muscularity|Proportion)\s*\| ([^|]+?)\s*\|$",
    text, re.MULTILINE,
)
assert len(controls) == 3, "Expected three control names"
assert all(not re.search(r"%|body[\s-]*fat|ffmi", name, re.I)
           for _, name in controls), "Prohibited control wording"
assert controls == [("Adiposity", "Fullness"), ("Muscularity", "Build"),
                    ("Proportion", "Proportions")], "Unexpected control names"
print("Control wording: PASS")
PY
```
