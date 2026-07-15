# Marketing performance budget

The launch landing page has one job: explain LogYourBody and accept an email. Its runtime cost should reflect that.

The machine-readable source of truth is [`performance-budgets.json`](../performance-budgets.json).

## Release thresholds

- Lighthouse mobile: performance, accessibility, best practices, and SEO each at least 95
- Production p75: LCP at most 2.5 seconds, INP at most 200 milliseconds, CLS at most 0.10
- Compressed JavaScript on the initial route: at most 150 KB
- Initial transfer size: at most 500 KB

Vercel Speed Insights is the production source for Core Web Vitals. Lighthouse should run against a production build before a landing-page release. Treat a threshold regression as a release blocker unless the PR includes measured conversion evidence that justifies the cost.

## Measurement notes

- Test mobile with a cold cache and default Lighthouse throttling.
- Measure the root route with landing experiment flags disabled.
- Do not add third-party tags directly to the page. Route events through the analytics port.
- Keep email and other personal data out of analytics payloads.
- Prefer server-rendered content; isolate interactive code to the waitlist form.
