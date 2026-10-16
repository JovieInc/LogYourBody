import {
  markdownResponse,
  missingPageMarkdown,
  PUBLIC_MARKDOWN_HEADER,
} from '@/lib/marketing/public-markdown';

export function GET(request: Request): Response {
  // Middleware strips client values; only a positive gate decision supplies this.
  if (request.headers.get(PUBLIC_MARKDOWN_HEADER) !== '1') {
    return new Response(null, { status: 404, headers: { 'Cache-Control': 'no-store' } });
  }
  return markdownResponse(missingPageMarkdown(), 404, request.method);
}

export const HEAD = GET;
