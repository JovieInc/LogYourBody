import { NextResponse } from 'next/server';
import { createJsonCompletionPort } from '@/lib/ports/openai-json-completion';

export async function GET() {
  try {
    const hasApiKey = !!process.env.OPENAI_API_KEY;
    const apiKeyPreview = process.env.OPENAI_API_KEY
      ? `${process.env.OPENAI_API_KEY.substring(0, 7)}...${process.env.OPENAI_API_KEY.substring(process.env.OPENAI_API_KEY.length - 4)}`
      : 'Not set';

    // Test OpenAI connection
    let openAIStatus = 'Not tested';
    let openAIError = null;

    if (hasApiKey) {
      try {
        const completionPort = createJsonCompletionPort(process.env.OPENAI_API_KEY!);

        // Make a simple test request
        const completion = await completionPort.createTextCompletion({
          model: 'gpt-4o-mini',
          messages: [
            { role: 'system', content: 'You are a test assistant.' },
            { role: 'user', content: "Say 'API working'" },
          ],
          maxTokens: 10,
        });

        openAIStatus = completion || 'Unknown response';
      } catch (error) {
        openAIError = error instanceof Error ? error.message : 'Unknown error';
        openAIStatus = 'Failed';
      }
    }

    // Test pdf-parse availability
    let pdfParseAvailable = false;
    try {
      await import('pdf-parse');
      pdfParseAvailable = true;
    } catch {
      pdfParseAvailable = false;
    }

    return NextResponse.json({
      status: 'OK',
      checks: {
        openAI: {
          hasApiKey,
          apiKeyPreview,
          connectionStatus: openAIStatus,
          error: openAIError,
        },
        pdfParse: {
          available: pdfParseAvailable,
        },
      },
    });
  } catch (error) {
    return NextResponse.json(
      {
        status: 'Error',
        error: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 },
    );
  }
}
