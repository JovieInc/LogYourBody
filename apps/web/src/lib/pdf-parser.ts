// Server-side PDF parsing utility
import { Buffer } from 'buffer'

export async function parsePDFServer(buffer: Buffer): Promise<string> {
  try {
    // Dynamically import pdf-parse only on server
    if (typeof window === 'undefined') {
      const pdfParseModule = await import('pdf-parse')
      const pdfParse = pdfParseModule.default || pdfParseModule
      const data = await pdfParse(buffer)
      return data.text
    }
    throw new Error('PDF parsing is only available on server')
  } catch (error) {
    console.error('Error in parsePDFServer:', error)
    throw error
  }
}

// Alternative method using pdf.js
export async function parsePDFWithPdfJs(arrayBuffer: ArrayBuffer): Promise<string> {
  try {
    // Import PDF.js dynamically
    const pdfjsLib = await import('pdfjs-dist')
    
    // Set worker
    pdfjsLib.GlobalWorkerOptions.workerSrc = `//cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version}/pdf.worker.min.js`
    
    const loadingTask = pdfjsLib.getDocument({ data: arrayBuffer })
    const pdf = await loadingTask.promise
    
    let fullText = ''
    
    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i)
      const textContent = await page.getTextContent()
      const pageText = textContent.items
        .filter((item): item is { str: string } => typeof (item as { str?: unknown }).str === 'string')
        .map((item) => item.str)
        .join(' ')
      fullText += pageText + '\n'
    }
    
    return fullText
  } catch (error) {
    console.error('Error parsing with PDF.js:', error)
    throw error
  }
}
