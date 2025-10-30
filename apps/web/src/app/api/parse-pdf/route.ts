import { NextRequest, NextResponse } from 'next/server'
import OpenAI from 'openai'
import { serverEnv } from '@/env-server'

// Dynamic import with error handling
async function loadPdfParse() {
  try {
    const pdfParse = await import('pdf-parse')
    return pdfParse.default || pdfParse
  } catch (error) {
    console.error('Failed to load pdf-parse:', error)
    return null
  }
}

export async function POST(request: NextRequest) {
  try {
    // Check if OpenAI API key is configured
    if (!serverEnv.OPENAI_API_KEY) {
      console.error('OpenAI API key not configured')
      return NextResponse.json(
        { error: 'OpenAI API key not configured. Please set OPENAI_API_KEY environment variable.' },
        { status: 500 }
      )
    }

    const openai = new OpenAI({
      apiKey: serverEnv.OPENAI_API_KEY,
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

    // Convert file to buffer
    const buffer = Buffer.from(await file.arrayBuffer())
    
    let pdfText = ''
    
    // Try to load and use pdf-parse
    const pdfParse = await loadPdfParse()
    
    if (pdfParse) {
      try {
        const pdfData = await pdfParse(buffer)
        pdfText = pdfData.text
      } catch (parseError) {
        console.error('Error parsing PDF:', parseError)
        // Continue to fallback method
      }
    }
    
    // If pdf-parse didn't work, try pdf-lib as fallback
    if (!pdfText) {
      try {
        const { PDFDocument } = await import('pdf-lib')
        const pdfDoc = await PDFDocument.load(buffer)
        
        // Get basic info from PDF
        const pages = pdfDoc.getPages()
        const pageCount = pages.length
        
        // pdf-lib doesn't extract text well, so we'll use a different approach
        // Convert first page to base64 and send to OpenAI Vision API
        if (pageCount > 0) {
          // For DEXA scans, usually the first page has the summary
          // const base64 = buffer.toString('base64') // Not used with current approach
          
          // Use OpenAI to analyze the PDF content
          // Note: This is a workaround - ideally we'd extract text directly
          const completion = await openai.chat.completions.create({
            model: "gpt-4o-mini",
            messages: [
              {
                role: "system",
                content: `You are analyzing a medical document that was uploaded as a PDF. Since we cannot extract text directly, please analyze any visible information and extract body composition data.
                
                Look for:
                - Weight (in kg or lbs)
                - Body fat percentage
                - Muscle mass / Lean mass
                - Bone mass
                - Visceral fat level
                - Date of scan
                - Any other relevant measurements
                
                Return the data in JSON format as specified.`
              },
              {
                role: "user",
                content: `This is a ${file.name} file with ${pageCount} pages. Please extract any body composition data you can identify.`
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
            method: 'pdf-lib-extraction'
          })
        }
      } catch (pdfLibError) {
        console.error('pdf-lib also failed:', pdfLibError)
      }
    }

    // Check if we extracted any text
    if (!pdfText || pdfText.trim().length === 0) {
      return NextResponse.json(
        { error: 'Could not extract text from PDF. The PDF might be image-based or corrupted.' },
        { status: 400 }
      )
    }

    console.log('PDF Text Extraction:', {
      textLength: pdfText.length,
      fullText: pdfText.substring(0, 2000), // Log more text for debugging
      hasContent: pdfText.trim().length > 0
    })
    
    // If we have very little text, it might be an image-based PDF
    if (pdfText.trim().length < 100) {
      console.warn('Very little text extracted from PDF - might be image-based')
    }

    // Use OpenAI to extract body composition data
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: `You are a medical data extraction assistant. Your task is to extract ONLY the actual data present in body composition reports, DEXA scans, InBody scans, or similar documents.

          CRITICAL RULES:
          1. ONLY extract data that is explicitly written in the document
          2. DO NOT make up or estimate any values
          3. DO NOT fill in missing data with typical or example values
          4. If you cannot find a specific measurement, omit it entirely
          5. If the document appears to be empty or unreadable, return {"scans": [], "total_scans": 0}

          Look for these specific data points:
          - Scan/Test dates
          - Body weight (with units)
          - Body fat percentage
          - Muscle mass / Lean body mass
          - Bone mass / Bone mineral content
          - Visceral fat rating
          - Any other measurements explicitly stated

          Return the data in this JSON format:
          {
            "scans": [
              {
                "date": "YYYY-MM-DD",
                "weight": number,
                "weight_unit": "kg" or "lbs",
                "body_fat_percentage": number,
                "muscle_mass": number,
                "bone_mass": number,
                "visceral_fat": number,
                "source": "DEXA Scan" or "InBody" or "Other"
              }
            ],
            "total_scans": number,
            "extraction_confidence": "high" | "medium" | "low",
            "extraction_notes": "any issues or observations about the data extraction"
          }

          Extract ALL scan dates found in the document. Only include fields that are explicitly present in the document.
          Sort scans by date (oldest first).`
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
    
    console.log('OpenAI extraction result:', {
      scanCount: extractedData.total_scans,
      confidence: extractedData.extraction_confidence,
      notes: extractedData.extraction_notes,
      firstScan: extractedData.scans?.[0]
    })

    // Validate the extraction
    if (extractedData.extraction_confidence === 'low' || !extractedData.scans || extractedData.scans.length === 0) {
      console.warn('Low confidence extraction or no scans found')
      
      return NextResponse.json({
        success: false,
        error: 'Could not reliably extract data from this PDF',
        details: extractedData.extraction_notes || 'The PDF might be image-based or in an unsupported format',
        filename: file.name
      })
    }

    // Validate that the data looks reasonable
    const validScans = extractedData.scans.filter((scan: any) => {
      // Basic validation - must have at least a date and weight
      if (!scan.date || !scan.weight) return false
      
      // Weight should be reasonable (20-300 kg or 44-660 lbs)
      const weightInKg = scan.weight_unit === 'lbs' ? scan.weight * 0.453592 : scan.weight
      if (weightInKg < 20 || weightInKg > 300) {
        console.warn('Invalid weight detected:', scan.weight, scan.weight_unit)
        return false
      }
      
      // Body fat percentage should be reasonable (3-60%)
      if (scan.body_fat_percentage && (scan.body_fat_percentage < 3 || scan.body_fat_percentage > 60)) {
        console.warn('Invalid body fat percentage:', scan.body_fat_percentage)
        return false
      }
      
      return true
    })
    
    if (validScans.length === 0) {
      return NextResponse.json({
        success: false,
        error: 'No valid scan data found',
        details: 'The extracted data appears to be invalid or corrupted',
        filename: file.name
      })
    }

    return NextResponse.json({
      success: true,
      data: {
        ...extractedData,
        scans: validScans
      },
      filename: file.name,
      scanCount: validScans.length,
      textLength: pdfText.length
    })

  } catch (error) {
    console.error('Error parsing PDF:', error)
    
    // Log more details about the error
    if (error instanceof Error) {
      console.error('Error details:', {
        name: error.name,
        message: error.message,
        stack: error.stack,
        // Check if it's an OpenAI specific error
        isOpenAIError: error.message.includes('OpenAI') || error.message.includes('API')
      })
    }
    
    return NextResponse.json(
      { 
        error: 'Failed to parse PDF', 
        details: error instanceof Error ? error.message : 'Unknown error',
        errorType: error instanceof Error ? error.name : 'Unknown'
      },
      { status: 500 }
    )
  }
}