/** @jest-environment node */
import { NextRequest } from 'next/server';
import { POST } from '../route';
import { parsePDFServer } from '@/lib/pdf-parser';
import { createJsonCompletionPort } from '@/lib/ports/openai-json-completion';

jest.mock('@/lib/auth/jovie-oauth', () => ({
  fetchUserInfo: jest.fn(async () => ({ sub: 'pdf-evidence-user' })),
}));
jest.mock('@/lib/pdf-parser', () => ({ parsePDFServer: jest.fn() }));
jest.mock('@/lib/ports/openai-json-completion', () => ({
  createJsonCompletionPort: jest.fn(),
}));
jest.mock('pdf-lib', () => ({
  PDFDocument: { load: jest.fn(async () => ({ getPages: () => [{}] })) },
}));

const originalAPIKey = process.env.OPENAI_API_KEY;
const completion = jest.fn();
const extractedScan = {
  date: '2026-09-20',
  weight: 82.4,
  weight_unit: 'kg',
  body_fat_percentage: 21.2,
  source: 'Other',
};

function upload() {
  const form = new FormData();
  form.append(
    'file',
    new File(['fixture-pdf'], 'report-82.4kg.pdf', {
      type: 'application/pdf',
    }),
  );
  return new NextRequest('http://localhost/api/parse-pdf', {
    method: 'POST',
    headers: { authorization: 'Bearer fixture-token' },
    body: form,
  });
}

describe('PDF extraction requires document evidence', () => {
  afterEach(() => {
    if (originalAPIKey === undefined) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = originalAPIKey;
  });

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.OPENAI_API_KEY = 'fixture-key';
    jest.mocked(createJsonCompletionPort).mockReturnValue({
      createJsonObjectCompletion: completion,
      createTextCompletion: jest.fn(),
    });
    completion.mockResolvedValue(
      JSON.stringify({
        scans: [extractedScan],
        total_scans: 1,
        extraction_confidence: 'high',
      }),
    );
  });

  it.each(['', '   \n'])(
    'rejects a PDF without readable text (%j) before model extraction',
    async (text) => {
      jest.mocked(parsePDFServer).mockResolvedValue(text);
      const response = await POST(upload());
      expect(response.status).toBe(400);
      expect(await response.json()).toMatchObject({
        error: expect.stringContaining('Could not extract text'),
      });
      expect(completion).not.toHaveBeenCalled();
    },
  );

  it('does not substitute a filename and page count for a failed text extraction', async () => {
    jest.mocked(parsePDFServer).mockRejectedValue(new Error('No readable content'));
    const response = await POST(upload());
    expect(response.status).toBe(400);
    expect(completion).not.toHaveBeenCalled();
  });

  it('continues to extract from real document text and keeps its unknown source', async () => {
    const text =
      'Body composition report. Date: 2026-09-20. Weight: 82.4 kg. Body fat: 21.2%. The measurement device is not identified.';
    jest.mocked(parsePDFServer).mockResolvedValue(text);
    const response = await POST(upload());
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      success: true,
      data: { scans: [extractedScan] },
    });
    expect(completion).toHaveBeenCalledTimes(1);
    expect(completion.mock.calls[0][0].messages).toContainEqual({ role: 'user', content: text });
  });
});
