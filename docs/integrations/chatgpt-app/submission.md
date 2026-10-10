# ChatGPT app submission package (draft, not submitted)

Status: prepared by an agent on 2026-10-04 (LYB-120). Nothing has been submitted and no developer
account has been created. Tim submits, or explicitly approves submission, after the
production prerequisites in [README.md](README.md) are done.

## Listing

**Name:** LogYourBody

**Category:** Health and fitness

**Short description (one line):**
Hear today's hypertrophy session and log your sets by voice.

**Long description:**
LogYourBody plans your hypertrophy training and keeps your logs. Connect your
LogYourBody account to ask what today's session is, log sets between exercises by
speaking ("chest press, two sets of ten at 135 pounds, two in reserve"), record how the
session felt, and check how your lifts have moved.

Every set, rep and load target comes from the LogYourBody training engine, which builds
each session from your logged history and your check-ins. ChatGPT reads the plan back to
you; it does not invent one.

You need a LogYourBody account with the training plan set up in the iPhone app. The app
logs training only. Body composition, photos and health records stay in the LogYourBody
iPhone app.

**Example prompts:**

- What's my workout today?
- Log leg press, two sets of 10 at 180 pounds, 2 reps in reserve.
- I just finished. Soreness 3, pump 7, no joint pain, performance stable.
- How has my chest press moved this month?

**Developer:** LogYourBody (Jovie Inc.)
**Website:** https://www.logyourbody.com
**Privacy policy:** https://logyourbody.com/privacy
**Terms:** https://logyourbody.com/terms
**Support:** https://logyourbody.com/support
**Icon:** `apps/web/public/brand/logyourbody-app-icon.png`
**Countries:** United States first (matches the US compliance corpus); expand after review.

## MCP connectivity

- Server URL: `https://www.logyourbody.com/api/mcp`
- Auth: OAuth 2.1, authorization code with PKCE S256, issuer `https://jov.ie/api/auth`,
  scopes `lyb:training.read lyb:training.write`.
- Tools and annotations: see the table in [README.md](README.md). No tool deletes,
  overwrites, sends, posts or reaches the open web.

## Data use (for the review form and the privacy policy check)

| Data                                                       | Why                                              | Where it goes                                  | Retention                                           |
| ---------------------------------------------------------- | ------------------------------------------------ | ---------------------------------------------- | --------------------------------------------------- |
| Account subject id from the OAuth token                    | Identify whose plan to read and write            | LogYourBody database                           | Life of the account                                 |
| Sets (exercise, reps, load, reps in reserve)               | The user asked to log them                       | LogYourBody database, synced to the iPhone app | Until the user deletes training data or the account |
| Session check-in (soreness, pump, joint pain, performance) | Lets the engine adjust or pause the next session | Same                                           | Same                                                |

Not collected through ChatGPT: email, name, body measurements, photos, medication data,
location, payment data, conversation text. Tool inputs are only the fields listed above.
The privacy policy must name ChatGPT and other connected assistants as a way data enters
LogYourBody before submission (tracked in the submission issue).

## Commerce

None. The app sells nothing, shows no prices, and does not mention plans or upgrades. It
works for any linked LogYourBody account that finished training setup in the iPhone app.

## Audience and safety

- Suitable for users 13 to 17 in the sense OpenAI requires: no adult content and no
  advice. Training itself is only available to accounts that confirmed adult age and the
  safety consent in the iPhone app, so a minor gets the "set up in the app" message.
- Joint pain of 4 or more pauses the affected work and points to a qualified clinician.
- No medical, disease or medication claims (checked with `scripts/lint-claims.mjs`).

## Review test account (to create before submission)

A dedicated LogYourBody account, adult profile, training plan enrolled (3 days, full gym),
two weeks of seeded sets and check-ins so every tool returns real data. Credentials go in
the OpenAI submission form only, never in this repo.

## Screenshots to capture (developer mode, after the issuer is configured)

1. Asking "What's my workout today?" with the session list in the answer.
2. Voice mode logging two sets, with the confirmation.
3. "How has my chest press moved?" with the progress answer.
4. The account connection screen showing the LogYourBody consent and scopes.

## Pre-submission checklist

- [ ] Jovie issuer: resource, scopes, ChatGPT client (README prerequisites)
- [ ] `LYB_CHATGPT_MCP_ENABLED` and `LYB_HYPERTROPHY_COACH_API_ENABLED` on in production
- [ ] Privacy policy names connected assistants as a data source
- [ ] Review test account seeded
- [ ] Screenshots captured
- [ ] OpenAI organization verification (Tim)
- [ ] Tim submits or approves submission
