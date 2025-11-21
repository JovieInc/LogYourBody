import { NextRequest, NextResponse } from 'next/server'

type DebugMethodResult = Record<string, unknown>

interface DebugPdfResults {
  filename: string
  fileSize: number
  methods: Record<string, DebugMethodResult>
}

// Debug endpoint to see what text is extracted from PDF
export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData()
    const file = formData.get('file') as File
    
    if (!file || file.type !== 'application/pdf') {
      return NextResponse.json({ error: 'Invalid file type' }, { status: 400 })
    }

    const buffer = Buffer.from(await file.arrayBuffer())
    
    // Try different methods to extract text
    const results: DebugPdfResults = {
      filename: file.name,
      fileSize: file.size,
      methods: {}
    }
    
    // Method 1: pdf-parse
    try {
      const pdfParse = await import('pdf-parse')
      const pdfData = await pdfParse.default(buffer)
      results.methods.pdfParse = {
        success: true,
        textLength: pdfData.text.length,
        textPreview: pdfData.text.substring(0, 1000),
        numPages: pdfData.numpages,
        info: pdfData.info
      }
    } catch (error) {
      results.methods.pdfParse = {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }
    }
    
    // Method 2: Check if it's just plain text
    try {
      const textDecoder = new TextDecoder()
      const text = textDecoder.decode(buffer)
      const isProbablyText = text.includes('DEXA') || text.includes('Body Composition') || text.includes('weight')
      results.methods.textDecode = {
        success: isProbablyText,
        textLength: text.length,
        preview: isProbablyText ? text.substring(0, 500) : 'Not plain text'
      }
    } catch {
      results.methods.textDecode = {
        success: false,
        error: 'Failed to decode as text'
      }
    }
    
    return NextResponse.json(results)
  } catch (error) {
    return NextResponse.json({
      error: 'Debug failed',
      details: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 })
  }
}
