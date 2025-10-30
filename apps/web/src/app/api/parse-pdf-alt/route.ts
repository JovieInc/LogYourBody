import { NextRequest, NextResponse } from 'next/server'
import OpenAI from 'openai'
import { serverEnv } from '@/env-server'

export async function POST(request: NextRequest) {
  try {
    // Check if OpenAI API key is configured
    if (!serverEnv.OPENAI_API_KEY) {
      return NextResponse.json(
        { error: 'OpenAI API key not configured' },
        { status: 500 }
      )
    }

    const _openai = new OpenAI({
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

    // For now, since pdf-parse isn't working, provide instructions to the user
    return NextResponse.json({
      success: false,
      error: 'PDF processing is temporarily unavailable',
      suggestion: 'Please take a screenshot of your DEXA scan results and upload it as an image instead, or enter your data manually.',
      manualEntryFields: {
        weight: 'Your weight in kg or lbs',
        bodyFatPercentage: 'Your body fat percentage',
        muscleMass: 'Your muscle mass (if available)',
        boneMass: 'Your bone mass (if available)',
        visceralFat: 'Your visceral fat level (if available)'
      }
    }, { status: 503 })

  } catch (error) {
    console.error('Error in parse-pdf-alt:', error)
    return NextResponse.json(
      { 
        error: 'Failed to process request',
        details: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    )
  }
}