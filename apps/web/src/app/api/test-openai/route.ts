import { NextResponse } from 'next/server'
import { serverEnv } from '@/env-server'

export async function GET() {
  try {
    const apiKey = serverEnv.OPENAI_API_KEY
    const hasApiKey = !!apiKey
    const apiKeyPreview = apiKey
      ? `${apiKey.substring(0, 7)}...${apiKey.substring(apiKey.length - 4)}`
      : 'Not set'
    
    // Test OpenAI connection
    let openAIStatus = 'Not tested'
    let openAIError = null
    
    if (hasApiKey) {
      try {
        const OpenAI = (await import('openai')).default
        const openai = new OpenAI({
          apiKey,
        })
        
        // Make a simple test request
        const completion = await openai.chat.completions.create({
          model: "gpt-4o-mini",
          messages: [
            { role: "system", content: "You are a test assistant." },
            { role: "user", content: "Say 'API working'" }
          ],
          max_tokens: 10,
        })
        
        openAIStatus = completion.choices[0]?.message?.content || 'Unknown response'
      } catch (error) {
        openAIError = error instanceof Error ? error.message : 'Unknown error'
        openAIStatus = 'Failed'
      }
    }
    
    // Test pdf-parse availability
    let pdfParseAvailable = false
    try {
      await import('pdf-parse')
      pdfParseAvailable = true
    } catch {
      pdfParseAvailable = false
    }
    
    return NextResponse.json({
      status: 'OK',
      checks: {
        openAI: {
          hasApiKey,
          apiKeyPreview,
          connectionStatus: openAIStatus,
          error: openAIError
        },
        pdfParse: {
          available: pdfParseAvailable
        }
      }
    })
  } catch (error) {
    return NextResponse.json({
      status: 'Error',
      error: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 })
  }
}