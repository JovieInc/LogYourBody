import { serve } from "https://deno.land/std@0.210.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import {
  deleteLegacyUserDatabaseRows,
  deleteProductAuthUser,
  deleteUserDatabaseRows,
  ownedCloudinaryPublicIdFromUrl,
  ownedStoragePathFromValue,
} from "./account-deletion.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error(
        "Missing Supabase service configuration for delete-user-assets",
      );
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Current Jovie sessions terminate at LYB's first-party API. That server
    // calls this boundary with the Supabase service credential and an exact
    // already-authenticated subject. Legacy Supabase clients retain their
    // existing user-token path.
    let userId: string | null = null;
    let supabaseAuthUser = false;
    const serviceRequest = token === supabaseServiceKey;
    if (serviceRequest) {
      const input = await req.json().catch(() => null) as {
        userId?: unknown;
      } | null;
      if (typeof input?.userId === "string" && input.userId.trim().length > 0) {
        userId = input.userId;
      }
    } else {
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser(token);
      if (!authError && user) {
        userId = user.id;
        supabaseAuthUser = true;
      }
    }

    if (!userId) {
      return new Response(
        JSON.stringify({ error: "Invalid token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const ownerId = userId;

    // Collect all photo-related URLs for this user
    const [bodyMetricsResult, progressPhotosResult] = await Promise.all([
      supabase
        .from("body_metrics")
        .select("id, photo_url, original_photo_url")
        .eq("user_id", ownerId),
      supabase
        .from("progress_photos")
        .select("id, photo_url, thumbnail_url")
        .eq("user_id", ownerId),
    ]);

    const bodyMetrics = (bodyMetricsResult.data || []) as {
      id: string;
      photo_url: string | null;
      original_photo_url: string | null;
    }[];

    const progressPhotos = (progressPhotosResult.data || []) as {
      id: string;
      photo_url: string | null;
      thumbnail_url: string | null;
    }[];

    if (bodyMetricsResult.error) throw bodyMetricsResult.error;
    if (progressPhotosResult.error) throw progressPhotosResult.error;

    let legacyBodyMetrics: { id: string; photo_url: string | null }[] = [];
    let legacyProgressPhotos: {
      id: string;
      photo_url: string | null;
      thumbnail_url: string | null;
    }[] = [];
    if (supabaseAuthUser) {
      const [legacyBodyMetricsResult, legacyProgressPhotosResult] =
        await Promise.all([
          supabase
            .from("body_metrics_old")
            .select("id, photo_url")
            .eq("user_id", ownerId),
          supabase
            .from("progress_photos_old")
            .select("id, photo_url, thumbnail_url")
            .eq("user_id", ownerId),
        ]);
      if (legacyBodyMetricsResult.error) throw legacyBodyMetricsResult.error;
      if (legacyProgressPhotosResult.error) {
        throw legacyProgressPhotosResult.error;
      }
      legacyBodyMetrics = (legacyBodyMetricsResult.data || []) as {
        id: string;
        photo_url: string | null;
      }[];
      legacyProgressPhotos = (legacyProgressPhotosResult.data || []) as {
        id: string;
        photo_url: string | null;
        thumbnail_url: string | null;
      }[];
    }

    const storagePaths = new Set<string>();
    const cloudinaryPublicIds = new Set<string>();
    // Cloudinary upload IDs are derived from body_metrics.id. Progress-photo
    // row IDs are client-provided and cannot be used as ownership proof.
    const ownedMetricIds = new Set([
      ...bodyMetrics.map((row) => row.id),
      ...legacyBodyMetrics.map((row) => row.id),
    ]);

    function addStoragePathFromUrl(url: string | null) {
      const path = ownedStoragePathFromValue(url, ownerId);
      if (path) storagePaths.add(path);
    }

    function addCloudinaryPublicIdFromUrl(url: string | null) {
      const publicId = ownedCloudinaryPublicIdFromUrl(
        url,
        ownerId,
        ownedMetricIds,
      );
      if (publicId) cloudinaryPublicIds.add(publicId);
      if (url?.includes("res.cloudinary.com") && !publicId) {
        throw new Error(
          "Cloudinary asset ownership cannot be verified automatically; manual deletion is required",
        );
      }
    }

    for (const row of bodyMetrics) {
      addStoragePathFromUrl(row.original_photo_url);
      addStoragePathFromUrl(row.photo_url);
      addCloudinaryPublicIdFromUrl(row.photo_url);
    }

    for (const row of progressPhotos) {
      addStoragePathFromUrl(row.photo_url);
      addStoragePathFromUrl(row.thumbnail_url);
      addCloudinaryPublicIdFromUrl(row.photo_url);
      addCloudinaryPublicIdFromUrl(row.thumbnail_url);
    }

    for (const row of legacyBodyMetrics) {
      addStoragePathFromUrl(row.photo_url);
      addCloudinaryPublicIdFromUrl(row.photo_url);
    }

    for (const row of legacyProgressPhotos) {
      addStoragePathFromUrl(row.photo_url);
      addStoragePathFromUrl(row.thumbnail_url);
      addCloudinaryPublicIdFromUrl(row.photo_url);
      addCloudinaryPublicIdFromUrl(row.thumbnail_url);
    }

    // Uploads use the exact `<user id>/<filename>` prefix. Listing that
    // folder also catches committed originals whose database update was
    // interrupted after storage succeeded.
    let storageOffset = 0;
    const storagePageSize = 100;
    while (true) {
      const { data: objects, error: listError } = await supabase.storage
        .from("photos")
        .list(ownerId, {
          limit: storagePageSize,
          offset: storageOffset,
          sortBy: { column: "name", order: "asc" },
        });
      if (listError) throw listError;

      for (const object of objects || []) {
        const path = object.name
          ? ownedStoragePathFromValue(`${ownerId}/${object.name}`, ownerId)
          : null;
        if (path) storagePaths.add(path);
      }
      if (!objects || objects.length < storagePageSize) break;
      storageOffset += objects.length;
    }

    // Asset deletion is fail-closed: database URLs stay available for a
    // retry unless every referenced private object has been removed.
    if (storagePaths.size > 0) {
      const paths = Array.from(storagePaths);
      const { error: storageError } = await supabase.storage.from("photos")
        .remove(paths);
      if (storageError) {
        throw storageError;
      }
    }

    // Processed assets are removed through Cloudinary's authenticated API.
    const CLOUDINARY_CLOUD_NAME = Deno.env.get("CLOUDINARY_CLOUD_NAME");
    const CLOUDINARY_API_KEY = Deno.env.get("CLOUDINARY_API_KEY");
    const CLOUDINARY_API_SECRET = Deno.env.get("CLOUDINARY_API_SECRET");

    if (cloudinaryPublicIds.size > 0) {
      if (
        !CLOUDINARY_CLOUD_NAME || !CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET
      ) {
        throw new Error(
          "Cloudinary account-deletion service is not configured",
        );
      }
      const publicIds = Array.from(cloudinaryPublicIds);
      const deleteBatchSize = 100;
      for (let index = 0; index < publicIds.length; index += deleteBatchSize) {
        const authHeader = "Basic " +
          btoa(`${CLOUDINARY_API_KEY}:${CLOUDINARY_API_SECRET}`);

        const body = new URLSearchParams();
        for (const id of publicIds.slice(index, index + deleteBatchSize)) {
          body.append("public_ids[]", id);
        }
        body.append("invalidate", "true");

        const response = await fetch(
          `https://api.cloudinary.com/v1_1/${CLOUDINARY_CLOUD_NAME}/resources/image/upload`,
          {
            method: "DELETE",
            headers: {
              Authorization: authHeader,
              "Content-Type": "application/x-www-form-urlencoded",
            },
            body,
          },
        );

        const payload = await response.json().catch(() => null) as {
          deleted?: Record<string, string>;
          error?: { message?: string };
        } | null;
        if (!response.ok) {
          throw new Error(
            `Cloudinary resource deletion failed (${response.status}): ${
              payload?.error?.message ?? "unknown error"
            }`,
          );
        }

        for (const id of publicIds.slice(index, index + deleteBatchSize)) {
          const status = payload?.deleted?.[id];
          if (status !== "deleted" && status !== "not_found") {
            throw new Error(
              `Cloudinary did not confirm deletion for ${id}`,
            );
          }
        }
      }
    }

    const deletedRows = await deleteUserDatabaseRows(supabase, ownerId);
    if (!serviceRequest && supabaseAuthUser) {
      await deleteLegacyUserDatabaseRows(supabase, ownerId);
      await deleteProductAuthUser(supabase, ownerId);
    }

    return new Response(
      JSON.stringify({ success: true, deletedRows }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("delete-user-assets error", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
