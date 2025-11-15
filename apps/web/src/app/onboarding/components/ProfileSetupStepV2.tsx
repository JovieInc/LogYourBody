'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
// import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group' // Not used
import { useOnboarding } from '@/contexts/OnboardingContext'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { DateWheelPicker, HeightWheelPicker } from '@/components/ui/wheel-picker'
import { format } from 'date-fns'
import { motion, AnimatePresence } from 'framer-motion'
import { ArrowLeft, ArrowRight, Calendar, Ruler, User, UserCheck, Users } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useMediaQuery } from '@/hooks/use-media-query'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'

type ProfileStep = 'name' | 'dob' | 'height' | 'gender'

const PROFILE_STEPS: ProfileStep[] = ['name', 'dob', 'height', 'gender']

export function ProfileSetupStepV2() {
  const { data, updateData, nextStep, previousStep } = useOnboarding()
  const { user } = useAuth()
  const isMobile = useMediaQuery('(max-width: 768px)')

  const [currentProfileStep, setCurrentProfileStep] = useState<ProfileStep>('name')

  const initialFullName = data.fullName || ''
  const initialFirstNameFromFull = initialFullName.trim().split(/\s+/)[0] || ''
  const initialLastNameFromFull = initialFullName.trim().split(/\s+/).slice(1).join(' ')

  const clerkFirstName = (user as { firstName?: string } | null)?.firstName || ''
  const clerkLastName = (user as { lastName?: string } | null)?.lastName || ''

  const [formData, setFormData] = useState({
    firstName: initialFullName ? initialFirstNameFromFull : clerkFirstName,
    lastName: initialFullName ? initialLastNameFromFull : clerkLastName,
    dateOfBirth: data.dateOfBirth || '',
    dateOfBirthDate: data.dateOfBirth ? new Date(data.dateOfBirth) : new Date(1990, 0, 1),
    height: data.height || 71, // Default 5'11" in inches
    heightFeet: Math.floor((data.height || 71) / 12),
    heightInches: (data.height || 71) % 12,
    gender: data.gender || ''
  })

  const currentStepIndex = PROFILE_STEPS.indexOf(currentProfileStep)
  const progress = ((currentStepIndex + 1) / PROFILE_STEPS.length) * 100

  const handleProfileNext = () => {
    const nextIndex = currentStepIndex + 1
    if (nextIndex < PROFILE_STEPS.length) {
      setCurrentProfileStep(PROFILE_STEPS[nextIndex])
    } else {
      // Save data and go to next onboarding step
      updateData({
        fullName: `${formData.firstName} ${formData.lastName}`.trim(),
        dateOfBirth: formData.dateOfBirth,
        height: formData.height,
        gender: formData.gender as 'male' | 'female'
      })
      nextStep()
    }
  }

  const handleProfileBack = () => {
    const prevIndex = currentStepIndex - 1
    if (prevIndex >= 0) {
      setCurrentProfileStep(PROFILE_STEPS[prevIndex])
    } else {
      previousStep()
    }
  }

  const isCurrentStepValid = () => {
    switch (currentProfileStep) {
      case 'name':
        return formData.firstName.trim().length > 0 && formData.lastName.trim().length > 0
      case 'dob':
        return formData.dateOfBirth.length > 0
      case 'height':
        return formData.height > 0
      case 'gender':
        return formData.gender.length > 0
      default:
        return false
    }
  }

  // Generate year options for desktop
  const currentYear = new Date().getFullYear()
  const years = Array.from({ length: 100 }, (_, i) => currentYear - i - 10)
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ]
  const days = Array.from({ length: 31 }, (_, i) => i + 1)

  const stepContent = {
    name: {
      icon: User,
      title: "What's your name?",
      description: "This helps personalize your experience"
    },
    dob: {
      icon: Calendar,
      title: "When were you born?",
      description: "Used to calculate age-related metrics"
    },
    height: {
      icon: Ruler,
      title: "How tall are you?",
      description: "Used to calculate BMI and other body metrics"
    },
    gender: {
      icon: Users,
      title: "Select your biological sex",
      description: "Used for accurate body composition calculations"
    }
  }

  const currentContent = stepContent[currentProfileStep]
  const StepIcon = currentContent.icon

  return (
    <Card className="bg-linear-card border-linear-border max-h-[85vh] flex flex-col">
      <CardHeader className="pb-4 flex-shrink-0">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 rounded-lg bg-linear-purple/10 flex items-center justify-center">
              <StepIcon className="h-5 w-5 text-linear-text" />
            </div>
            <div>
              <CardTitle className="text-linear-text">{currentContent.title}</CardTitle>
              <CardDescription className="text-linear-text-secondary">
                {currentContent.description}
              </CardDescription>
            </div>
          </div>
          <span className="text-sm text-linear-text-tertiary">
            {currentStepIndex + 1} of {PROFILE_STEPS.length}
          </span>
        </div>
        <div className="w-full bg-linear-border rounded-full h-2">
          <div
            className="bg-linear-purple h-2 rounded-full transition-all duration-300"
            style={{ width: `${progress}%` }}
          />
        </div>
      </CardHeader>

      <CardContent className="flex-1 overflow-y-auto">
        <AnimatePresence mode="wait">
          <motion.div
            key={currentProfileStep}
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            transition={{ duration: 0.2 }}
            className="space-y-6"
          >
            {/* Name Step */}
            {currentProfileStep === 'name' && (
              <div className="space-y-4 py-8">
                <div className={cn("grid gap-4", isMobile ? "grid-cols-1" : "grid-cols-2")}
                >
                  <div className="space-y-2">
                    <Label htmlFor="firstName" className="text-linear-text-secondary text-sm">
                      First name
                    </Label>
                    <Input
                      id="firstName"
                      value={formData.firstName}
                      onChange={(e) => setFormData(prev => ({ ...prev, firstName: e.target.value }))}
                      className={cn(
                        "bg-linear-bg border-linear-border text-linear-text",
                        isMobile ? "text-base h-12" : "text-lg h-12"
                      )}
                      placeholder="First name"
                      autoFocus
                      onKeyPress={(e) => {
                        if (e.key === 'Enter' && isCurrentStepValid()) {
                          handleProfileNext()
                        }
                      }}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="lastName" className="text-linear-text-secondary text-sm">
                      Last name
                    </Label>
                    <Input
                      id="lastName"
                      value={formData.lastName}
                      onChange={(e) => setFormData(prev => ({ ...prev, lastName: e.target.value }))}
                      className={cn(
                        "bg-linear-bg border-linear-border text-linear-text",
                        isMobile ? "text-base h-12" : "text-lg h-12"
                      )}
                      placeholder="Last name"
                      onKeyPress={(e) => {
                        if (e.key === 'Enter' && isCurrentStepValid()) {
                          handleProfileNext()
                        }
                      }}
                    />
                  </div>
                </div>

                <p className="text-center text-sm text-linear-text-tertiary">
                  {isMobile ? "Tap Next to continue" : "Press Enter or click Next to continue"}
                </p>
              </div>
            )}

            {/* Date of Birth Step */}
            {currentProfileStep === 'dob' && (
              <div className="space-y-4 py-4">
                {isMobile ? (
                  <DateWheelPicker
                    date={formData.dateOfBirthDate}
                    onDateChange={(date) => {
                      setFormData(prev => ({
                        ...prev,
                        dateOfBirthDate: date,
                        dateOfBirth: format(date, 'yyyy-MM-dd')
                      }))
                    }}
                    className="bg-linear-bg rounded-lg"
                  />
                ) : (
                  <div className="grid grid-cols-3 gap-4">
                    <div className="space-y-2">
                      <Label className="text-linear-text">Month</Label>
                      <Select
                        value={formData.dateOfBirthDate.getMonth().toString()}
                        onValueChange={(value) => {
                          const newDate = new Date(formData.dateOfBirthDate)
                          newDate.setMonth(parseInt(value))
                          setFormData(prev => ({
                            ...prev,
                            dateOfBirthDate: newDate,
                            dateOfBirth: format(newDate, 'yyyy-MM-dd')
                          }))
                        }}
                      >
                        <SelectTrigger className="bg-linear-bg border-linear-border">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {months.map((month, index) => (
                            <SelectItem key={month} value={index.toString()}>
                              {month}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    <div className="space-y-2">
                      <Label className="text-linear-text">Day</Label>
                      <Select
                        value={formData.dateOfBirthDate.getDate().toString()}
                        onValueChange={(value) => {
                          const newDate = new Date(formData.dateOfBirthDate)
                          newDate.setDate(parseInt(value))
                          setFormData(prev => ({
                            ...prev,
                            dateOfBirthDate: newDate,
                            dateOfBirth: format(newDate, 'yyyy-MM-dd')
                          }))
                        }}
                      >
                        <SelectTrigger className="bg-linear-bg border-linear-border">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {days.map(day => (
                            <SelectItem key={day} value={day.toString()}>
                              {day}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    <div className="space-y-2">
                      <Label className="text-linear-text">Year</Label>
                      <Select
                        value={formData.dateOfBirthDate.getFullYear().toString()}
                        onValueChange={(value) => {
                          const newDate = new Date(formData.dateOfBirthDate)
                          newDate.setFullYear(parseInt(value))
                          setFormData(prev => ({
                            ...prev,
                            dateOfBirthDate: newDate,
                            dateOfBirth: format(newDate, 'yyyy-MM-dd')
                          }))
                        }}
                      >
                        <SelectTrigger className="bg-linear-bg border-linear-border">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {years.map(year => (
                            <SelectItem key={year} value={year.toString()}>
                              {year}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                )}

                <div className="text-center pt-4">
                  <p className="text-sm text-linear-text-secondary">
                    You are {new Date().getFullYear() - formData.dateOfBirthDate.getFullYear()} years old
                  </p>
                </div>
              </div>
            )}

            {/* Height Step */}
            {currentProfileStep === 'height' && (
              <div className="space-y-4 py-4">
                {isMobile ? (
                  <HeightWheelPicker
                    heightInCm={formData.height * 2.54}
                    units="imperial"
                    onHeightChange={(heightInCm) => {
                      const inches = Math.round(heightInCm / 2.54)
                      setFormData(prev => ({
                        ...prev,
                        height: inches,
                        heightFeet: Math.floor(inches / 12),
                        heightInches: inches % 12
                      }))
                    }}
                    className="bg-linear-bg rounded-lg"
                  />
                ) : (
                  <div className="flex items-center justify-center gap-4">
                    <div className="space-y-2">
                      <Label className="text-linear-text text-center">Feet</Label>
                      <Select
                        value={formData.heightFeet.toString()}
                        onValueChange={(value) => {
                          const feet = parseInt(value)
                          const totalInches = feet * 12 + formData.heightInches
                          setFormData(prev => ({
                            ...prev,
                            heightFeet: feet,
                            height: totalInches
                          }))
                        }}
                      >
                        <SelectTrigger className="bg-linear-bg border-linear-border w-24">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {[3, 4, 5, 6, 7, 8].map(ft => (
                            <SelectItem key={ft} value={ft.toString()}>
                              {ft}'
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    <div className="space-y-2">
                      <Label className="text-linear-text text-center">Inches</Label>
                      <Select
                        value={formData.heightInches.toString()}
                        onValueChange={(value) => {
                          const inches = parseInt(value)
                          const totalInches = formData.heightFeet * 12 + inches
                          setFormData(prev => ({
                            ...prev,
                            heightInches: inches,
                            height: totalInches
                          }))
                        }}
                      >
                        <SelectTrigger className="bg-linear-bg border-linear-border w-24">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {Array.from({ length: 12 }, (_, i) => i).map(inch => (
                            <SelectItem key={inch} value={inch.toString()}>
                              {inch}"
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                )}

                <div className="text-center pt-4">
                  <p className="text-sm text-linear-text-secondary">
                    {formData.heightFeet}'{formData.heightInches}" = {Math.round(formData.height * 2.54)} cm
                  </p>
                </div>
              </div>
            )}

            {/* Gender Step */}
            {currentProfileStep === 'gender' && (
              <div className="space-y-6 py-4">
                <div className="grid grid-cols-2 gap-4">
                  <button
                    onClick={() => setFormData(prev => ({ ...prev, gender: 'male' }))}
                    className={cn(
                      "rounded-xl border-2 transition-all",
                      isMobile ? "p-4" : "p-6",
                      formData.gender === 'male'
                        ? "border-linear-purple bg-linear-purple/10 shadow-lg"
                        : "border-linear-border hover:border-linear-border/70"
                    )}
                  >
                    <div className="space-y-2">
                      <div className={isMobile ? "text-3xl" : "text-4xl"}>♂️</div>
                      <p className="font-medium text-linear-text">Male</p>
                    </div>
                  </button>

                  <button
                    onClick={() => setFormData(prev => ({ ...prev, gender: 'female' }))}
                    className={cn(
                      "rounded-xl border-2 transition-all",
                      isMobile ? "p-4" : "p-6",
                      formData.gender === 'female'
                        ? "border-linear-purple bg-linear-purple/10 shadow-lg"
                        : "border-linear-border hover:border-linear-border/70"
                    )}
                  >
                    <div className="space-y-2">
                      <div className={isMobile ? "text-3xl" : "text-4xl"}>♀️</div>
                      <p className="font-medium text-linear-text">Female</p>
                    </div>
                  </button>
                </div>

                <p className="text-center text-xs text-linear-text-tertiary px-4">
                  This information is used for accurate body composition calculations
                </p>
              </div>
            )}
          </motion.div>
        </AnimatePresence>

        {/* Navigation */}
        <div className="flex gap-3 pt-8 mt-auto">
          <Button
            variant="ghost"
            onClick={handleProfileBack}
            className="flex items-center"
          >
            <ArrowLeft className="h-4 w-4 mr-2" />
            Back
          </Button>

          <Button
            onClick={handleProfileNext}
            disabled={!isCurrentStepValid()}
            className={cn(
              "ml-auto flex items-center transition-all",
              isCurrentStepValid()
                ? "bg-linear-purple hover:bg-linear-purple/90 text-white animate-glow-pulse"
                : "bg-gray-300 text-gray-500"
            )}
          >
            {currentStepIndex === PROFILE_STEPS.length - 1 ? (
              <>
                Complete
                <UserCheck className="h-4 w-4 ml-2" />
              </>
            ) : (
              <>
                Next
                <ArrowRight className="h-4 w-4 ml-2" />
              </>
            )}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}