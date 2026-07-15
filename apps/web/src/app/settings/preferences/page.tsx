'use client';

import { useAuth } from '@/contexts/ProductAuthContext';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Switch } from '@/components/ui/switch';
import { toast } from '@/hooks/use-toast';
import { Loader2, ArrowLeft, Save, Camera, Sparkles } from 'lucide-react';
import Link from 'next/link';
import { UserSettings } from '@/types/body-metrics';

export default function PreferencesSettingsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [isSaving, setIsSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);

  const [_settings, setSettings] = useState<UserSettings>({
    units: {
      weight: 'lbs',
      height: 'ft',
      measurements: 'in',
    },
  });
  const [measurementSystem, setMeasurementSystem] = useState<'imperial' | 'metric'>('imperial');
  const [faceBlurring, setFaceBlurring] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin');
    }
  }, [user, loading, router]);

  if (loading) {
    return (
      <div className="bg-linear-bg flex min-h-screen items-center justify-center">
        <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  const handleSystemChange = (system: 'imperial' | 'metric') => {
    setMeasurementSystem(system);
    if (system === 'imperial') {
      setSettings((prev) => ({
        ...prev,
        units: {
          weight: 'lbs',
          height: 'ft',
          measurements: 'in',
        },
      }));
    } else {
      setSettings((prev) => ({
        ...prev,
        units: {
          weight: 'kg',
          height: 'cm',
          measurements: 'cm',
        },
      }));
    }
    setHasChanges(true);
  };

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      toast({
        title: 'Preferences saved',
        description: 'Your preferences have been updated successfully.',
      });
      setHasChanges(false);
    } catch {
      toast({
        title: 'Error',
        description: 'Failed to save preferences. Please try again.',
        variant: 'destructive',
      });
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="bg-linear-bg min-h-screen">
      {/* Header */}
      <header className="bg-linear-card border-linear-border sticky top-0 z-10 border-b shadow-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/settings">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-linear-text text-xl font-bold">Preferences</h1>
            </div>
            {hasChanges && (
              <Button
                onClick={handleSave}
                disabled={isSaving}
                size="sm"
                className="bg-linear-purple hover:bg-linear-purple/80 text-white"
              >
                {isSaving ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Save className="h-4 w-4" />
                )}
              </Button>
            )}
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto max-w-2xl space-y-6 px-4 py-6">
        {/* Units & Measurements */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Units & Measurements</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Choose your measurement system
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              <Label className="text-linear-text">Measurement System</Label>
              <Tabs
                value={measurementSystem}
                onValueChange={(value) => handleSystemChange(value as 'imperial' | 'metric')}
              >
                <TabsList className="bg-linear-bg grid w-full grid-cols-2">
                  <TabsTrigger
                    value="imperial"
                    className="data-[state=active]:bg-linear-purple data-[state=active]:text-white"
                  >
                    Imperial
                  </TabsTrigger>
                  <TabsTrigger
                    value="metric"
                    className="data-[state=active]:bg-linear-purple data-[state=active]:text-white"
                  >
                    Metric
                  </TabsTrigger>
                </TabsList>
              </Tabs>
              <div className="text-linear-text-secondary mt-4 space-y-2 text-sm">
                {measurementSystem === 'imperial' ? (
                  <>
                    <p>• Weight: Pounds (lbs)</p>
                    <p>• Height: Feet & Inches (ft/in)</p>
                    <p>• Measurements: Inches (in)</p>
                  </>
                ) : (
                  <>
                    <p>• Weight: Kilograms (kg)</p>
                    <p>• Height: Centimeters (cm)</p>
                    <p>• Measurements: Centimeters (cm)</p>
                  </>
                )}
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Privacy Features */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text flex items-center gap-2">
              <Camera className="h-5 w-5" />
              Privacy Features
            </CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Control how your progress photos are processed
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-6">
              <div className="flex items-start justify-between gap-4">
                <div className="flex-1 space-y-1">
                  <div className="flex items-center gap-2">
                    <Label htmlFor="face-blur" className="text-linear-text font-medium">
                      Face Blurring
                    </Label>
                    <div className="inline-flex items-center gap-1 rounded-full border border-purple-500/20 bg-purple-500/10 px-2 py-0.5 text-xs font-medium text-purple-400">
                      <Sparkles className="h-3 w-3" />
                      Coming Soon
                    </div>
                  </div>
                  <p className="text-linear-text-secondary text-sm">
                    Automatically blur your face in progress photos for additional privacy. Your
                    face will be detected and blurred before photos are stored.
                  </p>
                </div>
                <Switch
                  id="face-blur"
                  checked={faceBlurring}
                  onCheckedChange={setFaceBlurring}
                  disabled={true}
                  className="data-[state=checked]:bg-linear-purple"
                />
              </div>
              <div className="rounded-lg border border-purple-500/10 bg-purple-500/5 p-3">
                <p className="text-xs text-purple-400/80">
                  This feature is currently in development and will be available soon. When enabled,
                  it will use on-device AI to detect and blur faces automatically.
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      </main>
    </div>
  );
}
