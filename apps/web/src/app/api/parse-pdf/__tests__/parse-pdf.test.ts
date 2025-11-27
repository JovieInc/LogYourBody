/**
 * @jest-environment node
 */
import { POST } from '../route';
import OpenAI from 'openai';

type WeightUnit = 'kg' | 'lbs';

interface MockScan {
  date: string;
  weight: number;
  weight_unit: WeightUnit;
  body_fat_percentage?: number;
  muscle_mass?: number;
  source: string;
}

interface MockOpenAIResponseData {
  scans: MockScan[];
  total_scans: number;
  extraction_confidence: 'low' | 'medium' | 'high';
  extraction_notes?: string;
}

// Mock Next.js server components
jest.mock('next/server', () => ({
  NextRequest: jest.fn().mockImplementation((url, init) => {
    return {
      url,
      method: init?.method || 'GET',
      body: init?.body,
      formData: async () => init?.body,
    };
  }),
  NextResponse: {
    json: (data: unknown, init?: ResponseInit) => ({
      json: async () => data,
      status: init?.status ?? 200,
    }),
  },
}));

// Mock OpenAI
jest.mock('openai');

// Mock pdf-parse
jest.mock('pdf-parse', () => {
  return jest.fn((buffer) => {
    if (buffer.toString().includes('valid-pdf')) {
      return Promise.resolve({
        text: 'DEXA Scan Results\nDate: 2024-01-15\nWeight: 180 lbs\nBody Fat: 15.5%\nMuscle Mass: 145 lbs',
        numpages: 1,
        info: {},
      });
    } else if (buffer.toString().includes('multi-scan')) {
      return Promise.resolve({
        text: `DEXA Scan History
        Scan 1: Date: 2024-01-15, Weight: 180 lbs, Body Fat: 15.5%
        Scan 2: Date: 2024-02-15, Weight: 175 lbs, Body Fat: 14.2%
        Scan 3: Date: 2024-03-15, Weight: 172 lbs, Body Fat: 13.8%`,
        numpages: 1,
        info: {},
      });
    } else if (buffer.toString().includes('empty-pdf')) {
      return Promise.resolve({
        text: '',
        numpages: 1,
        info: {},
      });
    }
    throw new Error('PDF parse error');
  });
});

describe('PDF Parsing API', () => {
  const mockOpenAIResponse = (data: MockOpenAIResponseData) => {
    const mockCreate = jest.fn().mockResolvedValue({
      choices: [
        {
          message: {
            content: JSON.stringify(data),
          },
        },
      ],
    });

    const mockOpenAI = {
      chat: {
        completions: {
          create: mockCreate,
        },
      },
    };

    (OpenAI as jest.MockedClass<typeof OpenAI>).mockImplementation(
      () => mockOpenAI as unknown as OpenAI,
    );

    return mockCreate;
  };

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.OPENAI_API_KEY = 'test-api-key';
  });

  describe('Single Scan Extraction', () => {
    it('should extract data from a valid PDF with single scan', async () => {
      mockOpenAIResponse({
        scans: [
          {
            date: '2024-01-15',
            weight: 180,
            weight_unit: 'lbs',
            body_fat_percentage: 15.5,
            muscle_mass: 145,
            source: 'DEXA Scan',
          },
        ],
        total_scans: 1,
        extraction_confidence: 'high',
      });

      const formData = new FormData();
      const file = new File(['valid-pdf'], 'test.pdf', { type: 'application/pdf' });
      formData.append('file', file);

      const { NextRequest } = require('next/server');
      const request = new NextRequest('http://localhost:3000/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.scans).toHaveLength(1);
      expect(data.data.scans[0].weight).toBe(180);
      expect(data.data.scans[0].body_fat_percentage).toBe(15.5);
    });
  });

  describe('Multiple Scan Extraction', () => {
    it('should extract multiple scans from PDF history', async () => {
      mockOpenAIResponse({
        scans: [
          {
            date: '2024-01-15',
            weight: 180,
            weight_unit: 'lbs',
            body_fat_percentage: 15.5,
            source: 'DEXA Scan',
          },
          {
            date: '2024-02-15',
            weight: 175,
            weight_unit: 'lbs',
            body_fat_percentage: 14.2,
            source: 'DEXA Scan',
          },
          {
            date: '2024-03-15',
            weight: 172,
            weight_unit: 'lbs',
            body_fat_percentage: 13.8,
            source: 'DEXA Scan',
          },
        ],
        total_scans: 3,
        extraction_confidence: 'high',
      });

      const formData = new FormData();
      const file = new File(['multi-scan'], 'history.pdf', { type: 'application/pdf' });
      formData.append('file', file);

      const { NextRequest } = require('next/server');
      const request = new NextRequest('http://localhost:3000/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.scans).toHaveLength(3);
      expect(data.scanCount).toBe(3);

      // Verify scans are in chronological order
      expect(data.data.scans[0].date).toBe('2024-01-15');
      expect(data.data.scans[1].date).toBe('2024-02-15');
      expect(data.data.scans[2].date).toBe('2024-03-15');
    });
  });

  describe('Data Validation', () => {
    it('should reject invalid weight values', async () => {
      mockOpenAIResponse({
        scans: [
          {
            date: '2024-01-15',
            weight: 700, // Invalid weight (>660 lbs)
            weight_unit: 'lbs',
            body_fat_percentage: 15.5,
            source: 'DEXA Scan',
          },
        ],
        total_scans: 1,
        extraction_confidence: 'high',
      });

      const formData = new FormData();
      const file = new File(['valid-pdf'], 'test.pdf', { type: 'application/pdf' });
      formData.append('file', file);

      const { NextRequest } = require('next/server');
      const request = new NextRequest('http://localhost:3000/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(false);
      expect(data.error).toBe('No valid scan data found');
    });

    it('should reject invalid body fat percentage', async () => {
      mockOpenAIResponse({
        scans: [
          {
            date: '2024-01-15',
            weight: 180,
            weight_unit: 'lbs',
            body_fat_percentage: 75, // Invalid BF%
            source: 'DEXA Scan',
          },
        ],
        total_scans: 1,
        extraction_confidence: 'high',
      });

      const formData = new FormData();
      const file = new File(['valid-pdf'], 'test.pdf', { type: 'application/pdf' });
      formData.append('file', file);

      const { NextRequest } = require('next/server');
      const request = new NextRequest('http://localhost:3000/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(false);
      expect(data.error).toBe('No valid scan data found');
    });

    it('should handle low confidence extractions', async () => {
      mockOpenAIResponse({
        scans: [],
        total_scans: 0,
        extraction_confidence: 'low',
        extraction_notes: 'Could not reliably extract data',
      });

      const formData = new FormData();
      const file = new File(['valid-pdf'], 'test.pdf', { type: 'application/pdf' });
      formData.append('file', file);

      const { NextRequest } = require('next/server');
      const request = new NextRequest('http://localhost:3000/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(false);
      expect(data.error).toBe('Could not reliably extract data from this PDF');
    });
  });

  describe('Error Handling', () => {
    it('should handle missing OpenAI API key', async () => {
      delete process.env.OPENAI_API_KEY;

      const formData = new FormData();
      const file = new File(['valid-pdf'], 'test.pdf', { type: 'application/pdf' });
      formData.append('file', file);

      const { NextRequest } = require('next/server');
      const request = new NextRequest('http://localhost:3000/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(500);
      expect(data.error).toContain('OpenAI API key not configured');
    });

    it('should handle invalid file type', async () => {
      const formData = new FormData();
      const file = new File(['not-a-pdf'], 'test.txt', { type: 'text/plain' });
      formData.append('file', file);

      const { NextRequest } = require('next/server');
      const request = new NextRequest('http://localhost:3000/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toBe('Invalid file type. Please provide a PDF file.');
    });

    it('should handle empty PDF', async () => {
      mockOpenAIResponse({
        scans: [],
        total_scans: 0,
        extraction_confidence: 'low',
      });

      const formData = new FormData();
      const file = new File(['empty-pdf'], 'empty.pdf', { type: 'application/pdf' });
      formData.append('file', file);

      const { NextRequest } = require('next/server');
      const request = new NextRequest('http://localhost:3000/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      const response = await POST(request);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toContain('Could not extract text from PDF');
    });
  });
});
