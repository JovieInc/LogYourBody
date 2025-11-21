/**
 * Enhanced photo upload utilities with compression, optimization, and error handling
 */

interface CompressOptions {
  maxWidth?: number
  maxHeight?: number
  quality?: number
  format?: 'webp' | 'jpeg' | 'png'
}

// interface UploadResult { // Not currently used
//   success: boolean
//   publicUrl?: string
//   thumbnailUrl?: string
//   error?: string
//   details?: any
// }

/**
 * Compresses an image file before upload
 */
export async function compressImage(
  file: File,
  options: CompressOptions = {}
): Promise<Blob> {
  const {
    maxWidth = 1920,
    maxHeight = 1920,
    quality = 0.85,
    format = 'jpeg'
  } = options

  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    
    reader.onload = (e) => {
      const img = new Image()
      
      img.onload = () => {
        const canvas = document.createElement('canvas')
        let width = img.width
        let height = img.height

        // Calculate new dimensions while maintaining aspect ratio
        if (width > maxWidth || height > maxHeight) {
          const aspectRatio = width / height
          
          if (width > height) {
            width = maxWidth
            height = width / aspectRatio
          } else {
            height = maxHeight
            width = height * aspectRatio
          }
        }

        canvas.width = width
        canvas.height = height

        const ctx = canvas.getContext('2d')
        if (!ctx) {
          reject(new Error('Failed to get canvas context'))
          return
        }

        // Use better image smoothing
        ctx.imageSmoothingEnabled = true
        ctx.imageSmoothingQuality = 'high'
        
        // Draw the image
        ctx.drawImage(img, 0, 0, width, height)

        // Convert to blob
        canvas.toBlob(
          (blob) => {
            if (blob) {
              resolve(blob)
            } else {
              reject(new Error('Failed to compress image'))
            }
          },
          `image/${format}`,
          quality
        )
      }

      img.onerror = () => {
        reject(new Error('Failed to load image'))
      }

      img.src = e.target?.result as string
    }

    reader.onerror = () => {
      reject(new Error('Failed to read file'))
    }

    reader.readAsDataURL(file)
  })
}

/**
 * Creates a thumbnail version of an image
 */
export async function createThumbnail(
  file: File | Blob,
  maxSize: number = 300
): Promise<Blob> {
  return compressImage(file as File, {
    maxWidth: maxSize,
    maxHeight: maxSize,
    quality: 0.7,
    format: 'jpeg'
  })
}

/**
 * Validates image file before upload
 */
export function validateImageFile(file: File): { valid: boolean; error?: string } {
  const validTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
  const maxSize = 10 * 1024 * 1024 // 10MB

  if (!validTypes.includes(file.type)) {
    return {
      valid: false,
      error: 'Invalid file type. Please upload a JPG, PNG, or WebP image.'
    }
  }

  if (file.size > maxSize) {
    return {
      valid: false,
      error: `File too large. Maximum size is ${maxSize / 1024 / 1024}MB.`
    }
  }

  return { valid: true }
}

/**
 * Extracts EXIF data from image (if available)
 */
export async function extractImageMetadata(file: File): Promise<{
  width?: number
  height?: number
  orientation?: number
  dateTaken?: Date
}> {
  return new Promise((resolve) => {
    const img = new Image()
    const url = URL.createObjectURL(file)

    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve({
        width: img.naturalWidth,
        height: img.naturalHeight
      })
    }

    img.onerror = () => {
      URL.revokeObjectURL(url)
      resolve({})
    }

    img.src = url
  })
}

/**
 * Generates a unique filename for photo upload
 */
export function generatePhotoFilename(userId: string, type: 'progress' | 'thumbnail' = 'progress'): string {
  const timestamp = Date.now()
  const randomString = Math.random().toString(36).substring(2, 8)
  return `${userId}/${type}/${timestamp}-${randomString}.jpg`
}

/**
 * Handles upload errors with user-friendly messages
 */
export function getUploadErrorMessage(error: unknown): string {
  if (!error) return 'An unknown error occurred'

  // Network errors
  if (error instanceof Error && (error.message.includes('Failed to fetch') || error.message.includes('NetworkError'))) {
    return 'Network error. Please check your connection and try again.'
  }

  // Storage quota errors
  if (error instanceof Error && (error.message.includes('storage') || error.message.includes('quota'))) {
    return 'Storage limit reached. Please try again later.'
  }

  // Permission errors
  if (error instanceof Error && (error.message.includes('permission') || error.message.includes('unauthorized'))) {
    return 'You do not have permission to upload photos. Please log in again.'
  }

  // File size errors
  if (error instanceof Error && (error.message.includes('payload too large') || error.message.includes('size'))) {
    return 'File too large. Please use a smaller image.'
  }

  // Rate limiting
  if ((error instanceof Error && error.message.includes('rate limit')) || (typeof error === 'object' && error !== null && 'statusCode' in error && error.statusCode === 429)) {
    return 'Too many uploads. Please wait a moment and try again.'
  }

  // Default error with details
  return error instanceof Error ? error.message : 'Failed to upload photo. Please try again.'
}

/**
 * Retries an upload operation with exponential backoff
 */
export async function retryUpload<T>(
  operation: () => Promise<T>,
  maxRetries: number = 3,
  initialDelay: number = 1000
): Promise<T> {
  let lastError: unknown

  for (let i = 0; i < maxRetries; i++) {
    try {
      return await operation()
    } catch (error) {
      lastError = error
      
      // Don't retry on client errors
      if (error && typeof error === 'object' && 'statusCode' in error) {
        const statusCodeProp = (error as { statusCode?: number }).statusCode
        const statusCode = typeof statusCodeProp === 'number' ? statusCodeProp : undefined
        if (statusCode >= 400 && statusCode < 500 && statusCode !== 429) {
          throw error
        }
      }

      // Wait before retrying (exponential backoff)
      if (i < maxRetries - 1) {
        const delay = initialDelay * Math.pow(2, i)
        await new Promise(resolve => setTimeout(resolve, delay))
      }
    }
  }

  throw lastError
}

/**
 * Checks if browser supports required features
 */
export function checkBrowserSupport(): {
  supported: boolean
  missingFeatures: string[]
} {
  const missingFeatures: string[] = []

  if (!window.FileReader) {
    missingFeatures.push('FileReader API')
  }

  if (!window.Blob) {
    missingFeatures.push('Blob API')
  }

  if (!document.createElement('canvas').getContext) {
    missingFeatures.push('Canvas API')
  }

  if (typeof URL.createObjectURL !== 'function') {
    missingFeatures.push('URL.createObjectURL')
  }

  return {
    supported: missingFeatures.length === 0,
    missingFeatures
  }
}
