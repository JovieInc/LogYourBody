import { NextRequest, NextResponse } from 'next/server'
import OpenAI from 'openai'

// We'll use dynamic import for PDF.js
async function setupPdfJs() {
  const pdfjsLib = await import('pdfjs-dist')
  pdfjsLib.GlobalWorkerOptions.workerSrc = `//cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version}/pdf.worker.min.js`
  return pdfjsLib
}

async function extractTextFromPDF(buffer: ArrayBuffer): Promise<string> {
  try {
    const pdfjsLib = await setupPdfJs()

    // Load the PDF document
    const loadingTask = pdfjsLib.getDocument({
      data: buffer,
      useSystemFonts: true,
    })

    const pdf = await loadingTask.promise
    let fullText = ''

    // Extract text from each page
    for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
      const page = await pdf.getPage(pageNum)
      const textContent = await page.getTextContent()

      // Combine text items
      const itemsWithText = textContent.items
        .filter((item) => typeof (item as { str?: unknown }).str === 'string') as { str: string }[]
      const pageText = itemsWithText
        .map((item) => item.str)
        .join(' ')

      fullText += pageText + '\n\n'
    }

    return fullText
  } catch (error) {
    console.error('Error extracting text with PDF.js:', error)
    throw error
  }
}

export async function POST(request: NextRequest) {
  try {
    // Check if OpenAI API key is configured
    if (!process.env.OPENAI_API_KEY) {
      return NextResponse.json(
        { error: 'OpenAI API key not configured' },
        { status: 500 }
      )
    }

    const openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    })

    // Get the PDF file from the request
    const formData = await request.formData()
    const file = formData.get('file') as File

    if (!file || file.type !== 'application/pdf') {
      return NextResponse.json(
        { error: 'Invalid file type. Please provide a PDF file.' },
        { status: 400 }
      )
    }

    // Convert file to ArrayBuffer
    const arrayBuffer = await file.arrayBuffer()

    let pdfText = ''

    try {
      // Extract text using PDF.js
      pdfText = await extractTextFromPDF(arrayBuffer)
    } catch (error) {
      console.error('Failed to extract text from PDF:', error)

      // If text extraction fails, we could try OCR or other methods
      return NextResponse.json(
        {
          error: 'Could not extract text from PDF',
          details: 'The PDF might be image-based or corrupted. Please try uploading a text-based PDF or enter your data manually.'
        },
        { status: 400 }
      )
    }

    // Check if we extracted any meaningful text
    if (!pdfText || pdfText.trim().length < 50) {
      return NextResponse.json(
        {
          error: 'No text found in PDF',
          details: 'The PDF appears to be empty or image-based. Please upload a text-based PDF.'
        },
        { status: 400 }
      )
    }

    console.log('Extracted text length:', pdfText.length)
    console.log('Text preview:', pdfText.substring(0, 200) + '...')

    // Use OpenAI to extract body composition data with strict instructions
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: `You are a medical data extraction assistant. Your task is to extract ONLY the actual data present in body composition reports.

          CRITICAL RULES:
          1. ONLY extract data that is explicitly written in the document
          2. DO NOT make up or estimate any values
          3. DO NOT fill in missing data
          4. If you cannot find a specific measurement, omit it entirely
          
          Return data in this format:
          {
            "scans": [
              {
                "date": "YYYY-MM-DD",
                "weight": number,
                "weight_unit": "kg" or "lbs",
                "body_fat_percentage": number,
                "muscle_mass": number,
                "bone_mass": number,
                "source": "DEXA Scan" or "InBody" or "Other"
              }
            ],
            "total_scans": number,
            "extraction_confidence": "high" | "medium" | "low"
          }`
        },
        {
          role: "user",
          content: pdfText
        }
      ],
      response_format: { type: "json_object" },
      temperature: 0.1,
    })

    const extractedData = JSON.parse(completion.choices[0].message.content || '{}')

    return NextResponse.json({
      success: true,
      data: extractedData,
      filename: file.name,
      textLength: pdfText.length
    })

  } catch (error) {
    console.error('Error parsing PDF:', error)

    return NextResponse.json(
      {
        error: 'Failed to parse PDF',
        details: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    )
  }
}
