declare module 'pdf-parse' {
  interface PDFInfo {
    PDFFormatVersion?: string
    IsAcroFormPresent?: boolean
    IsXFAPresent?: boolean
    Title?: string
    Author?: string
    Subject?: string
    Creator?: string
    Producer?: string
    CreationDate?: string
    ModDate?: string
  }

  interface PDFMetadata {
    _metadata?: unknown
    [key: string]: unknown
  }

  interface PDFData {
    numpages: number
    numrender: number
    info: PDFInfo
    metadata: PDFMetadata
    text: string
    version: string
  }

  function pdf(dataBuffer: Buffer | ArrayBuffer | Uint8Array, options?: Record<string, unknown>): Promise<PDFData>
  
  export = pdf
}
