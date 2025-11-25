import { createClient } from '@/lib/supabase/client'
import { deleteFromStorage, getFilePathFromUrl } from './storage-utils'

export interface PhotoData {
  id: string
  user_id: string
  date: string
  photo_url: string
  original_photo_url?: string | null
  weight?: number
  weight_unit?: string
  body_fat_percentage?: number
  notes?: string
  created_at: string
}

export interface PhotoUploadResult {
  success: boolean
  data?: PhotoData
  error?: string
}

function isSupabasePhotosUrl(url: string | null | undefined): boolean {
  if (!url) return false
  return url.includes('/storage/v1/object') && url.includes('/photos/')
}

async function getSignedPhotoUrlIfNeeded(
  supabase: ReturnType<typeof createClient>,
  url: string | null,
): Promise<string | null> {
  if (!url) return url
  if (!isSupabasePhotosUrl(url)) {
    return url
  }

  const path = getFilePathFromUrl(url, 'photos')
  if (!path) {
    return url
  }

  const { data: signedData, error: signedError } = await supabase
    .storage
    .from('photos')
    .createSignedUrl(path, 60 * 10)

  if (signedError || !signedData || !signedData.signedUrl) {
    console.error('Failed to create signed URL for photo', signedError)
    return url
  }

  let signedUrl = signedData.signedUrl as string

  if (!signedUrl.startsWith('http')) {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    if (supabaseUrl) {
      const base = supabaseUrl.endsWith('/')
        ? supabaseUrl.slice(0, -1)
        : supabaseUrl
      const pathPart = signedUrl.startsWith('/')
        ? signedUrl
        : `/${signedUrl}`
      signedUrl = `${base}${pathPart}`
    }
  }

  return signedUrl
}

/**
 * Loads all photos for the current user from body_metrics
 * @returns Array of photo data
 */
export async function loadUserPhotos(): Promise<PhotoData[]> {
  const supabase = createClient()

  const { data, error } = await supabase
    .from('body_metrics')
    .select('id, user_id, date, photo_url, original_photo_url, weight, weight_unit, body_fat_percentage, notes, created_at')
    .not('photo_url', 'is', null)
    .order('date', { ascending: false })

  if (error) {
    console.error('Error loading photos:', error)
    throw error
  }

  const rows = data || []

  const photosWithUrls = await Promise.all(
    rows.map(async (photo) => {
      const signedUrl = await getSignedPhotoUrlIfNeeded(supabase, photo.photo_url)
      return {
        ...photo,
        photo_url: signedUrl ?? photo.photo_url,
      }
    }),
  )

  return photosWithUrls
}

/**
 * Loads a single photo by ID
 * @param photoId The photo ID
 * @returns Photo data or null
 */
export async function loadPhoto(photoId: string): Promise<PhotoData | null> {
  const supabase = createClient()

  const { data, error } = await supabase
    .from('body_metrics')
    .select('id, user_id, date, photo_url, original_photo_url, weight, weight_unit, body_fat_percentage, notes, created_at')
    .eq('id', photoId)
    .single()

  if (error) {
    console.error('Error loading photo:', error)
    return null
  }

  if (!data) {
    return null
  }

  const signedUrl = await getSignedPhotoUrlIfNeeded(supabase, data.photo_url)

  return {
    ...data,
    photo_url: signedUrl ?? data.photo_url,
  }
}

/**
 * Deletes a photo from body_metrics and storage
 * @param photoId The photo ID to delete
 */
export async function deletePhoto(photoId: string): Promise<void> {
  const supabase = createClient()

  try {
    // First, get the photo to extract the storage path
    const photo = await loadPhoto(photoId)
    if (!photo) {
      throw new Error('Photo not found')
    }

    // Prefer original_photo_url (storage path) when deleting from storage
    const storageSource = photo.original_photo_url
    let filePath: string | null = null

    if (storageSource) {
      if (isSupabasePhotosUrl(storageSource)) {
        filePath = getFilePathFromUrl(storageSource, 'photos')
      } else {
        // Assume this is already a bucket-relative path
        filePath = storageSource
      }
    }

    // Delete from storage bucket first
    if (filePath) {
      try {
        await deleteFromStorage('photos', filePath)
      } catch (storageError) {
        console.error('Error deleting from storage:', storageError)
        // Continue with database deletion even if storage fails
      }
    }

    // Delete from body_metrics (this will set photo_url to null or delete the record)
    const { error } = await supabase
      .from('body_metrics')
      .update({ photo_url: null })
      .eq('id', photoId)

    if (error) {
      console.error('Error deleting photo from database:', error)
      throw error
    }
  } catch (error) {
    console.error('Error in deletePhoto:', error)
    throw error
  }
}

/**
 * Uploads a photo with a body metrics entry
 */
export async function uploadPhotoWithMetrics(
  file: File,
  userId: string,
  data?: {
    weight?: number
    weight_unit?: string
    body_fat_percentage?: number
    notes?: string
    date?: string
  }
): Promise<PhotoUploadResult> {
  const supabase = createClient()

  try {
    // 1) Create body metrics entry (without photo_url)
    const { data: metricsData, error: metricsError } = await supabase
      .from('body_metrics')
      .insert({
        user_id: userId,
        date: data?.date || new Date().toISOString().split('T')[0],
        weight: data?.weight,
        weight_unit: data?.weight_unit,
        body_fat_percentage: data?.body_fat_percentage,
        notes: data?.notes || 'Progress photo'
      })
      .select()
      .single()

    if (metricsError || !metricsData) {
      throw metricsError || new Error('Failed to create metrics entry')
    }

    const metricsId = metricsData.id as string

    // 2) Upload original photo to Supabase Storage
    const fileName = `${userId}/${metricsId}-${Date.now()}-progress.jpg`
    const { error: uploadError } = await supabase.storage
      .from('photos')
      .upload(fileName, file, {
        contentType: file.type,
        upsert: false
      })

    if (uploadError) {
      // Best-effort cleanup of the metrics row
      const { error: cleanupError } = await supabase
        .from('body_metrics')
        .delete()
        .eq('id', metricsId)
      if (cleanupError) {
        console.error('Failed to clean up body_metrics after upload error', cleanupError)
      }
      throw uploadError
    }

    // 3) Call edge function to process the photo with Cloudinary
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

    if (!supabaseUrl || !supabaseAnonKey) {
      throw new Error('Missing Supabase environment variables')
    }

    const response = await fetch(
      `${supabaseUrl}/functions/v1/process-progress-photo`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: supabaseAnonKey,
          Authorization: `Bearer ${supabaseAnonKey}`,
        },
        body: JSON.stringify({
          storagePath: fileName,
          metricsId,
        }),
      },
    )

    if (!response.ok) {
      const text = await response.text().catch(() => '')
      console.error('process-progress-photo failed', {
        status: response.status,
        body: text,
      })

      // Best-effort cleanup of storage and metrics row
      await deleteFromStorage('photos', fileName).catch(() => { })
      const { error: cleanupError } = await supabase
        .from('body_metrics')
        .delete()
        .eq('id', metricsId)
      if (cleanupError) {
        console.error('Failed to clean up body_metrics after processing error', cleanupError)
      }

      throw new Error('Photo processing failed')
    }

    const result = await response.json().catch(() => null) as { processedUrl?: string } | null
    const processedUrl = result?.processedUrl

    if (!processedUrl) {
      throw new Error('Missing processedUrl from process-progress-photo')
    }

    // Edge function updates body_metrics.photo_url; return processed URL for client display
    return {
      success: true,
      data: {
        ...metricsData,
        photo_url: processedUrl
      }
    }
  } catch (error) {
    console.error('Error uploading photo:', error)
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Failed to upload photo'
    }
  }
}