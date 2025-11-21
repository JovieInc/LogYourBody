'use client'

import React, { createContext, useContext, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from './ClerkAuthContext'
import { formatDateForDB } from '@/utils/date-utils'

export interface DexaScan {
  id?: string
  date: string
  weight?: number
  weight_unit?: 'kg' | 'lbs'
  body_fat_percentage?: number
  muscle_mass?: number
  bone_mass?: number
  source?: string
  [key: string]: unknown
}

export interface OnboardingData {
  // DEXA scan data
  weight?: number
  bodyFatPercentage?: number
  leanMass?: number
  fatMass?: number
  boneMass?: number
  scanDate?: string

  // Multiple scans data
  extractedScans?: DexaScan[]
  scanCount?: number
  filename?: string
  confirmedScans?: DexaScan[]
  selectedScanCount?: number

  // Profile data
  fullName?: string
  dateOfBirth?: string
  height?: number
  gender?: 'male' | 'female'

  // Settings
  notificationsEnabled?: boolean
}

interface OnboardingContextType {
  currentStep: number
  totalSteps: number
  data: OnboardingData
  updateData: (newData: Partial<OnboardingData>) => void
  nextStep: () => void
  previousStep: () => void
  completeOnboarding: () => Promise<void>
  isLoading: boolean
}

const OnboardingContext = createContext<OnboardingContextType | undefined>(undefined)

export function OnboardingProvider({ children }: { children: React.ReactNode }) {
  const router = useRouter()
  const { user } = useAuth()
  const [currentStep, setCurrentStep] = useState(1)
  const [data, setData] = useState<OnboardingData>({})
  const [isLoading, setIsLoading] = useState(false)

  const totalSteps = 6

  const updateData = useCallback((newData: Partial<OnboardingData>) => {
    setData(prev => ({ ...prev, ...newData }))
  }, [])

  const nextStep = useCallback(() => {
    if (currentStep < totalSteps) {
      setCurrentStep(prev => prev + 1)
    }
  }, [currentStep, totalSteps])

  const previousStep = useCallback(() => {
    if (currentStep > 1) {
      setCurrentStep(prev => prev - 1)
    }
  }, [currentStep])

  const completeOnboarding = useCallback(async () => {
    if (!user) return

    // Validate data before submission to avoid constraint violations
    if (data.height) {
      // Height should be between 12 and 96 inches for 'ft' unit
      if (data.height < 12 || data.height > 96) {
        const { toast } = await import('@/hooks/use-toast')
        toast({
          title: 'Invalid height',
          description: 'Height must be between 1ft and 8ft',
          variant: 'destructive',
        })
        return
      }
    }

    if (data.bodyFatPercentage) {
      // Body fat should be between 0 and 70%
      if (data.bodyFatPercentage < 0 || data.bodyFatPercentage > 70) {
        const { toast } = await import('@/hooks/use-toast')
        toast({
          title: 'Invalid body fat percentage',
          description: 'Body fat percentage must be between 0% and 70%',
          variant: 'destructive',
        })
        return
      }
    }

    setIsLoading(true)
    try {
      // Save profile data
      const { createClient } = await import('@/lib/supabase/client')
      const supabase = createClient()
      const primaryEmail = user.primaryEmailAddress?.emailAddress
        ?? user.emailAddresses?.[0]?.emailAddress

      // Update user profile
      const { error: profileError } = await supabase
        .from('profiles')
        .upsert({
          id: user.id,
          email: primaryEmail || '', // Include email from auth user
          full_name: data.fullName,
          date_of_birth: data.dateOfBirth,
          height: data.height,
          height_unit: 'ft', // Heights in inches use 'ft' unit per database constraint
          gender: data.gender,
          onboarding_completed: true,
          updated_at: new Date().toISOString()
        })

      if (profileError) throw profileError

      // Save body metrics - either multiple scans or single entry
      if (data.confirmedScans && data.confirmedScans.length > 0) {
        // Multiple scans from PDF
        const metricsToInsert = data.confirmedScans.map(scan => ({
          user_id: user.id,
          date: formatDateForDB(scan.date),
          weight: typeof scan.weight === 'number'
            ? (scan.weight_unit === 'lbs' ? scan.weight * 0.453592 : scan.weight)
            : undefined, // Convert to kg when weight is present
          weight_unit: 'kg',
          body_fat_percentage: scan.body_fat_percentage || null,
          body_fat_method: 'dexa',
          bone_mass: scan.bone_mass ? (scan.weight_unit === 'lbs' ? scan.bone_mass * 0.453592 : scan.bone_mass) : null, // Convert to kg if needed
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }))

        const { error: metricsError } = await supabase
          .from('body_metrics')
          .insert(metricsToInsert)

        if (metricsError) throw metricsError
      } else if (data.weight && data.bodyFatPercentage) {
        // Single entry (manual or single scan)
        // Convert weight to kg for storage (database expects kg when weight_unit is 'kg')
        const weightInKg = data.weight * 0.453592 // Convert lbs to kg

        const { error: metricsError } = await supabase
          .from('body_metrics')
          .insert({
            user_id: user.id,
            date: data.scanDate ? formatDateForDB(data.scanDate) : formatDateForDB(new Date()),
            weight: weightInKg,
            weight_unit: 'kg',
            body_fat_percentage: data.bodyFatPercentage,
            body_fat_method: 'dexa',
            bone_mass: data.boneMass ? data.boneMass * 0.453592 : null, // Convert to kg if present
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
          })

        if (metricsError) throw metricsError
      }

      // Navigate to dashboard
      router.push('/dashboard')
    } catch (error) {
      console.error('Error completing onboarding:', error)
      // Show error to user
      const errorMessage = error instanceof Error ? error.message : 'Failed to complete onboarding'
      // Import toast dynamically to avoid issues
      const { toast } = await import('@/hooks/use-toast')
      toast({
        title: 'Error',
        description: errorMessage,
        variant: 'destructive',
      })
    } finally {
      setIsLoading(false)
    }
  }, [user, data, router])

  return (
    <OnboardingContext.Provider
      value={{
        currentStep,
        totalSteps,
        data,
        updateData,
        nextStep,
        previousStep,
        completeOnboarding,
        isLoading
      }}
    >
      {children}
    </OnboardingContext.Provider>
  )
}

export function useOnboarding() {
  const context = useContext(OnboardingContext)
  if (context === undefined) {
    throw new Error('useOnboarding must be used within an OnboardingProvider')
  }
  return context
}
