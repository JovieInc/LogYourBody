# App Store min-SDK table and guard — source of truth

These three files are vendored **byte-identically** from JovieInc/Jovie (JOV-13089), so LogYourBody and Jovie cannot drift:

| File in this repo | Source path in Jovie |
| --- | --- |
| `apps/ios/config/app-store-min-sdk.json` | `apps/ios/config/app-store-min-sdk.json` |
| `apps/ios/Scripts/verify-app-store-min-sdk.mjs` | `apps/ios/scripts/verify-app-store-min-sdk.mjs` |
| `apps/ios/Scripts/verify-app-store-min-sdk.test.mjs` | `apps/ios/scripts/verify-app-store-min-sdk.test.mjs` |

The `.mjs` files live under `Scripts` (capital S) because that is this repo's git-canonical directory. The script's default table path is `../config/app-store-min-sdk.json` relative to the script, so the layout is equivalent.

- Jovie PR: https://github.com/JovieInc/Jovie/pull/26026
- Jovie branch: `jov-13089-ios-min-sdk-guard`
- Jovie commit: `403f79c9c22d44abd2900f0977edff06a38a53b4`

sha256 (must remain identical to Jovie):

```
81b47fc09d207eec54dca93fca243762e7fe1fbe68f06ddb372a3f3c51cc4032  apps/ios/config/app-store-min-sdk.json
10222ed11f4ea80629976f90bf74c0c48fc84620b702f01fad073e489ca9fea0  apps/ios/Scripts/verify-app-store-min-sdk.mjs
540d5f4f86a75841852dbd36a52aef5c6fd408e4762df827e2a1ae5eba8a346d  apps/ios/Scripts/verify-app-store-min-sdk.test.mjs
```

Do not edit the three vendored files in this repo. Update them only by re-copying from Jovie. A CI check that compares these hashes to Jovie `main` after JOV-13089 merges is LATER.
