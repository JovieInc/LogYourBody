import { NextResponse } from 'next/server';

// Collector for the report-only CSP in next.config.ts. Browsers POST
// violation reports here; nothing is blocked while the policy is report-only.
export async function POST(request: Request) {
  const report = await request.json().catch(() => null);
  console.warn('CSP violation report:', report);
  return new NextResponse(null, { status: 204 });
}
