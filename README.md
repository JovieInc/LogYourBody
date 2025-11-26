# LogYourBody

A comprehensive body metrics tracking platform with native iOS and web applications for monitoring health and fitness progress.

## Overview

LogYourBody helps users track their body composition changes over time through manual logging and automated data imports from DEXA scans, InBody analyses, and other body composition measurement devices.

## AI Issue Triage

This repository uses an intelligent AI-powered issue triage system. When you create a new issue, it will automatically:
- Analyze the content and recommend the best AI tool (Sweep, Copilot, or Claude)
- Add appropriate labels
- Comment with instructions

[Learn more about AI triage →](docs/ai-issue-triage.md)

## Project Structure

This monorepo contains two main applications:

### 📱 iOS App (`/apps/ios`)

Native SwiftUI application for iPhone that provides:
- **HealthKit Integration**: Syncs steps data with Apple Health
- **Body Metrics Tracking**: Log weight, body fat %, muscle mass, and measurements
- **Photo Progress**: Capture and compare progress photos
- **Offline Support**: Core Data for local storage with background sync
- **Real-time Sync**: Automatic synchronization with Supabase backend

**Tech Stack:**
- SwiftUI
- HealthKit
- Core Data
- Supabase Swift SDK
- Clerk for authentication

### 🌐 Web App (`/apps/web`)

Modern web application built with Next.js that offers:
- **Dashboard**: Visualize trends and progress with interactive charts
- **PDF Import**: Extract data from DEXA/InBody scan PDFs using AI
- **Manual Entry**: Log body metrics with an intuitive interface
- **Mobile Responsive**: Optimized for all devices
- **Real-time Updates**: Live synchronization across devices

**Tech Stack:**
- Next.js 14 (App Router)
- TypeScript
- Tailwind CSS
- Supabase
- Clerk for authentication
- OpenAI for PDF parsing

## Features

### Core Features
- ✅ Multi-platform support (iOS & Web)
- ✅ Real-time data synchronization
- ✅ Secure authentication with Clerk
- ✅ Progress photo tracking
- ✅ Historical data visualization
- ✅ PDF scan import (DEXA, InBody)
- ✅ Apple Health integration (iOS)

### Coming Soon
- 🚧 Android app
- 🚧 Wearable device integrations
- 🚧 AI-powered insights
- 🚧 Social features & challenges

## Getting Started

### Prerequisites
- Node.js 20+
- pnpm (recommended for this monorepo)
- Xcode 15+ (for iOS development)
- Supabase account
- Clerk account

### Installation

1. Clone the repository:
```bash
git clone https://github.com/itstimwhite/LogYourBody.git
cd LogYourBody
```

2. Install dependencies (from the repo root):
```bash
pnpm install
```

3. Set up environment variables:
   - Copy `.env.example` to `.env` in `/apps/web`
   - Add your Supabase and Clerk credentials

4. Run the web app:
```bash
cd apps/web
pnpm dev
```

5. Run the iOS app:
   - Open `/apps/ios/LogYourBody.xcodeproj` in Xcode
   - Configure signing & capabilities
   - Build and run on simulator or device

## Database Schema

The application uses Supabase with PostgreSQL. Key tables include:
- `profiles`: User profile information
- `body_metrics`: Weight, body fat %, muscle mass records
- `body_measurements`: Detailed body measurements
- `daily_metrics`: Steps and activity data

Row Level Security (RLS) ensures users can only access their own data.

## Development Scripts

The monorepo is managed with **pnpm workspaces** and **Turborepo**. Run these from the repo root:

- `pnpm dev` – Start the web dev server (apps/web)
- `pnpm build` – Run the Turborepo build pipeline
- `pnpm test` – Run tests across workspaces
- `pnpm test:ci` – Run tests in CI mode (`--runInBand`)
- `pnpm lint` – Run all linters across workspaces
- `pnpm typecheck` – TypeScript type checking across workspaces
- `pnpm ios` – Open the iOS project in Xcode

You can still run app-specific scripts directly, for example:

- `cd apps/web && pnpm dev`
- `cd apps/web && pnpm test`

## Deployment

### Web App
The web app is configured for deployment on Vercel:
```bash
cd apps/web
pnpm build
```

### iOS App
The iOS app can be distributed via TestFlight or the App Store.

## Contributing

We welcome contributions! Please see our contributing guidelines for more details.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support, email support@logyourbody.com or open an issue on GitHub.

---

Built with ❤️ by the LogYourBody team