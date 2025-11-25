import { serve } from "https://deno.land/std@0.210.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4"

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders })
    }

    try {
        const authHeader = req.headers.get("Authorization")

        if (!authHeader || !authHeader.startsWith("Bearer ")) {
            return new Response(
                JSON.stringify({ error: "Missing or invalid authorization header" }),
                { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            )
        }

        const token = authHeader.replace("Bearer ", "")

        const supabaseUrl = Deno.env.get("SUPABASE_URL")
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

        if (!supabaseUrl || !supabaseServiceKey) {
            console.error("Missing Supabase service configuration for delete-user-assets")
            return new Response(
                JSON.stringify({ error: "Server configuration error" }),
                { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            )
        }

        const supabase = createClient(supabaseUrl, supabaseServiceKey)

        // Verify JWT and get user
        const {
            data: { user },
            error: authError,
        } = await supabase.auth.getUser(token)

        if (authError || !user) {
            return new Response(
                JSON.stringify({ error: "Invalid token" }),
                { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            )
        }

        const userId = user.id as string

        // Collect all photo-related URLs for this user
        const [bodyMetricsResult, progressPhotosResult] = await Promise.all([
            supabase
                .from("body_metrics")
                .select("photo_url, original_photo_url")
                .eq("user_id", userId),
            supabase
                .from("progress_photos")
                .select("photo_url, thumbnail_url")
                .eq("user_id", userId),
        ])

        const bodyMetrics = (bodyMetricsResult.data || []) as {
            photo_url: string | null
            original_photo_url: string | null
        }[]

        const progressPhotos = (progressPhotosResult.data || []) as {
            photo_url: string | null
            thumbnail_url: string | null
        }[]

        const storagePaths = new Set<string>()
        const cloudinaryPublicIds = new Set<string>()

        function addStoragePathFromUrl(url: string | null) {
            if (!url) return

            // If it's already a bare path, accept as-is
            if (!url.startsWith("http")) {
                storagePaths.add(url)
                return
            }

            const patterns = [
                "/storage/v1/object/public/photos/",
                "/storage/v1/object/photos/",
            ]

            for (const pattern of patterns) {
                const index = url.indexOf(pattern)
                if (index !== -1) {
                    const path = url.substring(index + pattern.length)
                    if (path) {
                        storagePaths.add(path)
                    }
                    return
                }
            }
        }

        function addCloudinaryPublicIdFromUrl(url: string | null) {
            if (!url) return
            if (!url.includes("res.cloudinary.com") || !url.includes("/upload/")) return

            try {
                const uploadIndex = url.indexOf("/upload/")
                if (uploadIndex === -1) return

                let path = url.substring(uploadIndex + "/upload/".length)
                // path might look like: v1234567890/progress-photos/metricsId_timestamp.webp
                const segments = path.split("/").filter((segment) => segment.length > 0)

                if (segments.length === 0) return

                // Strip leading version segment like v1234567890 if present
                const first = segments[0]
                if (first.startsWith("v") && /^v\d+$/.test(first)) {
                    segments.shift()
                }

                if (segments.length === 0) return

                path = segments.join("/")

                // Remove file extension
                const dotIndex = path.lastIndexOf(".")
                if (dotIndex !== -1) {
                    path = path.substring(0, dotIndex)
                }

                // Extra safety: only delete resources in the expected folder
                if (!path.startsWith("progress-photos/")) return

                cloudinaryPublicIds.add(path)
            } catch (error) {
                console.error("Failed to parse Cloudinary URL for deletion", { url, error })
            }
        }

        for (const row of bodyMetrics) {
            addStoragePathFromUrl(row.original_photo_url)
            addStoragePathFromUrl(row.photo_url)
            addCloudinaryPublicIdFromUrl(row.photo_url)
        }

        for (const row of progressPhotos) {
            addStoragePathFromUrl(row.photo_url)
            addStoragePathFromUrl(row.thumbnail_url)
            addCloudinaryPublicIdFromUrl(row.photo_url)
            addCloudinaryPublicIdFromUrl(row.thumbnail_url)
        }

        // Delete Supabase storage objects (best-effort)
        if (storagePaths.size > 0) {
            const paths = Array.from(storagePaths)
            const { error: storageError } = await supabase.storage.from("photos").remove(paths)
            if (storageError) {
                console.error("Error deleting Supabase storage objects for user", { userId, error: storageError })
            }
        }

        // Delete Cloudinary resources (best-effort)
        const CLOUDINARY_CLOUD_NAME = Deno.env.get("CLOUDINARY_CLOUD_NAME")
        const CLOUDINARY_API_KEY = Deno.env.get("CLOUDINARY_API_KEY")
        const CLOUDINARY_API_SECRET = Deno.env.get("CLOUDINARY_API_SECRET")

        if (cloudinaryPublicIds.size > 0 && CLOUDINARY_CLOUD_NAME && CLOUDINARY_API_KEY && CLOUDINARY_API_SECRET) {
            const publicIds = Array.from(cloudinaryPublicIds)

            try {
                const authHeader =
                    "Basic " + btoa(`${CLOUDINARY_API_KEY}:${CLOUDINARY_API_SECRET}`)

                const body = new URLSearchParams()
                for (const id of publicIds) {
                    body.append("public_ids[]", id)
                }

                const response = await fetch(
                    `https://api.cloudinary.com/v1_1/${CLOUDINARY_CLOUD_NAME}/resources/image/upload/delete_by_ids`,
                    {
                        method: "POST",
                        headers: {
                            Authorization: authHeader,
                            "Content-Type": "application/x-www-form-urlencoded",
                        },
                        body,
                    },
                )

                if (!response.ok) {
                    const text = await response.text()
                    console.error("Cloudinary delete_by_ids failed", { status: response.status, body: text })
                }
            } catch (error) {
                console.error("Error deleting Cloudinary resources for user", { userId, error })
            }
        }

        return new Response(
            JSON.stringify({ success: true }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
    } catch (error) {
        console.error("delete-user-assets error", error)
        return new Response(
            JSON.stringify({ error: "Internal server error" }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
    }
})
