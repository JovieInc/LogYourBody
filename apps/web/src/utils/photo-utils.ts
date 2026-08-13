export interface PhotoData {
  id: string;
  user_id: string;
  date: string;
  photo_url: string;
  original_photo_url?: string | null;
  weight?: number;
  weight_unit?: string;
  body_fat_percentage?: number;
  notes?: string;
  created_at: string;
}

export interface PhotoUploadResult {
  success: boolean;
  data?: PhotoData;
  error?: string;
}

const PHOTO_STORE_UNAVAILABLE =
  'Progress photo cloud storage is not available after the Supabase hard cut. Photos were not migrated.';

export async function loadUserPhotos(): Promise<PhotoData[]> {
  return [];
}

export async function loadPhoto(photoId: string): Promise<PhotoData | null> {
  void photoId;
  return null;
}

export async function deletePhoto(photoId: string): Promise<void> {
  void photoId;
  throw new Error(PHOTO_STORE_UNAVAILABLE);
}

export async function uploadPhotoWithMetrics(
  file: File,
  metrics?: Partial<PhotoData>,
): Promise<PhotoUploadResult> {
  void file;
  void metrics;
  return {
    success: false,
    error: PHOTO_STORE_UNAVAILABLE,
  };
}
