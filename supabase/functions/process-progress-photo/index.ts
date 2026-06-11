import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RequestBody {
  storagePath: string
  metricsId: string
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    }
  )
}

function bearerToken(authHeader: string | null): string | null {
  const match = authHeader?.match(/^Bearer\s+(.+)$/i)
  const token = match?.[1]?.trim()
  return token || null
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed' }, 405)
    }

    const token = bearerToken(req.headers.get('Authorization'))
    if (!token) {
      return jsonResponse({ error: 'Missing or invalid authorization header' }, 401)
    }

    // Get Supabase credentials from environment
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error('Missing Supabase service configuration for process-progress-photo')
      return jsonResponse({ error: 'Server configuration error' }, 500)
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token)

    if (authError || !user) {
      return jsonResponse({ error: 'Invalid token' }, 401)
    }

    const body = await req.json().catch(() => null) as Partial<RequestBody> | null
    const storagePath = body?.storagePath
    const metricsId = body?.metricsId

    // Validate inputs
    if (typeof storagePath !== 'string' || typeof metricsId !== 'string' || !storagePath || !metricsId) {
      return jsonResponse({ error: 'Missing required parameters' }, 400)
    }

    const normalizedStoragePath = storagePath.replace(/^\/+/, '')
    if (
      normalizedStoragePath !== storagePath ||
      normalizedStoragePath.includes('..') ||
      !normalizedStoragePath.startsWith(`${user.id}/`)
    ) {
      return jsonResponse({ error: 'Photo path does not belong to the authenticated user' }, 403)
    }

    const { data: metric, error: metricError } = await supabase
      .from('body_metrics')
      .select('id, user_id')
      .eq('id', metricsId)
      .maybeSingle()

    if (metricError) {
      console.error('Failed to load body_metrics owner:', metricError)
      return jsonResponse({ error: 'Failed to verify metrics ownership' }, 500)
    }

    if (!metric) {
      return jsonResponse({ error: 'Metrics record not found' }, 404)
    }

    if (metric.user_id !== user.id) {
      return jsonResponse({ error: 'Metrics record does not belong to the authenticated user' }, 403)
    }

    // Get Cloudinary credentials from environment
    const CLOUDINARY_CLOUD_NAME = Deno.env.get('CLOUDINARY_CLOUD_NAME')
    const CLOUDINARY_API_KEY = Deno.env.get('CLOUDINARY_API_KEY')
    const CLOUDINARY_API_SECRET = Deno.env.get('CLOUDINARY_API_SECRET')

    if (!CLOUDINARY_CLOUD_NAME || !CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
      throw new Error('Cloudinary credentials not configured')
    }

    // Build Cloudinary transformation URL
    // PNG with transparency already has background removed on device
    // Now we optimize with Cloudinary:
    // 1. Content-aware cropping to frame the person consistently
    // 2. Auto color and lighting adjustments for consistency
    // 3. Optimize size and convert to WebP with alpha channel
    const transformations = [
      'a_auto_right',         // Auto-rotate based on EXIF orientation
      'c_pad',                // Pad mode to ensure full body is visible
      'g_auto:subject',       // Content-aware gravity to focus on the person
      'w_600',                // Width
      'h_800',                // Height
      'b_rgb:000000',        // Black background for padding areas
      'e_auto_brightness',    // Auto brightness adjustment
      'e_auto_contrast',      // Auto contrast adjustment
      'e_auto_color',         // Auto color adjustment
      'fl_preserve_transparency', // Keep alpha channel
      'q_auto:best',          // Best auto quality
      'f_webp',               // WebP format with alpha support
      'fl_lossy',             // Allow lossy compression for smaller size
      // Additional transformations for consistent body framing
      'z_0.85'                // Zoom out slightly to ensure full body is captured
    ].join(',')

    // Resolve the original Supabase Storage URL from the storage path
    const originalUrl = `${supabaseUrl}/storage/v1/object/public/photos/${normalizedStoragePath}`

    // Create Cloudinary upload URL
    const timestamp = Math.round(Date.now() / 1000)
    const publicId = `progress-photos/${metricsId}_${timestamp}`

    // Parameters that need to be included in the signature (in alphabetical order)
    const params: Record<string, string | number> = {
      eager: transformations,
      eager_async: 'false',
      invalidate: 'true',
      public_id: publicId,
      timestamp: timestamp,
      transformation: transformations
    }

    // Generate signature - all parameters except api_key, file, and resource_type
    const sortedParams = Object.keys(params).sort()
    const stringToSign = sortedParams
      .map(key => `${key}=${params[key]}`)
      .join('&') + CLOUDINARY_API_SECRET

    const encoder = new TextEncoder()
    const data = encoder.encode(stringToSign)
    const hashBuffer = await crypto.subtle.digest('SHA-256', data)
    const hashArray = Array.from(new Uint8Array(hashBuffer))
    const signature = hashArray.map(b => b.toString(16).padStart(2, '0')).join('')

    // Create a signed URL for the original photo in Supabase Storage
    const { data: signedData, error: signedError } = await supabase
      .storage
      .from('photos')
      .createSignedUrl(normalizedStoragePath, 60 * 10)

    if (signedError || !signedData || !signedData.signedUrl) {
      throw new Error('Failed to create signed URL for original photo')
    }

    let cloudinarySourceUrl = signedData.signedUrl as string
    if (!cloudinarySourceUrl.startsWith('http')) {
      const base = supabaseUrl.endsWith('/')
        ? supabaseUrl.slice(0, -1)
        : supabaseUrl
      const path = cloudinarySourceUrl.startsWith('/')
        ? cloudinarySourceUrl
        : `/${cloudinarySourceUrl}`
      cloudinarySourceUrl = `${base}${path}`
    }

    // Upload to Cloudinary using the signed Supabase URL
    const formData = new FormData()
    formData.append('file', cloudinarySourceUrl)
    formData.append('public_id', publicId)
    formData.append('api_key', CLOUDINARY_API_KEY)
    formData.append('timestamp', timestamp.toString())
    formData.append('signature', signature)
    formData.append('transformation', transformations)
    formData.append('eager', transformations) // Apply transformations during upload
    formData.append('eager_async', 'false')
    formData.append('invalidate', 'true')

    const uploadResponse = await fetch(
      `https://api.cloudinary.com/v1_1/${CLOUDINARY_CLOUD_NAME}/image/upload`,
      {
        method: 'POST',
        body: formData
      }
    )

    if (!uploadResponse.ok) {
      const error = await uploadResponse.text()
      throw new Error(`Cloudinary upload failed: ${error}`)
    }

    const uploadResult = await uploadResponse.json()

    // Get the transformed URL
    const processedUrl = uploadResult.eager?.[0]?.secure_url || uploadResult.secure_url

    // Update the body_metrics record with the processed URL and storage path
    const { data: updatedMetric, error: updateError } = await supabase
      .from('body_metrics')
      .update({
        photo_url: processedUrl,
        original_photo_url: normalizedStoragePath,
        photo_processed_at: new Date().toISOString()
      })
      .eq('id', metricsId)
      .eq('user_id', user.id)
      .select('id')
      .maybeSingle()

    if (updateError) {
      console.error('Failed to update body_metrics:', updateError)
      return jsonResponse({ error: 'Failed to update metrics photo' }, 500)
    }

    if (!updatedMetric) {
      return jsonResponse({ error: 'Metrics record does not belong to the authenticated user' }, 403)
    }

    return new Response(
      JSON.stringify({
        processedUrl,
        publicId,
        originalUrl
      }),
      {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      }
    )

  } catch (error) {
    console.error('Error processing image:', error)
    const message = error instanceof Error ? error.message : 'Internal server error'
    return jsonResponse({ error: message }, 500)
  }
})
