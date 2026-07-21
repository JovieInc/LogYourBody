import { serve } from "https://deno.land/std@0.210.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4"
import { createHash } from "https://deno.land/std@0.210.0/hash/mod.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

interface ExportRequest {
  format?: 'json' | 'csv'
  emailLink?: boolean
}

interface UserData {
  profile: any
  bodyMetrics: any[]
  progressPhotos: any[]
  goals: any[]
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    // Get JWT from Authorization header
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "No authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // Create Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Verify JWT and get user
    const token = authHeader.replace("Bearer ", "")
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)
    
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const body: ExportRequest = await req.json().catch(() => ({ format: 'json', emailLink: true }))
    const format = body.format || 'json'
    const emailLink = body.emailLink ?? true

    // Fetch all user data
    const userData = await fetchUserData(supabase, user.id)

    if (emailLink) {
      // Generate secure download token
      const downloadToken = await generateDownloadToken(user.id)
      
      // Store export data temporarily (24 hour TTL)
      const { error: storeError } = await supabase
        .from('data_exports')
        .insert({
          id: downloadToken,
          user_id: user.id,
          data: userData,
          format: format,
          expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          created_at: new Date().toISOString()
        })

      if (storeError) {
        console.error('Error storing export:', storeError)
        throw new Error('Failed to create export')
      }

      // Send email with download link
      const downloadUrl = `${supabaseUrl}/functions/v1/download-export?token=${downloadToken}`
      await sendExportEmail(supabase, user.email!, downloadUrl)

      return new Response(
        JSON.stringify({ 
          success: true,
          message: "Export link has been sent to your email. The link will expire in 24 hours."
        }),
        { 
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200 
        }
      )
    } else {
      // Direct download (for web app)
      const exportData = format === 'csv' 
        ? await convertToCSV(userData)
        : JSON.stringify(userData, null, 2)

      const filename = `logyourbody-export-${new Date().toISOString().split('T')[0]}.${format}`
      
      return new Response(exportData, {
        headers: {
          ...corsHeaders,
          "Content-Type": format === 'csv' ? "text/csv" : "application/json",
          "Content-Disposition": `attachment; filename="${filename}"`
        },
        status: 200
      })
    }
  } catch (error) {
    console.error('Export error:', error)
    return new Response(
      JSON.stringify({ error: error.message || "Internal server error" }),
      { 
        status: 500, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      }
    )
  }
})

async function fetchUserData(supabase: any, userId: string): Promise<UserData> {
  // Fetch profile
  const { data: profile } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single()

  // Fetch body metrics
  const { data: bodyMetrics } = await supabase
    .from('body_metrics')
    .select('*')
    .eq('user_id', userId)
    .order('date', { ascending: false })

  // Fetch progress photos
  const { data: progressPhotos } = await supabase
    .from('progress_photos')
    .select('*')
    .eq('user_id', userId)
    .order('taken_at', { ascending: false })

  // Note: no `goals` table exists (goals live as columns on profiles), so the
  // export payload keeps the historical empty array.
  return {
    profile: profile || {},
    bodyMetrics: bodyMetrics || [],
    progressPhotos: progressPhotos || [],
    goals: []
  }
}

async function generateDownloadToken(userId: string): Promise<string> {
  const timestamp = Date.now().toString()
  const random = Math.random().toString(36).substring(2, 15)
  const hash = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(`${userId}-${timestamp}-${random}`)
  )
  return btoa(String.fromCharCode(...new Uint8Array(hash)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
}

async function sendExportEmail(supabase: any, email: string, downloadUrl: string) {
  // Using Supabase's email service or your preferred email provider
  // For this example, we'll use a simple approach with Supabase edge function
  
  const emailHtml = `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #000; color: #fff; padding: 30px; text-align: center; }
        .content { padding: 30px; background: #f5f5f5; }
        .button { 
          display: inline-block; 
          padding: 12px 24px; 
          background: #000; 
          color: #fff; 
          text-decoration: none; 
          border-radius: 6px;
          margin: 20px 0;
        }
        .footer { padding: 20px; text-align: center; color: #666; font-size: 14px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Your LogYourBody Data Export</h1>
        </div>
        <div class="content">
          <p>Hello,</p>
          <p>You requested an export of your LogYourBody data. Your export is ready for download.</p>
          <p><a href="${downloadUrl}" class="button">Download Your Data</a></p>
          <p><strong>Important:</strong> This link will expire in 24 hours for security reasons.</p>
          <p>If you didn't request this export, please ignore this email or contact our support team.</p>
        </div>
        <div class="footer">
          <p>© 2025 LogYourBody. All rights reserved.</p>
          <p><a href="https://logyourbody.com/privacy">Privacy Policy</a> | <a href="https://logyourbody.com/support">Support</a></p>
        </div>
      </div>
    </body>
    </html>
  `

  // Send email using your preferred method
  // This is a placeholder - implement with your email service
  console.log(`Sending export email to ${email} with download URL: ${downloadUrl}`)
  
  // Option 1: Use Supabase Auth email service
  // Option 2: Use SendGrid, Resend, or other email API
  // Option 3: Use another edge function for email sending
}

async function convertToCSV(data: UserData): Promise<string> {
  const csvParts: string[] = []

  // Profile CSV
  if (data.profile) {
    csvParts.push("PROFILE DATA")
    csvParts.push(objectToCSV([data.profile]))
    csvParts.push("")
  }

  // Body Metrics CSV
  if (data.bodyMetrics.length > 0) {
    csvParts.push("BODY METRICS")
    csvParts.push(objectToCSV(data.bodyMetrics))
    csvParts.push("")
  }

  // Progress Photos CSV
  if (data.progressPhotos.length > 0) {
    csvParts.push("PROGRESS PHOTOS")
    csvParts.push(objectToCSV(data.progressPhotos))
    csvParts.push("")
  }

  // Goals CSV
  if (data.goals.length > 0) {
    csvParts.push("GOALS")
    csvParts.push(objectToCSV(data.goals))
  }

  return csvParts.join("\n")
}

function objectToCSV(data: any[]): string {
  if (data.length === 0) return ""
  
  const headers = Object.keys(data[0])
  const csvHeaders = headers.join(",")
  
  const csvRows = data.map(row => {
    return headers.map(header => {
      const value = row[header]
      if (value === null || value === undefined) return ""
      if (typeof value === "string" && value.includes(",")) {
        return `"${value.replace(/"/g, '""')}"`
      }
      return String(value)
    }).join(",")
  })

  return [csvHeaders, ...csvRows].join("\n")
}