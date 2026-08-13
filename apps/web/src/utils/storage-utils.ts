const PHOTO_STORE_UNAVAILABLE =
  'Progress photo cloud storage is not available after the Supabase hard cut.';

/**
 * Ensures a legacy Supabase storage URL uses the public format.
 * Kept for abandoned URL parsing; new uploads do not use this store.
 */
export function ensurePublicUrl(url: string): string {
  if (!url) return url;
  if (!url.includes('/storage/v1/object/')) return url;
  if (url.includes('/public/')) return url;
  return url.replace('/storage/v1/object/', '/storage/v1/object/public/');
}

export function getStoragePublicUrl(bucketName: string, filePath: string): string {
  void bucketName;
  void filePath;
  return '';
}

export async function uploadToStorage(
  bucketName: string,
  filePath: string,
  file: File | Blob,
  options?: {
    contentType?: string;
    upsert?: boolean;
  },
) {
  void bucketName;
  void filePath;
  void file;
  void options;
  return {
    data: null,
    publicUrl: '',
    error: { message: PHOTO_STORE_UNAVAILABLE },
  };
}

export async function deleteFromStorage(bucketName: string, filePath: string) {
  void bucketName;
  void filePath;
  return { error: { message: PHOTO_STORE_UNAVAILABLE } };
}

export function getFilePathFromUrl(url: string, bucketName: string): string | null {
  if (!url) return null;

  const patterns = [
    `/storage/v1/object/public/${bucketName}/`,
    `/storage/v1/object/${bucketName}/`,
  ];

  for (const pattern of patterns) {
    const index = url.indexOf(pattern);
    if (index !== -1) {
      return url.substring(index + pattern.length);
    }
  }

  return null;
}
