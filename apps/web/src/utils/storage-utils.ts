import { createClient } from '@/lib/supabase/client'

/**
 * Ensures a Supabase storage URL uses the correct public format
 * @param url The URL to fix
 * @returns The corrected public URL
 */
export function ensurePublicUrl(url: string): string {
  if (!url) return url

  if (!url.includes('/storage/v1/object/')) return url

  // If it's already a public URL, return as-is
  if (url.includes('/public/')) return url

  // Fix the URL to include /public/ in the path
  return url.replace('/storage/v1/object/', '/storage/v1/object/public/')
}

/**
 * Gets the public URL for a file in Supabase storage
 * @param bucketName The storage bucket name
 * @param filePath The file path within the bucket
 * @returns The public URL
 */
export function getStoragePublicUrl(bucketName: string, filePath: string): string {
  const supabase = createClient()
  const { data: { publicUrl } } = supabase.storage
    .from(bucketName)
    .getPublicUrl(filePath)

  return ensurePublicUrl(publicUrl)
}

/**
 * Uploads a file to Supabase storage and returns the public URL
 * @param bucketName The storage bucket name
 * @param filePath The file path to upload to
 * @param file The file or blob to upload
 * @param options Upload options
 * @returns Object with upload result and public URL
 */
export async function uploadToStorage(
  bucketName: string,
  filePath: string,
  file: File | Blob,
  options?: {
    contentType?: string
    upsert?: boolean
  }
) {
  const supabase = createClient()

  // Log upload attempt
  console.log('Attempting to upload file:', {
    bucketName,
    filePath,
    fileSize: file.size,
    fileType: file.type
  })

  const { data, error } = await supabase.storage
    .from(bucketName)
    .upload(filePath, file, {
      contentType: options?.contentType || file.type,
      upsert: options?.upsert || false
    })

  if (error) {
    console.error('Storage upload error:', {
      error,
      message: error.message,
      statusCode: 'statusCode' in error ? error.statusCode : undefined,
      bucketName,
      filePath
    })
    throw error
  }

  const publicUrl = getStoragePublicUrl(bucketName, filePath)
  console.log('Upload successful, public URL:', publicUrl)

  return {
    data,
    publicUrl,
    error: null
  }
}

/**
 * Deletes a file from Supabase storage
 * @param bucketName The storage bucket name
 * @param filePath The file path to delete
 */
export async function deleteFromStorage(bucketName: string, filePath: string) {
  const supabase = createClient()

  const { error } = await supabase.storage
    .from(bucketName)
    .remove([filePath])

  if (error) {
    throw error
  }

  return { error: null }
}

/**
 * Extracts the file path from a Supabase storage URL
 * @param url The storage URL
 * @param bucketName The bucket name
 * @returns The file path or null if invalid
 */
export function getFilePathFromUrl(url: string, bucketName: string): string | null {
  if (!url) return null

  // Pattern to match Supabase storage URLs
  const patterns = [
    `/storage/v1/object/public/${bucketName}/`,
    `/storage/v1/object/${bucketName}/`,
  ]

  for (const pattern of patterns) {
    const index = url.indexOf(pattern)
    if (index !== -1) {
      return url.substring(index + pattern.length)
    }
  }

  return null
}