'use client'

import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter } from 'next/navigation'
import { useEffect, useState, useCallback, useRef } from 'react'
import { Button } from '@/components/ui/button'
import { getProfile, updateProfile } from '@/lib/supabase/profile'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { toast } from '@/hooks/use-toast'
import {
  Loader2,
  ArrowLeft,
  Camera,
  Calendar,
  Ruler,
  Check
} from 'lucide-react'
import Link from 'next/link'
import { UserProfile } from '@/types/body-metrics'
import { HeightWheelPicker, DateWheelPicker } from '@/components/ui/wheel-picker'
import { format, parseISO } from 'date-fns'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'

export default function ProfileSettingsPage() {
  const { user, loading, uploadProfileImage } = useAuth()
  const router = useRouter()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [isSaving, setIsSaving] = useState(false)
  const [isUploadingAvatar, setIsUploadingAvatar] = useState(false)
  const [lastSaved, setLastSaved] = useState<Date | null>(null)
  const [showHeightModal, setShowHeightModal] = useState(false)
  const [showDOBModal, setShowDOBModal] = useState(false)
  const [nameFields, setNameFields] = useState<{ firstName: string; lastName: string }>({
    firstName: '',
    lastName: ''
  })

  const [profile, setProfile] = useState<Partial<UserProfile>>({
    email: '',
    full_name: '',
    username: '',
    height: 71,
    height_unit: 'ft',
    gender: 'male',
    date_of_birth: '',
    bio: '',
    activity_level: 'moderately_active'
  })

  // For wheel pickers
  const [heightInCm, setHeightInCm] = useState(180) // Default height in cm
  const [dateOfBirthDate, setDateOfBirthDate] = useState(new Date(1990, 0, 1)) // Default date

  // Auto-save function
  const saveProfile = useCallback(async (profileData: Partial<UserProfile>) => {
    if (!user) return

    setIsSaving(true)
    try {
      await updateProfile(user.id, profileData)
      setLastSaved(new Date())

      // Show subtle feedback instead of toast for auto-save
      // Only show toast for errors
    } catch {
      toast({
        title: "Error",
        description: "Failed to save changes. Please try again.",
        variant: "destructive"
      })
    } finally {
      setIsSaving(false)
    }
  }, [user])

  // Debounced auto-save (custom implementation to avoid lodash)
  const timeoutRef = useRef<NodeJS.Timeout | undefined>(undefined)

  const debouncedSave = useCallback((profileData: Partial<UserProfile>) => {
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current)
    }
    timeoutRef.current = setTimeout(() => {
      saveProfile(profileData)
    }, 1000)
  }, [saveProfile])

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current)
      }
    }
  }, [])

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin')
    }
  }, [user, loading, router])

  // Load profile data
  useEffect(() => {
    if (user) {
      getProfile(user.id).then((profileData) => {
        if (profileData) {
          const normalizedGender = profileData.gender === 'female' ? 'female' : 'male'
          setProfile({
            email: profileData.email,
            full_name: profileData.full_name || '',
            username: profileData.username || '',
            height: profileData.height || 71,
            height_unit: profileData.height_unit || 'ft',
            gender: normalizedGender,
            date_of_birth: profileData.date_of_birth || '',
            bio: profileData.bio || '',
            activity_level: profileData.activity_level || 'moderately_active',
            avatar_url: profileData.avatar_url
          })
        }
      })
    }
  }, [user])

  // Initialize first/last name fields from profile full_name, Clerk user, or email
  useEffect(() => {
    if (!user) return

    const clerkUser = user as { firstName?: string; lastName?: string; email?: string } | null

    const existingFullName = (profile.full_name || '').trim()
    const clerkFirstName = (clerkUser?.firstName || '').trim()
    const clerkLastName = (clerkUser?.lastName || '').trim()

    let sourceFullName = existingFullName
    if (!sourceFullName && (clerkFirstName || clerkLastName)) {
      sourceFullName = `${clerkFirstName} ${clerkLastName}`.trim()
    }

    if (!sourceFullName) {
      const emailSource = (profile.email || clerkUser?.email || '').split('@')[0] || ''
      sourceFullName = emailSource
    }

    const parts = sourceFullName.trim().split(/\s+/)
    const firstName = parts[0] || ''
    const lastName = parts.slice(1).join(' ')

    setNameFields({ firstName, lastName })
  }, [profile.full_name, profile.email, user])

  // Initialize height in cm from profile
  useEffect(() => {
    if (profile.height && profile.height_unit) {
      if (profile.height_unit === 'cm') {
        setHeightInCm(profile.height)
      } else {
        // Convert feet/inches to cm
        const totalInches = profile.height
        setHeightInCm(Math.round(totalInches * 2.54))
      }
    }
  }, [profile.height, profile.height_unit])

  // Initialize date from profile
  useEffect(() => {
    if (profile.date_of_birth) {
      try {
        const date = parseISO(profile.date_of_birth)
        setDateOfBirthDate(date)
      } catch {
        // Invalid date
      }
    }
  }, [profile.date_of_birth])

  const updateLocalProfile = useCallback((updates: Partial<UserProfile>) => {
    const newProfile = { ...profile, ...updates }
    setProfile(newProfile)
    debouncedSave(newProfile)
  }, [profile, debouncedSave])

  const handleAvatarUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return

    setIsUploadingAvatar(true)

    try {
      const { imageUrl, error } = await uploadProfileImage(file)

      if (error) {
        throw error
      }

      if (imageUrl) {
        // Update Supabase profile with new Clerk imageUrl
        await updateLocalProfile({ avatar_url: imageUrl })

        toast({
          title: "Success",
          description: "Profile picture updated successfully",
        })
      }
    } catch (error) {
      toast({
        title: "Error",
        description: error instanceof Error ? error.message : "Failed to upload profile picture",
        variant: "destructive"
      })
    } finally {
      setIsUploadingAvatar(false)
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-linear-bg">
        <Loader2 className="h-8 w-8 animate-spin text-linear-text-secondary" />
      </div>
    )
  }

  if (!user) {
    return null
  }

  const primaryEmail = user.primaryEmailAddress?.emailAddress
    ?? user.emailAddresses?.[0]?.emailAddress
    ?? ''

  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map(word => word[0])
      .join('')
      .toUpperCase()
      .slice(0, 2)
  }

  const formatHeight = () => {
    if (!profile.height) return 'Not set'

    if (profile.height_unit === 'cm') {
      return `${profile.height} cm`
    } else {
      const feet = Math.floor(profile.height / 12)
      const inches = profile.height % 12
      return `${feet}'${inches}"`
    }
  }

  const formatDOB = () => {
    if (!profile.date_of_birth) return 'Not set'
    try {
      const date = parseISO(profile.date_of_birth)
      return format(date, 'MMM d, yyyy')
    } catch {
      return 'Not set'
    }
  }

  const calculateAge = () => {
    if (!profile.date_of_birth) return null
    try {
      const date = parseISO(profile.date_of_birth)
      const today = new Date()
      let age = today.getFullYear() - date.getFullYear()
      const monthDiff = today.getMonth() - date.getMonth()
      if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < date.getDate())) {
        age--
      }
      return age
    } catch {
      return null
    }
  }

  return (
    <div className="min-h-screen bg-linear-bg">
      {/* Header */}
      <header className="bg-linear-card shadow-sm border-b border-linear-border sticky top-0 z-10">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/settings">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-xl font-bold text-linear-text">Profile</h1>
            </div>
            <div className="text-sm text-linear-text-secondary">
              {isSaving ? (
                <span className="flex items-center gap-2">
                  <Loader2 className="h-3 w-3 animate-spin" />
                  Saving...
                </span>
              ) : lastSaved ? (
                <span className="flex items-center gap-2">
                  <Check className="h-3 w-3" />
                  Saved
                </span>
              ) : null}
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6 max-w-2xl space-y-6">
        {/* Basic Profile - Static Information */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Basic Information</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Your personal details and account information
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Profile Picture and Name Section */}
            <div className="flex items-start gap-6">
              <div className="relative group">
                <Avatar className="h-20 w-20">
                  <AvatarImage src={user.imageUrl || profile.avatar_url} />
                  <AvatarFallback className="bg-linear-border text-linear-text-secondary text-lg">
                    {getInitials(
                      (nameFields.firstName || nameFields.lastName)
                        ? `${nameFields.firstName} ${nameFields.lastName}`
                        : profile.full_name || primaryEmail || 'U'
                    )}
                  </AvatarFallback>
                </Avatar>
                <button
                  type="button"
                  disabled={isUploadingAvatar}
                  className="absolute bottom-0 right-0 h-8 w-8 rounded-full bg-linear-card border border-linear-border opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center hover:bg-linear-bg disabled:opacity-50"
                  onClick={() => fileInputRef.current?.click()}
                >
                  {isUploadingAvatar ? (
                    <Loader2 className="h-4 w-4 text-linear-text-secondary animate-spin" />
                  ) : (
                    <Camera className="h-4 w-4 text-linear-text-secondary" />
                  )}
                </button>
                {/* Hidden file input */}
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={handleAvatarUpload}
                />
              </div>

              <div className="flex-1 space-y-4">
                <div className="space-y-2">
                  <div className="grid gap-4 grid-cols-1 sm:grid-cols-2">
                    <div className="space-y-2">
                      <Label htmlFor="firstName" className="text-linear-text-secondary text-sm">First Name</Label>
                      <Input
                        id="firstName"
                        value={nameFields.firstName}
                        onChange={(e) => {
                          const updated = { ...nameFields, firstName: e.target.value }
                          setNameFields(updated)
                          updateLocalProfile({ full_name: `${updated.firstName} ${updated.lastName}`.trim() })
                        }}
                        className="bg-linear-bg border-linear-border text-linear-text focus:border-linear-text-tertiary"
                        placeholder="John"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="lastName" className="text-linear-text-secondary text-sm">Last Name</Label>
                      <Input
                        id="lastName"
                        value={nameFields.lastName}
                        onChange={(e) => {
                          const updated = { ...nameFields, lastName: e.target.value }
                          setNameFields(updated)
                          updateLocalProfile({ full_name: `${updated.firstName} ${updated.lastName}`.trim() })
                        }}
                        className="bg-linear-bg border-linear-border text-linear-text focus:border-linear-text-tertiary"
                        placeholder="Doe"
                      />
                    </div>
                  </div>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="email" className="text-linear-text-secondary text-sm">Email</Label>
                  <Input
                    id="email"
                    value={profile.email || primaryEmail || ''}
                    disabled
                    className="bg-linear-bg border-linear-border text-linear-text-tertiary"
                  />
                </div>
              </div>
            </div>

            {/* Biological Sex - inline tabs */}
            <div className="space-y-2">
              <Label className="text-linear-text-secondary text-sm">Biological Sex</Label>
              <div className="inline-flex bg-linear-bg rounded-md p-0.5">
                <button
                  onClick={() => updateLocalProfile({ gender: 'male' })}
                  className={`px-4 py-1.5 text-sm font-medium rounded transition-all ${profile.gender === 'male'
                    ? 'bg-linear-card text-linear-text shadow-sm'
                    : 'text-linear-text-tertiary hover:text-linear-text-secondary'
                    }`}
                >
                  Male
                </button>
                <button
                  onClick={() => updateLocalProfile({ gender: 'female' })}
                  className={`px-4 py-1.5 text-sm font-medium rounded transition-all ${profile.gender === 'female'
                    ? 'bg-linear-card text-linear-text shadow-sm'
                    : 'text-linear-text-tertiary hover:text-linear-text-secondary'
                    }`}
                >
                  Female
                </button>
              </div>
            </div>

            {/* Height and Age Row */}
            <div className="grid grid-cols-2 gap-4">
              {/* Height */}
              <div className="space-y-2">
                <Label className="text-linear-text-secondary text-sm">Height</Label>
                <button
                  onClick={() => setShowHeightModal(true)}
                  className="w-full bg-linear-bg border border-linear-border rounded-md px-3 py-2 text-linear-text hover:border-linear-text-tertiary transition-colors flex items-center justify-between group"
                >
                  <span className="font-medium">{formatHeight()}</span>
                  <Ruler className="h-4 w-4 text-linear-text-tertiary group-hover:text-linear-text-secondary transition-colors" />
                </button>
              </div>

              {/* Date of Birth / Age */}
              <div className="space-y-2">
                <Label className="text-linear-text-secondary text-sm">Age</Label>
                <button
                  onClick={() => setShowDOBModal(true)}
                  className="w-full bg-linear-bg border border-linear-border rounded-md px-3 py-2 text-linear-text hover:border-linear-text-tertiary transition-colors flex items-center justify-between group"
                  title={formatDOB()}
                >
                  <span className="font-medium">{calculateAge() ? `${calculateAge()} years` : 'Not set'}</span>
                  <Calendar className="h-4 w-4 text-linear-text-tertiary group-hover:text-linear-text-secondary transition-colors" />
                </button>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Activity & Lifestyle - Semi-static */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Activity & Lifestyle</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Your typical activity patterns
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="activityLevel" className="text-linear-text-secondary text-sm">Activity Level</Label>
              <Select
                value={profile.activity_level || ''}
                onValueChange={(value) => updateLocalProfile({ activity_level: value as UserProfile['activity_level'] })}
              >
                <SelectTrigger className="bg-linear-bg border-linear-border text-linear-text hover:border-linear-text-tertiary">
                  <SelectValue placeholder="Select activity level" />
                </SelectTrigger>
                <SelectContent className="bg-linear-card border-linear-border">
                  <SelectItem value="sedentary" className="hover:bg-linear-bg">Sedentary (little to no exercise)</SelectItem>
                  <SelectItem value="lightly_active" className="hover:bg-linear-bg">Lightly Active (1-3 days/week)</SelectItem>
                  <SelectItem value="moderately_active" className="hover:bg-linear-bg">Moderately Active (3-5 days/week)</SelectItem>
                  <SelectItem value="very_active" className="hover:bg-linear-bg">Very Active (6-7 days/week)</SelectItem>
                  <SelectItem value="extremely_active" className="hover:bg-linear-bg">Extremely Active (2x per day)</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="bio" className="text-linear-text-secondary text-sm">Bio</Label>
              <textarea
                id="bio"
                value={profile.bio || ''}
                onChange={(e) => updateLocalProfile({ bio: e.target.value })}
                className="w-full px-3 py-2 bg-linear-bg border border-linear-border text-linear-text rounded-md resize-none hover:border-linear-text-tertiary focus:border-linear-text-tertiary focus:outline-none transition-colors"
                placeholder="Share your fitness goals and journey..."
                rows={3}
              />
            </div>
          </CardContent>
        </Card>

        {/* Additional Options */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Additional Options</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="username" className="text-linear-text-secondary text-sm">Username</Label>
              <Input
                id="username"
                value={profile.username || ''}
                onChange={(e) => updateLocalProfile({ username: e.target.value })}
                className="bg-linear-bg border-linear-border text-linear-text focus:border-linear-text-tertiary"
                placeholder="@johndoe"
              />
              <p className="text-xs text-linear-text-tertiary">
                Your unique username for sharing your profile
              </p>
            </div>

            <div className="pt-2">
              <button
                type="button"
                disabled={isUploadingAvatar}
                className="w-full px-4 py-2 border border-linear-border rounded-md text-linear-text-secondary hover:text-linear-text hover:border-linear-text-tertiary transition-colors flex items-center justify-center disabled:opacity-50"
                onClick={() => fileInputRef.current?.click()}
              >
                {isUploadingAvatar ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Uploading...
                  </>
                ) : (
                  <>
                    <Camera className="h-4 w-4 mr-2" />
                    Change Profile Photo
                  </>
                )}
              </button>
            </div>
          </CardContent>
        </Card>
      </main>

      {/* Date of Birth Modal */}
      <Dialog open={showDOBModal} onOpenChange={setShowDOBModal}>
        <DialogContent className="bg-linear-card border-linear-border max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-linear-text text-center">Set Date of Birth</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="text-center py-4">
              <div className="text-2xl font-medium text-linear-text mb-1">
                {format(dateOfBirthDate, 'MMMM d, yyyy')}
              </div>
              <div className="text-sm text-linear-text-tertiary">
                {calculateAge() ? `${calculateAge()} years old` : 'Age will be calculated'}
              </div>
            </div>
            <div className="bg-linear-bg rounded-lg p-4">
              <DateWheelPicker
                date={dateOfBirthDate}
                onDateChange={(date) => {
                  setDateOfBirthDate(date)
                  updateLocalProfile({ date_of_birth: format(date, 'yyyy-MM-dd') })
                }}
                className=""
              />
            </div>
          </div>
          <div className="flex gap-2 mt-6">
            <button
              onClick={() => setShowDOBModal(false)}
              className="flex-1 px-4 py-2 border border-linear-border rounded-md text-linear-text-secondary hover:text-linear-text hover:border-linear-text-tertiary transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={() => setShowDOBModal(false)}
              className="flex-1 px-4 py-2 bg-white/10 rounded-md text-linear-text hover:bg-white/15 transition-colors"
            >
              Done
            </button>
          </div>
        </DialogContent>
      </Dialog >

      {/* Height Modal */}
      < Dialog open={showHeightModal} onOpenChange={setShowHeightModal} >
        <DialogContent className="bg-linear-card border-linear-border max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-linear-text text-center">Set Height</DialogTitle>
          </DialogHeader>
          <div className="space-y-6">
            {/* Unit Toggle */}
            <div className="flex justify-center">
              <div className="inline-flex bg-linear-bg rounded-md p-0.5">
                <button
                  onClick={() => {
                    const newUnit = 'cm'
                    if (profile.height_unit === 'ft') {
                      updateLocalProfile({ height: heightInCm, height_unit: newUnit })
                    } else {
                      updateLocalProfile({ height_unit: newUnit })
                    }
                  }}
                  className={`px-4 py-1.5 text-sm font-medium rounded transition-all ${profile.height_unit === 'cm'
                    ? 'bg-white/10 text-linear-text'
                    : 'text-linear-text-tertiary hover:text-linear-text-secondary'
                    }`}
                >
                  Metric (cm)
                </button>
                <button
                  onClick={() => {
                    const newUnit = 'ft'
                    if (profile.height_unit === 'cm') {
                      const totalInches = Math.round(heightInCm / 2.54)
                      updateLocalProfile({ height: totalInches, height_unit: newUnit })
                    } else {
                      updateLocalProfile({ height_unit: newUnit })
                    }
                  }}
                  className={`px-4 py-1.5 text-sm font-medium rounded transition-all ${profile.height_unit === 'ft'
                    ? 'bg-white/10 text-linear-text'
                    : 'text-linear-text-tertiary hover:text-linear-text-secondary'
                    }`}
                >
                  Imperial (ft/in)
                </button>
              </div>
            </div>

            {/* Height Display */}
            <div className="text-center py-4">
              <div className="text-4xl font-semibold text-linear-text mb-2">
                {formatHeight()}
              </div>
              <div className="text-sm text-linear-text-tertiary">
                {profile.height_unit === 'cm'
                  ? `${Math.floor(heightInCm / 30.48)}'${Math.round((heightInCm % 30.48) / 2.54)}" in imperial`
                  : `${heightInCm} cm in metric`
                }
              </div>
            </div>

            {/* Height Picker */}
            <div className="bg-linear-bg rounded-lg p-4">
              <HeightWheelPicker
                heightInCm={heightInCm}
                units={profile.height_unit === 'ft' ? 'imperial' : 'metric'}
                onHeightChange={(newHeightInCm) => {
                  setHeightInCm(newHeightInCm)
                  // Update profile height based on unit
                  if (profile.height_unit === 'ft') {
                    const totalInches = Math.round(newHeightInCm / 2.54)
                    updateLocalProfile({ height: totalInches })
                  } else {
                    updateLocalProfile({ height: newHeightInCm })
                  }
                }}
                className=""
              />
            </div>
          </div>
          <div className="flex gap-2 mt-6">
            <button
              onClick={() => setShowHeightModal(false)}
              className="flex-1 px-4 py-2 border border-linear-border rounded-md text-linear-text-secondary hover:text-linear-text hover:border-linear-text-tertiary transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={() => setShowHeightModal(false)}
              className="flex-1 px-4 py-2 bg-white/10 rounded-md text-linear-text hover:bg-white/15 transition-colors"
            >
              Done
            </button>
          </div>
        </DialogContent>
      </Dialog >
    </div >
  )
}
