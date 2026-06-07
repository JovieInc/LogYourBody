# JOV-2870 Timeline Aggregation Evidence

## Populated History Sample

Fixture:

- January 2, 2026: weight 80 kg, body fat 20%, progress photo
- January 7, 2026: weight 82 kg, body fat 18%
- February 5, 2026: weight 78 kg, body fat 17%, progress photo
- January step days: 5,000 + 7,000
- February step day: 10,000

Expected monthly output:

- `2026-M01`: weight `81.0` present, body fat `19.0` present, FFMI present, steps `12000`, photo count `1`
- `2026-M02`: weight `78.0` present, body fat `17.0` present, FFMI present, steps `10000`, photo count `1`

Expected yearly output:

- `2026`: weight `80.0` present, body fat `18.0` present, steps `22000`, photo count `2`

## Sparse History Sample

Fixture:

- January 1, 2026: weight 80 kg, body fat 20%
- January 15, 2026: weight 82 kg, body fat 18%
- February 10, 2026: 3,000 steps

Expected weekly output:

- `2026-W02`: weight/body-fat/FFMI are `interpolated` with `medium` confidence.
- `2026-W07`: weight/body-fat/FFMI are `last_known`; steps are present.

## Wide Gap Sample

Fixture:

- January 1, 2026: weight 80 kg, body fat 20%
- February 15, 2026: 9,000 steps
- March 15, 2026: weight 85 kg, body fat 18%

Expected monthly output:

- `2026-M02`: weight/body-fat/FFMI remain `missing` because the interpolation gap is wider than 30 days; steps are present.
