const safeCloudinarySegment = /^[A-Za-z0-9_-]+$/;

export function cloudinaryPublicIdForOwner(
  userId: string,
  metricId: string,
  timestamp: number,
): string {
  if (
    !safeCloudinarySegment.test(userId) ||
    !safeCloudinarySegment.test(metricId) ||
    !Number.isSafeInteger(timestamp) ||
    timestamp <= 0
  ) {
    throw new Error("Invalid Cloudinary asset identity");
  }

  return `progress-photos/${userId}/${metricId}_${timestamp}`;
}
