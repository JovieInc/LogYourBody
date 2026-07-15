'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/ProductAuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { toast } from '@/hooks/use-toast';
import {
  ArrowLeft,
  Camera,
  Upload,
  Image as ImageIcon,
  Weight,
  Percent,
  Trash2,
  Info,
  X,
  Loader2,
  Grid3x3,
  LayoutGrid,
} from 'lucide-react';
import Link from 'next/link';
import { format, differenceInDays } from 'date-fns';
import Image from 'next/image';
import {
  loadUserPhotos,
  deletePhoto,
  PhotoData,
  uploadPhotoWithMetrics,
} from '@/utils/photo-utils';
import {
  compressImage,
  validateImageFile,
  getUploadErrorMessage,
  retryUpload,
  checkBrowserSupport,
} from '@/utils/photo-upload-utils';

type ProgressPhoto = PhotoData & {
  url: string;
  thumbnail_url: string;
  uploaded_at: string;
};

type ViewMode = 'grid' | 'comparison';

export default function PhotosPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [photos, setPhotos] = useState<ProgressPhoto[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [viewMode, setViewMode] = useState<ViewMode>('grid');
  const [selectedPhotos, setSelectedPhotos] = useState<string[]>([]);
  const [isUploading, setIsUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [showUploadDialog, setShowUploadDialog] = useState(false);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin');
    } else if (user) {
      loadPhotos();
    }
  }, [user, loading, router]);

  const loadPhotos = async () => {
    setIsLoading(true);
    try {
      const photoData = await loadUserPhotos();

      // Transform to ProgressPhoto format
      const transformedPhotos: ProgressPhoto[] = photoData.map((photo) => ({
        ...photo,
        url: photo.photo_url,
        thumbnail_url: photo.photo_url, // Using same URL for now
        uploaded_at: photo.created_at,
      }));

      setPhotos(transformedPhotos);
    } catch (error) {
      console.error('Error loading photos:', error);
      toast({
        title: 'Error',
        description: 'Failed to load photos. Please try again.',
        variant: 'destructive',
      });
    } finally {
      setIsLoading(false);
    }
  };

  const handleFileSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    // Check browser support first
    const browserSupport = checkBrowserSupport();
    if (!browserSupport.supported) {
      toast({
        title: 'Browser not supported',
        description: `Your browser lacks support for: ${browserSupport.missingFeatures.join(', ')}`,
        variant: 'destructive',
      });
      return;
    }

    // Validate file
    const validation = validateImageFile(file);
    if (!validation.valid) {
      toast({
        title: 'Invalid file',
        description: validation.error,
        variant: 'destructive',
      });
      return;
    }

    setSelectedFile(file);

    // Create preview
    const reader = new FileReader();
    reader.onload = (e) => {
      setPreview(e.target?.result as string);
    };
    reader.readAsDataURL(file);

    setShowUploadDialog(true);
  };

  const handleUpload = async () => {
    if (!selectedFile || !user) return;

    setIsUploading(true);
    setUploadProgress(0);

    try {
      // Compress image before upload
      setUploadProgress(10);
      let fileToUpload: File | Blob = selectedFile;

      // Only compress if file is larger than 1MB
      if (selectedFile.size > 1024 * 1024) {
        try {
          const compressed = await compressImage(selectedFile, {
            maxWidth: 1920,
            maxHeight: 1920,
            quality: 0.85,
            format: 'jpeg',
          });

          // Only use compressed version if it's smaller
          if (compressed.size < selectedFile.size) {
            fileToUpload = compressed;
            console.log(
              `Compressed from ${(selectedFile.size / 1024 / 1024).toFixed(2)}MB to ${(compressed.size / 1024 / 1024).toFixed(2)}MB`,
            );
          }
        } catch (compressionError) {
          console.warn('Compression failed, using original:', compressionError);
          // Continue with original file if compression fails
        }
      }

      setUploadProgress(30);

      // Upload with retry mechanism
      const uploadOperation = async () => {
        const result = await uploadPhotoWithMetrics(fileToUpload as File, user.id, {
          notes: 'Progress photo',
        });

        if (!result.success) {
          throw new Error(result.error || 'Upload failed');
        }

        return result.data!;
      };

      setUploadProgress(50);
      const metricsData = await retryUpload(uploadOperation, 3, 1000);

      setUploadProgress(90);

      // Add to photos list
      const newPhoto: ProgressPhoto = {
        ...metricsData,
        url: metricsData.photo_url,
        thumbnail_url: metricsData.photo_url,
        uploaded_at: metricsData.created_at,
      };

      setPhotos((prev) => [newPhoto, ...prev]);

      setUploadProgress(100);

      toast({
        title: 'Success!',
        description: 'Photo uploaded successfully.',
      });

      setShowUploadDialog(false);
      setSelectedFile(null);
      setPreview(null);
    } catch (error) {
      console.error('Upload error:', error);
      const errorMessage = getUploadErrorMessage(error);

      toast({
        title: 'Upload failed',
        description: errorMessage,
        variant: 'destructive',
      });
    } finally {
      setIsUploading(false);
      setUploadProgress(0);
    }
  };

  const togglePhotoSelection = (photoId: string) => {
    setSelectedPhotos((prev) => {
      if (prev.includes(photoId)) {
        return prev.filter((id) => id !== photoId);
      }
      if (prev.length >= 2) {
        // Max 2 photos for comparison
        return [prev[1], photoId];
      }
      return [...prev, photoId];
    });
  };

  const handleDeletePhoto = async (photoId: string) => {
    if (!confirm('Are you sure you want to delete this photo?')) return;

    try {
      await deletePhoto(photoId);

      setPhotos((prev) => prev.filter((p) => p.id !== photoId));
      setSelectedPhotos((prev) => prev.filter((id) => id !== photoId));

      toast({
        title: 'Photo deleted',
        description: 'The photo has been removed.',
      });
    } catch (error) {
      console.error('Delete error:', error);
      toast({
        title: 'Error',
        description: 'Failed to delete photo. Please try again.',
        variant: 'destructive',
      });
    }
  };

  const selectedPhotoObjects = selectedPhotos
    .map((id) => photos.find((p) => p.id === id))
    .filter(Boolean) as ProgressPhoto[];

  if (loading || isLoading) {
    return (
      <div className="bg-linear-bg flex min-h-screen items-center justify-center">
        <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  return (
    <div className="bg-linear-bg min-h-screen">
      {/* Header */}
      <header className="bg-linear-card border-linear-border sticky top-0 z-10 border-b shadow-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/dashboard">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-linear-text text-xl font-bold">Progress Photos</h1>
            </div>
            <div className="flex items-center gap-2">
              {/* View Mode Toggle */}
              <div className="bg-linear-border/30 flex rounded-lg p-1">
                <button
                  onClick={() => setViewMode('grid')}
                  className={`rounded p-2 ${
                    viewMode === 'grid'
                      ? 'bg-linear-card text-linear-text'
                      : 'text-linear-text-secondary'
                  }`}
                  aria-label="Grid view"
                >
                  <Grid3x3 className="h-4 w-4" />
                </button>
                <button
                  onClick={() => setViewMode('comparison')}
                  className={`rounded p-2 ${
                    viewMode === 'comparison'
                      ? 'bg-linear-card text-linear-text'
                      : 'text-linear-text-secondary'
                  }`}
                  aria-label="Comparison view"
                >
                  <LayoutGrid className="h-4 w-4" />
                </button>
              </div>

              {/* Upload Button */}
              <Button
                onClick={() => document.getElementById('photo-upload')?.click()}
                size="sm"
                className="bg-linear-purple hover:bg-linear-purple/80 text-white"
              >
                <Camera className="mr-2 h-4 w-4" />
                Add Photo
              </Button>
              <input
                id="photo-upload"
                type="file"
                accept="image/jpeg,image/jpg,image/png,image/webp"
                onChange={handleFileSelect}
                className="hidden"
              />
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6">
        {photos.length === 0 ? (
          <Card className="bg-linear-card border-linear-border">
            <CardContent className="py-12 text-center">
              <div className="bg-linear-purple/10 mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full">
                <ImageIcon className="text-linear-purple h-8 w-8" />
              </div>
              <h2 className="text-linear-text mb-2 text-xl font-semibold">No photos yet</h2>
              <p className="text-linear-text-secondary mx-auto mb-6 max-w-sm">
                Start documenting your progress by taking your first photo.
              </p>
              <Button
                onClick={() => document.getElementById('photo-upload')?.click()}
                className="bg-linear-purple hover:bg-linear-purple/80 text-white"
              >
                <Camera className="mr-2 h-4 w-4" />
                Take First Photo
              </Button>
            </CardContent>
          </Card>
        ) : viewMode === 'grid' ? (
          <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
            {photos.map((photo) => (
              <Card
                key={photo.id}
                className="bg-linear-card border-linear-border group cursor-pointer overflow-hidden"
                onClick={() => togglePhotoSelection(photo.id)}
              >
                <div className="relative aspect-[3/4]">
                  <Image src={photo.url} alt="Progress photo" fill className="object-cover" />

                  {/* Selection indicator */}
                  {selectedPhotos.includes(photo.id) && (
                    <div className="bg-linear-purple/20 absolute inset-0 flex items-center justify-center">
                      <div className="bg-linear-purple flex h-12 w-12 items-center justify-center rounded-full">
                        <span className="font-bold text-white">
                          {selectedPhotos.indexOf(photo.id) + 1}
                        </span>
                      </div>
                    </div>
                  )}

                  {/* Overlay on hover */}
                  <div className="absolute inset-0 flex flex-col justify-between bg-black/60 p-4 opacity-0 transition-opacity group-hover:opacity-100">
                    <div className="flex justify-end gap-2">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDeletePhoto(photo.id);
                        }}
                        className="flex h-8 w-8 items-center justify-center rounded-full bg-red-500/20 text-red-500 hover:bg-red-500/30"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>

                    <div className="space-y-2 text-white">
                      <div className="text-sm">
                        {format(new Date(photo.uploaded_at), 'MMM d, yyyy')}
                      </div>
                      {photo.weight && (
                        <div className="flex items-center gap-1 text-xs">
                          <Weight className="h-3 w-3" />
                          {photo.weight} kg
                        </div>
                      )}
                      {photo.body_fat_percentage && (
                        <div className="flex items-center gap-1 text-xs">
                          <Percent className="h-3 w-3" />
                          {photo.body_fat_percentage}%
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        ) : (
          // Comparison View
          <div className="space-y-6">
            {/* Instructions */}
            <Alert className="border-linear-border bg-linear-card">
              <Info className="text-linear-text h-4 w-4" />
              <AlertDescription className="text-linear-text-secondary">
                Select up to 2 photos to compare your progress side by side.
              </AlertDescription>
            </Alert>

            {/* Comparison Display */}
            {selectedPhotos.length === 2 ? (
              <Card className="bg-linear-card border-linear-border p-6">
                <div className="grid gap-6 md:grid-cols-2">
                  {selectedPhotoObjects.map((photo, index) => (
                    <div key={photo.id} className="space-y-4">
                      <div className="relative aspect-[3/4] overflow-hidden rounded-lg">
                        <Image
                          src={photo.url}
                          alt={`Progress photo ${index + 1}`}
                          fill
                          className="object-cover"
                        />
                      </div>

                      <div className="space-y-2">
                        <div className="text-center">
                          <div className="text-linear-text text-lg font-medium">
                            {format(new Date(photo.uploaded_at), 'MMM d, yyyy')}
                          </div>
                          {index === 0 && selectedPhotoObjects[1] && (
                            <div className="text-linear-text-secondary text-sm">
                              {differenceInDays(
                                new Date(selectedPhotoObjects[1].uploaded_at),
                                new Date(photo.uploaded_at),
                              )}{' '}
                              days ago
                            </div>
                          )}
                        </div>

                        <div className="grid grid-cols-2 gap-2 text-sm">
                          {photo.weight && (
                            <div className="bg-linear-bg rounded-lg p-2 text-center">
                              <div className="text-linear-text-secondary">Weight</div>
                              <div className="text-linear-text font-medium">{photo.weight} kg</div>
                            </div>
                          )}
                          {photo.body_fat_percentage && (
                            <div className="bg-linear-bg rounded-lg p-2 text-center">
                              <div className="text-linear-text-secondary">Body Fat</div>
                              <div className="text-linear-text font-medium">
                                {photo.body_fat_percentage}%
                              </div>
                            </div>
                          )}
                        </div>

                        {photo.notes && (
                          <div className="text-linear-text-secondary text-sm italic">
                            "{photo.notes}"
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>

                {/* Progress Summary */}
                {selectedPhotoObjects[0].weight && selectedPhotoObjects[1].weight && (
                  <div className="border-linear-border mt-6 border-t pt-6">
                    <h3 className="text-linear-text mb-3 font-medium">Progress Summary</h3>
                    <div className="grid grid-cols-2 gap-4">
                      <div className="bg-linear-bg rounded-lg p-3">
                        <div className="text-linear-text-secondary mb-1 text-sm">Weight Change</div>
                        <div className="text-linear-text font-medium">
                          {(
                            selectedPhotoObjects[1].weight - selectedPhotoObjects[0].weight
                          ).toFixed(1)}{' '}
                          kg
                        </div>
                      </div>
                      {selectedPhotoObjects[0].body_fat_percentage &&
                        selectedPhotoObjects[1].body_fat_percentage && (
                          <div className="bg-linear-bg rounded-lg p-3">
                            <div className="text-linear-text-secondary mb-1 text-sm">
                              Body Fat Change
                            </div>
                            <div className="text-linear-text font-medium">
                              {(
                                selectedPhotoObjects[1].body_fat_percentage -
                                selectedPhotoObjects[0].body_fat_percentage
                              ).toFixed(1)}
                              %
                            </div>
                          </div>
                        )}
                    </div>
                  </div>
                )}
              </Card>
            ) : (
              <Card className="bg-linear-card border-linear-border">
                <CardContent className="py-12 text-center">
                  <p className="text-linear-text-secondary">
                    Select 2 photos from the grid below to compare
                  </p>
                </CardContent>
              </Card>
            )}

            {/* Photo Grid for Selection */}
            <div className="grid grid-cols-3 gap-3 md:grid-cols-4 lg:grid-cols-6">
              {photos.map((photo) => (
                <div
                  key={photo.id}
                  onClick={() => togglePhotoSelection(photo.id)}
                  className={`relative aspect-[3/4] cursor-pointer overflow-hidden rounded-lg border-2 transition-all ${
                    selectedPhotos.includes(photo.id)
                      ? 'border-linear-purple'
                      : 'border-transparent'
                  }`}
                >
                  <Image
                    src={photo.thumbnail_url}
                    alt="Progress photo thumbnail"
                    fill
                    className="object-cover"
                  />
                  {selectedPhotos.includes(photo.id) && (
                    <div className="bg-linear-purple/20 absolute inset-0 flex items-center justify-center">
                      <div className="bg-linear-purple flex h-8 w-8 items-center justify-center rounded-full">
                        <span className="text-sm font-bold text-white">
                          {selectedPhotos.indexOf(photo.id) + 1}
                        </span>
                      </div>
                    </div>
                  )}
                  <div className="absolute bottom-0 left-0 right-0 bg-black/60 p-1">
                    <div className="text-center text-xs text-white">
                      {format(new Date(photo.uploaded_at), 'MMM d')}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </main>

      {/* Upload Dialog */}
      {showUploadDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <Card className="bg-linear-card border-linear-border w-full max-w-md">
            <div className="p-6">
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-linear-text text-xl font-semibold">Upload Photo</h2>
                <button
                  onClick={() => {
                    setShowUploadDialog(false);
                    setSelectedFile(null);
                    setPreview(null);
                  }}
                  className="text-linear-text-secondary hover:text-linear-text"
                >
                  <X className="h-5 w-5" />
                </button>
              </div>

              {preview && (
                <div className="mb-4">
                  <div className="relative aspect-[3/4] overflow-hidden rounded-lg">
                    <Image src={preview} alt="Preview" fill className="object-cover" />
                  </div>
                </div>
              )}

              {isUploading ? (
                <div className="space-y-3">
                  <Progress value={uploadProgress} className="h-2" />
                  <div className="text-center">
                    <p className="text-linear-text-secondary mb-1 text-sm">
                      {uploadProgress < 30
                        ? 'Preparing image...'
                        : uploadProgress < 50
                          ? 'Compressing...'
                          : uploadProgress < 90
                            ? 'Uploading...'
                            : 'Almost done...'}
                    </p>
                    <p className="text-linear-text-tertiary text-xs">{uploadProgress}%</p>
                  </div>
                </div>
              ) : (
                <div className="space-y-4">
                  <Alert className="border-linear-border bg-linear-card">
                    <Info className="text-linear-text h-4 w-4" />
                    <AlertDescription className="text-linear-text-secondary text-sm">
                      Tip: Take photos in consistent lighting and poses for better comparisons.
                    </AlertDescription>
                  </Alert>

                  <div className="flex gap-3">
                    <Button
                      onClick={() => {
                        setShowUploadDialog(false);
                        setSelectedFile(null);
                        setPreview(null);
                      }}
                      variant="outline"
                      className="flex-1"
                    >
                      Cancel
                    </Button>
                    <Button
                      onClick={handleUpload}
                      className="bg-linear-purple hover:bg-linear-purple/80 flex-1 text-white"
                    >
                      <Upload className="mr-2 h-4 w-4" />
                      Upload
                    </Button>
                  </div>
                </div>
              )}
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}
