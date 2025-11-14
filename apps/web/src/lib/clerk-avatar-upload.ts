/**
 * Clerk Avatar Upload Utility
 * Handles profile picture uploads to Clerk, matching iOS implementation
 */

export interface UploadProfileImageOptions {
  maxWidth?: number
  maxHeight?: number
  quality?: number
}

const DEFAULT_OPTIONS: Required<UploadProfileImageOptions> = {
  maxWidth: 1000,
  maxHeight: 1000,
  quality: 0.8, // 80% quality to match iOS
}

/**
 * Resize and compress an image file to match iOS implementation
 * @param file - The image file to process
 * @param options - Resize and compression options
 * @returns Promise resolving to the processed image as a Blob
 */
export async function processImageFile(
  file: File,
  options: UploadProfileImageOptions = {}
): Promise<Blob> {
  const opts = { ...DEFAULT_OPTIONS, ...options }

  return new Promise((resolve, reject) => {
    const img = new Image()
    const reader = new FileReader()

    reader.onload = (e) => {
      img.src = e.target?.result as string
    }

    img.onload = () => {
      // Calculate new dimensions while maintaining aspect ratio
      let { width, height } = img

      if (width > opts.maxWidth || height > opts.maxHeight) {
        const aspectRatio = width / height

        if (width > height) {
          width = opts.maxWidth
          height = width / aspectRatio
        } else {
          height = opts.maxHeight
          width = height * aspectRatio
        }
      }

      // Create canvas and draw resized image
      const canvas = document.createElement('canvas')
      canvas.width = width
      canvas.height = height
      const ctx = canvas.getContext('2d')

      if (!ctx) {
        reject(new Error('Failed to get canvas context'))
        return
      }

      ctx.drawImage(img, 0, 0, width, height)

      // Convert to blob with compression
      canvas.toBlob(
        (blob) => {
          if (blob) {
            resolve(blob)
          } else {
            reject(new Error('Failed to create blob from canvas'))
          }
        },
        'image/jpeg',
        opts.quality
      )
    }

    img.onerror = () => {
      reject(new Error('Failed to load image'))
    }

    reader.onerror = () => {
      reject(new Error('Failed to read file'))
    }

    reader.readAsDataURL(file)
  })
}

/**
 * Validate image file type and size
 * @param file - The file to validate
 * @param maxSizeMB - Maximum file size in megabytes (default: 10MB)
 */
export function validateImageFile(file: File, maxSizeMB: number = 10): { valid: boolean; error?: string } {
  // Check file type
  const validTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp']
  if (!validTypes.includes(file.type)) {
    return {
      valid: false,
      error: 'Invalid file type. Please upload a JPEG, PNG, GIF, or WebP image.',
    }
  }

  // Check file size
  const maxSizeBytes = maxSizeMB * 1024 * 1024
  if (file.size > maxSizeBytes) {
    return {
      valid: false,
      error: `File size exceeds ${maxSizeMB}MB limit.`,
    }
  }

  return { valid: true }
}
