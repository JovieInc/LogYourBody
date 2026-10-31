# LogYourBody certification

LogYourBody follows the company public app certification standard in full:
JovieInc/ci `canon/PUBLIC-APP-CERTIFICATION.md`. This directory is only the
app config; the machinery (walker, frame judge, buyer eval, privacy loop with
the stricter `health` profile, customer voice, receipts) is the shared kit in
JovieInc/ci `certify/`.

- `app.json`: golden path, paid outcome (live price read from the product registry), privacy, customer channels, waste and capacity ids
- `personas.json`, `calibration.json`: buyer-eval archetypes, known-bad holdouts and the off-ICP control
- `tracker-registry.json`: every third party with a category and rationale
- `flows/web.mjs`: web leg of the golden path; the iOS leg is `OnboardingGoldenPathUITests` on the mac lane

Canary and test accounts only. No real user data or PII in this directory.
