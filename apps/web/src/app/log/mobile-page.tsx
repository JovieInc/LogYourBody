'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { Button } from '@/components/ui/button'
// import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
// import { Progress } from '@/components/ui/progress'
// import { Separator } from '@/components/ui/separator'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { WeightWheelPicker, BodyFatWheelPicker } from '@/components/ui/weight-wheel-picker'
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group'
import { toast } from '@/hooks/use-toast'
import { 
  ArrowLeft, 
  ArrowRight,
  Camera,
  X,
  Check,
  Percent,
  User,
  AlertCircle
} from 'lucide-react'
// import Link from 'next/link'
import { format } from 'date-fns'
import { calculateNavyBodyFat, calculate3SiteBodyFat, calculateFFMI, calculateBodyComposition, convertMeasurement } from '@/utils/body-calculations'
import { UserProfile } from '@/types/body-metrics'
import { 
  compressImage, 
  validateImageFile, 
  getUploadErrorMessage,
  checkBrowserSupport
} from '@/utils/photo-upload-utils'
import { uploadToStorage } from '@/utils/storage-utils'
import { createClient } from '@/lib/supabase/client'
import { getProfile } from '@/lib/supabase/profile'
import Image from 'next/image'
import { cn } from '@/lib/utils'
import { motion, AnimatePresence } from 'framer-motion'

type Step = 'weight' | 'method' | 'measurements' | 'photo' | 'review'
type BodyFatMethod = 'simple' | 'navy' | '3-site'

const STEPS: Step[] = ['weight', 'method', 'measurements', 'photo', 'review']

// const STEP_TITLES = {
//   weight: 'Weight',
//   method: 'Method',
//   measurements: 'Body Fat',
//   photo: 'Photo',
//   review: 'Review',
// } as const

export default function MobileLogPage() {
  const { user, loading } = useAuth()
  const router = useRouter()
  const [currentStep, setCurrentStep] = useState<Step>('weight')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [showExitDialog, setShowExitDialog] = useState(false)
  
  // Form state
  const [formData, setFormData] = useState({
    weight: '',
    weight_unit: 'lbs' as 'kg' | 'lbs',
    method: 'simple' as BodyFatMethod,
    body_fat_percentage: null as number | null,
    // Navy method
    neck: '',
    waist: '',
    hip: '',
    // 3-site method
    chest: '',
    abdominal: '',
    thigh: '',
    tricep: '',
    suprailiac: '',
    // Photo
    photo: null as File | null,
    photoPreview: null as string | null,
    // Optional
    notes: ''
  })

  const [profile, setProfile] = useState<{
    height?: number
    height_unit?: 'cm' | 'ft'
    gender?: 'male' | 'female'
    date_of_birth?: string
    settings?: UserProfile['settings']
  }>({})

  const [isUploadingPhoto, setIsUploadingPhoto] = useState(false)
  const [showWeightModal, setShowWeightModal] = useState(false)
  const [showBodyFatModal, setShowBodyFatModal] = useState(false)

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin')
    }
  }, [user, loading, router])

  useEffect(() => {
    if (user) {
      getProfile(user.id).then((profileData) => {
        if (profileData) {
          setProfile({
            height: profileData.height,
            height_unit: profileData.height_unit,
            gender: profileData.gender as 'male' | 'female' | undefined,
            date_of_birth: profileData.date_of_birth,
            settings: profileData.settings
          })
          
          // Update form data with user's preferred units
          if (profileData.settings?.units?.weight) {
            setFormData(prev => ({
              ...prev,
              weight_unit: profileData.settings.units!.weight as 'kg' | 'lbs'
            }))
          }
        }
      }).catch((error) => {
        console.error('Error loading profile:', error)
      })
    }
  }, [user])

  const currentStepIndex = STEPS.indexOf(currentStep)

  const handleNext = () => {
    if (currentStepIndex < STEPS.length - 1) {
      // Calculate body fat if moving from measurements step
      if (currentStep === 'measurements') {
        calculateBodyFat()
      }
      setCurrentStep(STEPS[currentStepIndex + 1])
    }
  }

  const handleBack = () => {
    if (currentStepIndex > 0) {
      setCurrentStep(STEPS[currentStepIndex - 1])
    }
  }

  const handleExit = () => {
    if (formData.weight || formData.body_fat_percentage) {
      setShowExitDialog(true)
    } else {
      router.push('/dashboard')
    }
  }

  const calculateAge = () => {
    if (!profile.date_of_birth) return 30 // default
    const today = new Date()
    const birthDate = new Date(profile.date_of_birth)
    let age = today.getFullYear() - birthDate.getFullYear()
    const monthDiff = today.getMonth() - birthDate.getMonth()
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
      age--
    }
    return age
  }

  const calculateBodyFat = () => {
    try {
      let bodyFat: number | null = null
      
      if (formData.method === 'navy' && formData.waist && formData.neck) {
        // Convert measurements to cm if they're in inches
        const measurementUnit = profile.settings?.units?.measurements || 'in'
        const waistCm = measurementUnit === 'in' 
          ? convertMeasurement(parseFloat(formData.waist), 'in', 'cm')
          : parseFloat(formData.waist)
        const neckCm = measurementUnit === 'in'
          ? convertMeasurement(parseFloat(formData.neck), 'in', 'cm')
          : parseFloat(formData.neck)
        const hipCm = formData.hip 
          ? (measurementUnit === 'in' 
              ? convertMeasurement(parseFloat(formData.hip), 'in', 'cm')
              : parseFloat(formData.hip))
          : undefined
        
        // Convert height to cm if needed
        const heightCm = profile.settings?.units?.height === 'ft' 
          ? profile.height! * 2.54 // height is stored in inches when unit is 'ft'
          : profile.height!
        
        bodyFat = calculateNavyBodyFat(
          profile.gender as 'male' | 'female',
          waistCm,
          neckCm,
          heightCm,
          hipCm
        )
      } else if (formData.method === '3-site') {
        const age = calculateAge()
        if (profile.gender === 'male' && formData.chest && formData.abdominal && formData.thigh) {
          bodyFat = calculate3SiteBodyFat(
            'male',
            age,
            parseFloat(formData.chest),
            parseFloat(formData.abdominal),
            parseFloat(formData.thigh)
          )
        } else if (profile.gender === 'female' && formData.tricep && formData.suprailiac && formData.thigh) {
          bodyFat = calculate3SiteBodyFat(
            'female',
            age,
            undefined,
            undefined,
            parseFloat(formData.thigh),
            parseFloat(formData.tricep),
            parseFloat(formData.suprailiac)
          )
        }
      }
      
      if (bodyFat !== null) {
        setFormData(prev => ({ ...prev, body_fat_percentage: Math.round(bodyFat * 10) / 10 }))
      }
    } catch (error) {
      console.error('Error calculating body fat:', error)
    }
  }

  const handleSubmit = async () => {
    if (!user) return
    
    setIsSubmitting(true)
    try {
      const supabase = createClient()
      let photoUrl = null
      
      // Upload photo if present
      if (formData.photo) {
        const fileName = `${user.id}/${Date.now()}-progress.jpg`
        const { publicUrl, error: uploadError } = await uploadToStorage(
          'photos',
          fileName,
          formData.photo,
          { contentType: formData.photo.type }
        )
        
        if (uploadError) {
          throw new Error('Failed to upload photo')
        }
        
        photoUrl = publicUrl
      }
      
      // Convert weight to kg for storage
      const weightInKg = formData.weight_unit === 'lbs' 
        ? parseFloat(formData.weight) / 2.20462 
        : parseFloat(formData.weight)
      
      // Save body metrics
      const { error } = await supabase
        .from('body_metrics')
        .insert({
          user_id: user.id,
          date: format(new Date(), 'yyyy-MM-dd'),
          weight: weightInKg,
          weight_unit: 'kg', // Always store in kg
          body_fat_percentage: formData.body_fat_percentage,
          body_fat_method: formData.method === 'simple' ? undefined : formData.method,
          notes: formData.notes || null,
          photo_url: photoUrl
        })
      
      if (error) throw error
      
      toast({
        title: "Success!",
        description: "Your metrics have been logged successfully."
      })
      
      // Clean up photo preview
      if (formData.photoPreview) {
        URL.revokeObjectURL(formData.photoPreview)
      }
      
      router.push('/dashboard')
    } catch (error) {
      console.error('Submit error:', error)
      toast({
        title: "Error",
        description: error instanceof Error ? error.message : "Failed to save metrics. Please try again.",
        variant: "destructive"
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  const getFFMIData = () => {
    if (!formData.weight || !formData.body_fat_percentage || !profile.height) return null
    const weight = formData.weight_unit === 'lbs' 
      ? parseFloat(formData.weight) / 2.20462 
      : parseFloat(formData.weight)
    
    // Convert height to cm if needed
    const heightCm = profile.settings?.units?.height === 'ft'
      ? profile.height * 2.54 // height is stored in inches when unit is 'ft'
      : profile.height
    
    return calculateFFMI(weight, heightCm, formData.body_fat_percentage)
  }

  const handlePhotoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    setIsUploadingPhoto(true)
    try {
      // Check browser support
      const support = checkBrowserSupport()
      if (!support.supported) {
        toast({
          title: "Browser not supported",
          description: `Missing features: ${support.missingFeatures.join(', ')}`,
          variant: "destructive"
        })
        return
      }

      // Validate file
      const validation = validateImageFile(file)
      if (!validation.valid) {
        toast({
          title: "Invalid file",
          description: validation.error,
          variant: "destructive"
        })
        return
      }

      // Compress image
      const compressedFile = await compressImage(file, {
        maxWidth: 1920,
        maxHeight: 1920,
        quality: 0.8
      })

      // Create preview
      const preview = URL.createObjectURL(compressedFile)
      
      setFormData(prev => ({
        ...prev,
        photo: compressedFile as File,
        photoPreview: preview
      }))

      toast({
        title: "Photo added",
        description: "Your progress photo has been added successfully."
      })
    } catch (error) {
      const message = getUploadErrorMessage(error)
      toast({
        title: "Photo processing failed",
        description: message,
        variant: "destructive"
      })
    } finally {
      setIsUploadingPhoto(false)
    }
  }

  const removePhoto = () => {
    if (formData.photoPreview) {
      URL.revokeObjectURL(formData.photoPreview)
    }
    setFormData(prev => ({
      ...prev,
      photo: null,
      photoPreview: null
    }))
  }

  const getBodyComposition = () => {
    if (!formData.weight || !formData.body_fat_percentage) return null
    const weight = formData.weight_unit === 'lbs' 
      ? parseFloat(formData.weight) / 2.20462 
      : parseFloat(formData.weight)
    return calculateBodyComposition(weight, formData.body_fat_percentage)
  }

  const ffmiData = getFFMIData()
  const bodyComp = getBodyComposition()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-linear-bg">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-linear-purple"></div>
      </div>
    )
  }

  return (
    <>
      {/* Full Screen Mobile Experience */}
      <div className="fixed inset-0 bg-linear-bg z-50 flex flex-col">
        {/* Minimal Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-linear-border/50">
          <div className="flex items-center gap-3">
            <div className="flex gap-1.5">
              {STEPS.map((step, index) => (
                <div
                  key={step}
                  className={cn(
                    "h-1.5 rounded-full transition-all duration-300",
                    index < currentStepIndex 
                      ? "w-6 bg-linear-purple" 
                      : index === currentStepIndex 
                      ? "w-8 bg-linear-purple" 
                      : "w-1.5 bg-linear-border"
                  )}
                />
              ))}
            </div>
          </div>
          <button
            onClick={handleExit}
            className="p-2 -mr-2 text-linear-text-secondary hover:text-linear-text"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-y-auto">
          <AnimatePresence mode="wait">
            <motion.div
              key={currentStep}
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -20 }}
              transition={{ duration: 0.2 }}
              className="px-6 py-8"
            >
              {/* Step Content */}
              {currentStep === 'weight' && (
                <div className="space-y-8">
                  <div className="text-center">
                    <h2 className="text-3xl font-bold text-linear-text mb-2">
                      Current Weight
                    </h2>
                    <p className="text-linear-text-secondary">
                      How much do you weigh today?
                    </p>
                  </div>

                  {/* Weight requirement message */}
                  <div className="flex items-start gap-2 p-3 bg-amber-50 dark:bg-amber-950/20 rounded-lg border border-amber-200 dark:border-amber-800">
                    <AlertCircle className="h-5 w-5 text-amber-600 dark:text-amber-500 flex-shrink-0 mt-0.5" />
                    <div className="text-sm text-amber-800 dark:text-amber-300">
                      <p className="font-medium">Weight entry is required</p>
                      <p className="text-amber-700 dark:text-amber-400 mt-1">
                        Tap the box below to enter your weight
                      </p>
                    </div>
                  </div>

                  <button
                    onClick={() => setShowWeightModal(true)}
                    className="w-full"
                  >
                    <div className={`border-2 rounded-2xl p-8 text-center transition-all ${
                      formData.weight 
                        ? 'bg-linear-card border-linear-border hover:border-linear-purple/50' 
                        : 'bg-linear-purple/10 border-linear-purple hover:bg-linear-purple/20 animate-pulse'
                    }`}>
                      {formData.weight ? (
                        <div className="space-y-1">
                          <div className="text-5xl font-bold text-linear-text">
                            {formData.weight}
                          </div>
                          <div className="text-xl text-linear-text-secondary">
                            {formData.weight_unit}
                          </div>
                        </div>
                      ) : (
                        <div className="space-y-2">
                          <User className="h-12 w-12 mx-auto text-linear-purple" />
                          <div className="text-xl text-linear-text font-medium">
                            Tap to enter weight
                          </div>
                        </div>
                      )}
                    </div>
                  </button>

                  <div className="flex justify-center">
                    <ToggleGroup
                      type="single"
                      value={formData.weight_unit}
                      onValueChange={(value) => value && setFormData(prev => ({ ...prev, weight_unit: value as 'kg' | 'lbs' }))}
                      className="bg-linear-card rounded-lg p-1"
                    >
                      <ToggleGroupItem value="lbs" className="px-8 data-[state=on]:bg-linear-purple data-[state=on]:text-white">
                        lbs
                      </ToggleGroupItem>
                      <ToggleGroupItem value="kg" className="px-8 data-[state=on]:bg-linear-purple data-[state=on]:text-white">
                        kg
                      </ToggleGroupItem>
                    </ToggleGroup>
                  </div>
                </div>
              )}

              {currentStep === 'method' && (
                <div className="space-y-8">
                  <div className="text-center">
                    <h2 className="text-3xl font-bold text-linear-text mb-2">
                      Body Fat Method
                    </h2>
                    <p className="text-linear-text-secondary">
                      How do you want to track body fat?
                    </p>
                  </div>

                  <RadioGroup
                    value={formData.method}
                    onValueChange={(value) => value && setFormData(prev => ({ ...prev, method: value as BodyFatMethod }))}
                    className="space-y-4"
                  >
                    <label htmlFor="simple" className="block">
                      <div className={cn(
                        "border-2 rounded-xl p-6 transition-all cursor-pointer",
                        formData.method === 'simple' 
                          ? "border-linear-purple bg-linear-purple/10" 
                          : "border-linear-border hover:border-linear-border/70"
                      )}>
                        <div className="flex items-start gap-4">
                          <RadioGroupItem value="simple" id="simple" className="mt-1" />
                          <div className="flex-1">
                            <div className="font-semibold text-linear-text mb-1">
                              Simple Entry
                            </div>
                            <div className="text-sm text-linear-text-secondary">
                              I'll enter my body fat % directly
                            </div>
                          </div>
                        </div>
                      </div>
                    </label>

                    <label htmlFor="navy" className="block">
                      <div className={cn(
                        "border-2 rounded-xl p-6 transition-all cursor-pointer",
                        formData.method === 'navy' 
                          ? "border-linear-purple bg-linear-purple/10" 
                          : "border-linear-border hover:border-linear-border/70"
                      )}>
                        <div className="flex items-start gap-4">
                          <RadioGroupItem value="navy" id="navy" className="mt-1" />
                          <div className="flex-1">
                            <div className="font-semibold text-linear-text mb-1">
                              Navy Method
                            </div>
                            <div className="text-sm text-linear-text-secondary">
                              Calculate using waist, neck, and hip measurements
                            </div>
                          </div>
                        </div>
                      </div>
                    </label>

                    <label htmlFor="3-site" className="block">
                      <div className={cn(
                        "border-2 rounded-xl p-6 transition-all cursor-pointer",
                        formData.method === '3-site' 
                          ? "border-linear-purple bg-linear-purple/10" 
                          : "border-linear-border hover:border-linear-border/70"
                      )}>
                        <div className="flex items-start gap-4">
                          <RadioGroupItem value="3-site" id="3-site" className="mt-1" />
                          <div className="flex-1">
                            <div className="font-semibold text-linear-text mb-1">
                              3-Site Skinfold
                            </div>
                            <div className="text-sm text-linear-text-secondary">
                              Most accurate with calipers
                            </div>
                          </div>
                        </div>
                      </div>
                    </label>
                  </RadioGroup>
                </div>
              )}

              {currentStep === 'measurements' && (
                <div className="space-y-8">
                  <div className="text-center">
                    <h2 className="text-3xl font-bold text-linear-text mb-2">
                      {formData.method === 'simple' ? 'Body Fat %' : 'Measurements'}
                    </h2>
                    <p className="text-linear-text-secondary">
                      {formData.method === 'simple' 
                        ? 'Enter your body fat percentage'
                        : 'Enter your measurements for calculation'
                      }
                    </p>
                  </div>

                  {formData.method === 'simple' && (
                    <button
                      onClick={() => setShowBodyFatModal(true)}
                      className="w-full"
                    >
                      <div className="bg-linear-card border-2 border-linear-border rounded-2xl p-8 text-center hover:border-linear-purple/50 transition-colors">
                        {formData.body_fat_percentage ? (
                          <div className="space-y-1">
                            <div className="text-5xl font-bold text-linear-text">
                              {formData.body_fat_percentage}%
                            </div>
                            <div className="text-xl text-linear-text-secondary">
                              Body Fat
                            </div>
                          </div>
                        ) : (
                          <div className="space-y-2">
                            <Percent className="h-12 w-12 mx-auto text-linear-text-tertiary" />
                            <div className="text-xl text-linear-text-secondary">
                              Tap to enter body fat %
                            </div>
                          </div>
                        )}
                      </div>
                    </button>
                  )}

                  {formData.method === 'navy' && (
                    <div className="space-y-6">
                      <div>
                        <Label htmlFor="neck" className="text-linear-text mb-2 block">
                          Neck ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                        </Label>
                        <Input
                          id="neck"
                          type="number"
                          step="0.1"
                          value={formData.neck}
                          onChange={(e) => setFormData(prev => ({ ...prev, neck: e.target.value }))}
                          className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                          placeholder="15.0"
                        />
                      </div>
                      
                      <div>
                        <Label htmlFor="waist" className="text-linear-text mb-2 block">
                          Waist ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                        </Label>
                        <Input
                          id="waist"
                          type="number"
                          step="0.1"
                          value={formData.waist}
                          onChange={(e) => setFormData(prev => ({ ...prev, waist: e.target.value }))}
                          className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                          placeholder="33.5"
                        />
                        <p className="text-xs text-linear-text-tertiary mt-1">
                          Measure at navel level
                        </p>
                      </div>
                      
                      {profile.gender === 'female' && (
                        <div>
                          <Label htmlFor="hip" className="text-linear-text mb-2 block">
                            Hip ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                          </Label>
                          <Input
                            id="hip"
                            type="number"
                            step="0.1"
                            value={formData.hip}
                            onChange={(e) => setFormData(prev => ({ ...prev, hip: e.target.value }))}
                            className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                            placeholder="37.5"
                          />
                          <p className="text-xs text-linear-text-tertiary mt-1">
                            Measure at widest point
                          </p>
                        </div>
                      )}
                    </div>
                  )}

                  {formData.method === '3-site' && profile.gender === 'male' && (
                    <div className="space-y-6">
                      <div>
                        <Label htmlFor="chest" className="text-linear-text mb-2 block">Chest (mm)</Label>
                        <Input
                          id="chest"
                          type="number"
                          step="0.1"
                          value={formData.chest}
                          onChange={(e) => setFormData(prev => ({ ...prev, chest: e.target.value }))}
                          className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                          placeholder="10"
                        />
                      </div>
                      
                      <div>
                        <Label htmlFor="abdominal" className="text-linear-text mb-2 block">Abdominal (mm)</Label>
                        <Input
                          id="abdominal"
                          type="number"
                          step="0.1"
                          value={formData.abdominal}
                          onChange={(e) => setFormData(prev => ({ ...prev, abdominal: e.target.value }))}
                          className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                          placeholder="20"
                        />
                      </div>
                      
                      <div>
                        <Label htmlFor="thigh" className="text-linear-text mb-2 block">Thigh (mm)</Label>
                        <Input
                          id="thigh"
                          type="number"
                          step="0.1"
                          value={formData.thigh}
                          onChange={(e) => setFormData(prev => ({ ...prev, thigh: e.target.value }))}
                          className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                          placeholder="15"
                        />
                      </div>
                    </div>
                  )}

                  {formData.method === '3-site' && profile.gender === 'female' && (
                    <div className="space-y-6">
                      <div>
                        <Label htmlFor="tricep" className="text-linear-text mb-2 block">Tricep (mm)</Label>
                        <Input
                          id="tricep"
                          type="number"
                          step="0.1"
                          value={formData.tricep}
                          onChange={(e) => setFormData(prev => ({ ...prev, tricep: e.target.value }))}
                          className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                          placeholder="15"
                        />
                      </div>
                      
                      <div>
                        <Label htmlFor="suprailiac" className="text-linear-text mb-2 block">Suprailiac (mm)</Label>
                        <Input
                          id="suprailiac"
                          type="number"
                          step="0.1"
                          value={formData.suprailiac}
                          onChange={(e) => setFormData(prev => ({ ...prev, suprailiac: e.target.value }))}
                          className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                          placeholder="12"
                        />
                      </div>
                      
                      <div>
                        <Label htmlFor="thigh" className="text-linear-text mb-2 block">Thigh (mm)</Label>
                        <Input
                          id="thigh"
                          type="number"
                          step="0.1"
                          value={formData.thigh}
                          onChange={(e) => setFormData(prev => ({ ...prev, thigh: e.target.value }))}
                          className="bg-linear-card border-linear-border text-linear-text text-lg h-14"
                          placeholder="20"
                        />
                      </div>
                    </div>
                  )}
                </div>
              )}

              {currentStep === 'photo' && (
                <div className="space-y-8">
                  <div className="text-center">
                    <h2 className="text-3xl font-bold text-linear-text mb-2">
                      Progress Photo
                    </h2>
                    <p className="text-linear-text-secondary">
                      Track your visual progress (optional)
                    </p>
                  </div>

                  {formData.photoPreview ? (
                    <div className="relative">
                      <div className="rounded-2xl overflow-hidden bg-linear-card border border-linear-border">
                        <Image
                          src={formData.photoPreview}
                          alt="Progress photo"
                          width={400}
                          height={600}
                          className="w-full h-auto"
                        />
                      </div>
                      <button
                        onClick={removePhoto}
                        className="absolute top-4 right-4 p-2 bg-linear-bg/80 backdrop-blur-sm rounded-full border border-linear-border"
                      >
                        <X className="h-4 w-4" />
                      </button>
                    </div>
                  ) : (
                    <label className="block cursor-pointer">
                      <input
                        type="file"
                        accept="image/*"
                        onChange={handlePhotoUpload}
                        className="hidden"
                        disabled={isUploadingPhoto}
                      />
                      <div className="bg-linear-card border-2 border-dashed border-linear-border rounded-2xl p-12 text-center hover:border-linear-purple/50 transition-colors">
                        {isUploadingPhoto ? (
                          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-linear-purple mx-auto"></div>
                        ) : (
                          <>
                            <Camera className="h-16 w-16 mx-auto text-linear-text-tertiary mb-4" />
                            <div className="text-xl text-linear-text-secondary mb-2">
                              Add progress photo
                            </div>
                            <div className="text-sm text-linear-text-tertiary">
                              Tap to select from camera or gallery
                            </div>
                          </>
                        )}
                      </div>
                    </label>
                  )}
                </div>
              )}

              {currentStep === 'review' && (
                <div className="space-y-8">
                  <div className="text-center">
                    <h2 className="text-3xl font-bold text-linear-text mb-2">
                      Review & Save
                    </h2>
                    <p className="text-linear-text-secondary">
                      Confirm your entries before saving
                    </p>
                  </div>

                  <div className="bg-linear-card rounded-2xl p-6 space-y-4">
                    <div className="flex items-center justify-between py-3 border-b border-linear-border">
                      <span className="text-linear-text-secondary">Date</span>
                      <span className="font-medium text-linear-text">
                        {format(new Date(), 'MMMM d, yyyy')}
                      </span>
                    </div>
                    
                    <div className="flex items-center justify-between py-3 border-b border-linear-border">
                      <span className="text-linear-text-secondary">Weight</span>
                      <span className="font-medium text-linear-text">
                        {formData.weight} {formData.weight_unit}
                      </span>
                    </div>
                    
                    {formData.body_fat_percentage && (
                      <>
                        <div className="flex items-center justify-between py-3 border-b border-linear-border">
                          <span className="text-linear-text-secondary">Body Fat %</span>
                          <span className="font-medium text-linear-text">
                            {formData.body_fat_percentage.toFixed(1)}%
                          </span>
                        </div>
                        
                        {bodyComp && (
                          <>
                            <div className="flex items-center justify-between py-3 border-b border-linear-border">
                              <span className="text-linear-text-secondary">Lean Mass</span>
                              <span className="font-medium text-linear-text">
                                {(formData.weight_unit === 'lbs' 
                                  ? bodyComp.lean_mass * 2.20462 
                                  : bodyComp.lean_mass
                                ).toFixed(1)} {formData.weight_unit}
                              </span>
                            </div>
                            
                            <div className="flex items-center justify-between py-3 border-b border-linear-border">
                              <span className="text-linear-text-secondary">Fat Mass</span>
                              <span className="font-medium text-linear-text">
                                {(formData.weight_unit === 'lbs' 
                                  ? bodyComp.fat_mass * 2.20462 
                                  : bodyComp.fat_mass
                                ).toFixed(1)} {formData.weight_unit}
                              </span>
                            </div>
                          </>
                        )}
                        
                        {ffmiData && (
                          <div className="flex items-center justify-between py-3">
                            <span className="text-linear-text-secondary">FFMI</span>
                            <span className="font-medium text-linear-text">
                              {ffmiData.normalized_ffmi}
                            </span>
                          </div>
                        )}
                      </>
                    )}
                  </div>

                  {/* Notes */}
                  <div>
                    <Label htmlFor="notes" className="text-linear-text mb-2 block">
                      Notes (optional)
                    </Label>
                    <Input
                      id="notes"
                      value={formData.notes}
                      onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
                      className="bg-linear-card border-linear-border text-linear-text"
                      placeholder="Any additional notes..."
                    />
                  </div>
                </div>
              )}
            </motion.div>
          </AnimatePresence>
        </div>

        {/* Bottom Navigation */}
        <div className="border-t border-linear-border bg-linear-bg">
          <div className="flex gap-3 p-4">
            {currentStepIndex > 0 && (
              <Button
                variant="outline"
                onClick={handleBack}
                className="flex-1 border-linear-border"
              >
                <ArrowLeft className="h-4 w-4 mr-2" />
                Back
              </Button>
            )}
            
            {currentStepIndex < STEPS.length - 1 ? (
              <Button
                onClick={handleNext}
                disabled={
                  (currentStep === 'weight' && !formData.weight) ||
                  (currentStep === 'measurements' && formData.method !== 'simple' && 
                    ((formData.method === 'navy' && (!formData.waist || !formData.neck)) ||
                     (formData.method === '3-site' && profile.gender === 'male' && 
                      (!formData.chest || !formData.abdominal || !formData.thigh))))
                }
                className={`flex-1 bg-linear-purple hover:bg-linear-purple/90 text-white transition-all ${
                  currentStep === 'weight' && formData.weight
                    ? 'animate-glow-pulse' 
                    : ''
                }`}
              >
                Next
                <ArrowRight className="h-4 w-4 ml-2" />
              </Button>
            ) : (
              <Button
                onClick={handleSubmit}
                disabled={isSubmitting || !formData.weight}
                className="flex-1 bg-linear-purple hover:bg-linear-purple/90 text-white"
              >
                {isSubmitting ? (
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white" />
                ) : (
                  <>
                    <Check className="h-4 w-4 mr-2" />
                    Save Entry
                  </>
                )}
              </Button>
            )}
          </div>
        </div>
      </div>

      {/* Exit Confirmation Dialog */}
      <Dialog open={showExitDialog} onOpenChange={setShowExitDialog}>
        <DialogContent className="bg-linear-card border-linear-border max-w-sm mx-4">
          <DialogHeader>
            <DialogTitle className="text-linear-text">Discard changes?</DialogTitle>
          </DialogHeader>
          <p className="text-linear-text-secondary">
            You have unsaved data. Are you sure you want to exit?
          </p>
          <div className="flex gap-3 mt-6">
            <Button
              variant="outline"
              onClick={() => setShowExitDialog(false)}
              className="flex-1 border-linear-border"
            >
              Keep Editing
            </Button>
            <Button
              onClick={() => router.push('/dashboard')}
              className="flex-1 bg-red-500 hover:bg-red-600 text-white"
            >
              Discard
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Weight Modal */}
      <Dialog open={showWeightModal} onOpenChange={setShowWeightModal}>
        <DialogContent className="bg-linear-card border-linear-border max-w-md">
          <DialogHeader>
            <DialogTitle className="text-linear-text text-center">Set Weight</DialogTitle>
          </DialogHeader>
          {/* Direct input option for mobile */}
          <div className="mb-4">
            <Input
              type="number"
              inputMode="decimal"
              step="0.1"
              placeholder={`Enter weight in ${formData.weight_unit}`}
              value={formData.weight}
              onChange={(e) => setFormData(prev => ({ ...prev, weight: e.target.value }))}
              className="text-center text-2xl font-bold h-14 bg-linear-bg border-linear-border"
              autoFocus
            />
          </div>
          <div className="text-center text-sm text-linear-text-secondary mb-4">
            Or use the wheel picker below
          </div>
          <div className="py-8">
            <WeightWheelPicker
              weight={parseFloat(formData.weight) || 70}
              unit={formData.weight_unit}
              onWeightChange={(weight) => {
                setFormData(prev => ({ ...prev, weight: weight.toFixed(1) }))
              }}
            />
          </div>
          <div className="flex gap-3">
            <Button
              variant="outline"
              onClick={() => setShowWeightModal(false)}
              className="flex-1 border-linear-border"
            >
              Cancel
            </Button>
            <Button
              onClick={() => {
                setShowWeightModal(false)
              }}
              className="flex-1 bg-linear-purple hover:bg-linear-purple/80"
            >
              Save
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Body Fat Modal */}
      <Dialog open={showBodyFatModal} onOpenChange={setShowBodyFatModal}>
        <DialogContent className="bg-linear-card border-linear-border max-w-md">
          <DialogHeader>
            <DialogTitle className="text-linear-text text-center">Set Body Fat %</DialogTitle>
          </DialogHeader>
          <div className="py-8">
            <BodyFatWheelPicker
              bodyFat={formData.body_fat_percentage || 20}
              onBodyFatChange={(bf) => {
                setFormData(prev => ({ ...prev, body_fat_percentage: bf }))
              }}
            />
          </div>
          <div className="flex gap-3">
            <Button
              variant="outline"
              onClick={() => setShowBodyFatModal(false)}
              className="flex-1 border-linear-border"
            >
              Cancel
            </Button>
            <Button
              onClick={() => {
                setShowBodyFatModal(false)
              }}
              className="flex-1 bg-linear-purple hover:bg-linear-purple/80"
            >
              Save
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}
