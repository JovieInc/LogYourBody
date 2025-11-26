# Security Policy

## Supported Versions

We provide security updates for the following versions of LogYourBody:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

The LogYourBody team takes security seriously. If you believe you have found a security vulnerability in LogYourBody, please report it to us as described below.

### Please do NOT report security vulnerabilities through public GitHub issues.

Instead, please report them via email to **security@logyourbody.com** or directly to **tim@timwhite.dev**.

Please include the following information in your report:

- Type of issue (e.g. buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit the issue

This information will help us triage your report more quickly.

## Response Timeline

We will acknowledge receipt of your vulnerability report within 48 hours and will send a more detailed response within 72 hours indicating the next steps in handling your report.

After the initial reply to your report, we will keep you informed of the progress towards a fix and may ask for additional information or guidance.

## Disclosure Policy

When we receive a security bug report, we will:

1. Confirm the problem and determine the affected versions
2. Audit code to find any potential similar problems
3. Prepare fixes for all releases still under maintenance
4. Release new versions as soon as possible

We ask that you:

- Give us reasonable time to investigate and mitigate an issue you report before making any information public
- Make a good faith effort to avoid privacy violations, destruction of data, and interruption or degradation of our service

## Security Best Practices

### For Users

- Always use the latest version of LogYourBody
- Keep your dependencies up to date
- Use strong, unique passwords for your account
- Enable two-factor authentication if available
- Be cautious about sharing sensitive health data

### For Developers

- Follow secure coding practices
- Regularly update dependencies
- Run security scans on your code
- Use environment variables for sensitive configuration
- Implement proper input validation
- Use HTTPS for all communications

## Security Features

LogYourBody implements several security measures:

- **Authentication**: Secure user authentication via Supabase Auth
- **Data Encryption**: All data is encrypted in transit and at rest
- **Access Control**: Row Level Security (RLS) policies protect user data
- **Input Validation**: All user inputs are validated and sanitized
- **HTTPS**: All communications are encrypted
- **Payment Security**: PCI-compliant payment processing via Stripe
- **Privacy**: GDPR and privacy law compliance

## Third-Party Security

We rely on several third-party services:

- **Supabase**: Database and authentication
- **Stripe**: Payment processing
- **RevenueCat**: Subscription management
- **Vercel**: Hosting and deployment

These services undergo regular security audits and maintain high security standards.

## Bug Bounty Program

At this time, we do not have a formal bug bounty program. However, we greatly appreciate security researchers who help make LogYourBody safer for everyone.

If you discover a security vulnerability, we will:

- Acknowledge your contribution in our security hall of fame (if desired)
- Provide updates on the status of your report
- Give you credit in our release notes (if desired)

## Contact

For security-related questions or concerns, please contact:

- **Security Email**: security@logyourbody.com
- **General Contact**: tim@timwhite.dev
- **GitHub**: [@JovieInc](https://github.com/JovieInc)

Thank you for helping keep LogYourBody and our users safe!
