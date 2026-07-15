#!/usr/bin/env tsx

import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'
import { format, subYears } from 'date-fns'
import { getProfileAvatarUrl } from '../src/utils/pravatar-utils'

// Load environment variables
dotenv.config({ path: '.env.local' })

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('❌ Missing required environment variables')
  process.exit(1)
}

// Helper function to generate weight progression
function generateWeightProgression(
  startWeight: number,
  targetWeight: number,
  startDate: Date,
  endDate: Date,
  journeyType: 'loss' | 'gain' | 'maintain' | 'recomp'
) {
  const metrics = []
  const totalDays = Math.floor((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24))
  const weightChange = targetWeight - startWeight
  
  // Generate entries every 2 weeks
  for (let days = 0; days <= totalDays; days += 14) {
    const currentDate = new Date(startDate)
    currentDate.setDate(currentDate.getDate() + days)
    
    let weight = startWeight
    const progress = days / totalDays
    
    if (journeyType === 'loss' || journeyType === 'gain') {
      // Linear progression with some fluctuation
      weight = startWeight + (weightChange * progress) + (Math.random() * 2 - 1)
    } else if (journeyType === 'maintain') {
      // Small fluctuations around target weight
      weight = targetWeight + (Math.random() * 2 - 1)
    } else if (journeyType === 'recomp') {
      // Weight stays similar but body composition changes
      weight = startWeight + (Math.random() * 1 - 0.5)
    }
    
    metrics.push({
      date: format(currentDate, 'yyyy-MM-dd'),
      weight: Math.round(weight * 10) / 10,
      progress
    })
  }
  
  return metrics
}

// Comprehensive user data
const users = [
  {
    email: 'sarah.chen@example.com',
    password: 'password123',
    profile: {
      full_name: 'Sarah Chen',
      username: 'sarahc',
      gender: 'female',
      date_of_birth: '1992-03-15',
      height: 163,
      height_unit: 'cm',
      activity_level: 'moderately_active',
      bio: 'On a weight loss journey. Down 15 lbs so far! Love yoga and hiking.',
      goal_weight: 63.5,
      goal_weight_unit: 'kg',
      goal_body_fat_percentage: null,
      goal_waist_to_hip_ratio: null,
      goal_waist_to_height_ratio: null,
      avatar_url: getProfileAvatarUrl('sarahc', 300),
      settings: {
        units: {
          weight: 'kg',
          height: 'cm',
          measurements: 'cm'
        },
        notifications: {
          daily_reminder: true,
          reminder_time: '08:00',
          weekly_report: true,
          progress_milestones: true
        },
        privacy: {
          public_profile: false,
          show_progress_photos: false
        }
      }
    },
    journey: {
      type: 'loss' as const,
      startWeight: 81.6,
      currentWeight: 74.8,
      startDate: subYears(new Date(), 2),
      bodyFatStart: 35.0,
      bodyFatCurrent: 30.5,
      waistStart: 95,
      waistCurrent: 81,
      hipStart: 110,
      hipCurrent: 102
    },
    progressPhotos: [
      { angle: 'front', daysAgo: 730, note: 'Starting my journey' },
      { angle: 'side', daysAgo: 730, note: 'Day 1' },
      { angle: 'front', daysAgo: 365, note: '1 year progress!' },
      { angle: 'side', daysAgo: 365, note: 'Feeling stronger' },
      { angle: 'front', daysAgo: 180, note: '18 months in' },
      { angle: 'front', daysAgo: 90, note: 'Getting close to goal' },
      { angle: 'side', daysAgo: 90, note: 'Love the changes' },
      { angle: 'front', daysAgo: 30, note: 'Almost there!' }
    ]
  },
  {
    email: 'marcus.johnson@example.com',
    password: 'password123',
    profile: {
      full_name: 'Marcus Johnson',
      username: 'marcusj',
      gender: 'male',
      date_of_birth: '1995-07-22',
      height: 185,
      height_unit: 'cm',
      activity_level: 'very_active',
      bio: 'Powerlifter on a lean bulk. 4 years of training experience.',
      goal_weight: 90.7,
      goal_weight_unit: 'kg',
      goal_body_fat_percentage: null,
      goal_ffmi: null,
      goal_waist_to_hip_ratio: null,
      goal_waist_to_height_ratio: null,
      avatar_url: getProfileAvatarUrl('marcusj', 300),
      settings: {
        units: {
          weight: 'kg',
          height: 'cm',
          measurements: 'cm'
        },
        notifications: {
          daily_reminder: false,
          reminder_time: '18:00',
          weekly_report: true,
          progress_milestones: true
        },
        privacy: {
          public_profile: true,
          show_progress_photos: true
        }
      }
    },
    journey: {
      type: 'gain' as const,
      startWeight: 79.4,
      currentWeight: 86.2,
      startDate: subYears(new Date(), 3),
      bodyFatStart: 12.0,
      bodyFatCurrent: 14.0,
      waistStart: 80,
      waistCurrent: 84,
      hipStart: 95,
      hipCurrent: 99,
      muscleStart: 69.9,
      muscleCurrent: 74.1
    },
    progressPhotos: [
      { angle: 'front', daysAgo: 1095, note: 'Starting strength journey' },
      { angle: 'back', daysAgo: 1095, note: 'Need more back development' },
      { angle: 'front', daysAgo: 730, note: '1 year of training' },
      { angle: 'back', daysAgo: 730, note: 'Back getting wider' },
      { angle: 'side', daysAgo: 730, note: 'Profile shot' },
      { angle: 'front', daysAgo: 365, note: '2 years progress' },
      { angle: 'back', daysAgo: 365, note: 'Lats coming in' },
      { angle: 'front', daysAgo: 180, note: 'Bulk going well' },
      { angle: 'side', daysAgo: 180, note: 'Chest development' },
      { angle: 'front', daysAgo: 30, note: 'Current physique' },
      { angle: 'back', daysAgo: 30, note: 'Back double bicep' }
    ]
  },
  {
    email: 'emily.rodriguez@example.com',
    password: 'password123',
    profile: {
      full_name: 'Emily Rodriguez',
      username: 'emilyr',
      gender: 'female',
      date_of_birth: '1990-11-08',
      height: 170,
      height_unit: 'cm',
      activity_level: 'very_active',
      bio: 'Personal trainer. Maintaining my physique year-round.',
      goal_body_fat_percentage: null,
      goal_waist_to_hip_ratio: null,
      goal_waist_to_height_ratio: null,
      avatar_url: getProfileAvatarUrl('emilyr', 300),
      settings: {
        units: {
          weight: 'lbs',
          height: 'ft',
          measurements: 'in'
        },
        notifications: {
          daily_reminder: true,
          reminder_time: '06:00',
          weekly_report: false,
          progress_milestones: false
        },
        privacy: {
          public_profile: true,
          show_progress_photos: true
        }
      }
    },
    journey: {
      type: 'maintain' as const,
      startWeight: 61.2,
      currentWeight: 61.2,
      startDate: subYears(new Date(), 4),
      bodyFatStart: 22.0,
      bodyFatCurrent: 22.0,
      waistStart: 66,
      waistCurrent: 66,
      hipStart: 94,
      hipCurrent: 94,
      muscleStart: 47.7,
      muscleCurrent: 47.7
    },
    progressPhotos: [
      { angle: 'front', daysAgo: 365, note: 'Maintaining for a year' },
      { angle: 'side', daysAgo: 365, note: 'Consistent physique' },
      { angle: 'front', daysAgo: 180, note: 'Summer shape' },
      { angle: 'back', daysAgo: 180, note: 'Back definition' },
      { angle: 'front', daysAgo: 90, note: 'Fall check-in' },
      { angle: 'front', daysAgo: 30, note: 'Current condition' }
    ]
  },
  {
    email: 'david.kim@example.com',
    password: 'password123',
    profile: {
      full_name: 'David Kim',
      username: 'davidk',
      gender: 'male',
      date_of_birth: '1988-05-30',
      height: 175,
      height_unit: 'cm',
      activity_level: 'lightly_active',
      bio: 'Software engineer getting back in shape. Down 25 lbs!',
      goal_weight: 77.1,
      goal_weight_unit: 'kg',
      goal_body_fat_percentage: null,
      goal_ffmi: null,
      goal_waist_to_hip_ratio: null,
      goal_waist_to_height_ratio: null,
      avatar_url: getProfileAvatarUrl('davidk', 300),
      settings: {
        units: {
          weight: 'lbs',
          height: 'cm',
          measurements: 'cm'
        },
        notifications: {
          daily_reminder: true,
          reminder_time: '19:00',
          weekly_report: true,
          progress_milestones: true
        },
        privacy: {
          public_profile: false,
          show_progress_photos: false
        }
      }
    },
    journey: {
      type: 'loss' as const,
      startWeight: 99.8,
      currentWeight: 88.5,
      startDate: subYears(new Date(), 1.5),
      bodyFatStart: 32.0,
      bodyFatCurrent: 25.5,
      waistStart: 105,
      waistCurrent: 92,
      hipStart: 108,
      hipCurrent: 100
    },
    progressPhotos: [
      { angle: 'front', daysAgo: 548, note: 'Before - time to change' },
      { angle: 'side', daysAgo: 548, note: 'Starting point' },
      { angle: 'front', daysAgo: 365, note: '6 months progress' },
      { angle: 'side', daysAgo: 365, note: 'Belly going down' },
      { angle: 'front', daysAgo: 180, note: '1 year mark' },
      { angle: 'side', daysAgo: 180, note: 'Much better profile' },
      { angle: 'front', daysAgo: 60, note: 'Getting lean!' },
      { angle: 'front', daysAgo: 7, note: 'Current - 25 lbs down!' }
    ]
  },
  {
    email: 'jessica.thompson@example.com',
    password: 'password123',
    profile: {
      full_name: 'Jessica Thompson',
      username: 'jessicat',
      gender: 'female',
      date_of_birth: '1993-09-18',
      height: 168,
      height_unit: 'cm',
      activity_level: 'extremely_active',
      bio: 'CrossFit athlete. Body recomposition in progress!',
      goal_body_fat_percentage: null,
      goal_waist_to_hip_ratio: null,
      goal_waist_to_height_ratio: null,
      avatar_url: getProfileAvatarUrl('jessicat', 300),
      settings: {
        units: {
          weight: 'kg',
          height: 'cm',
          measurements: 'cm'
        },
        notifications: {
          daily_reminder: true,
          reminder_time: '05:30',
          weekly_report: true,
          progress_milestones: true
        },
        privacy: {
          public_profile: true,
          show_progress_photos: true
        }
      }
    },
    journey: {
      type: 'recomp' as const,
      startWeight: 65.8,
      currentWeight: 65.8,
      startDate: subYears(new Date(), 2.5),
      bodyFatStart: 28.0,
      bodyFatCurrent: 23.0,
      waistStart: 75,
      waistCurrent: 68,
      hipStart: 98,
      hipCurrent: 97,
      muscleStart: 47.4,
      muscleCurrent: 50.7
    },
    progressPhotos: [
      { angle: 'front', daysAgo: 912, note: 'Starting CrossFit' },
      { angle: 'side', daysAgo: 912, note: 'Baseline' },
      { angle: 'back', daysAgo: 912, note: 'Need more muscle' },
      { angle: 'front', daysAgo: 730, note: '6 months CF' },
      { angle: 'side', daysAgo: 730, note: 'Getting stronger' },
      { angle: 'front', daysAgo: 548, note: '1 year anniversary' },
      { angle: 'back', daysAgo: 548, note: 'Back gains!' },
      { angle: 'front', daysAgo: 365, note: '18 months' },
      { angle: 'side', daysAgo: 365, note: 'Core development' },
      { angle: 'front', daysAgo: 180, note: '2 years strong' },
      { angle: 'back', daysAgo: 180, note: 'Muscle definition' },
      { angle: 'front', daysAgo: 90, note: 'Competition prep' },
      { angle: 'side', daysAgo: 90, note: 'Stage ready' },
      { angle: 'front', daysAgo: 14, note: 'Current physique' },
      { angle: 'back', daysAgo: 14, note: 'Back double bicep' },
      { angle: 'side', daysAgo: 14, note: 'Side chest' }
    ]
  }
]

async function seedComprehensiveData() {
  console.log('🌱 Creating comprehensive test data...\n')
  
  for (const userData of users) {
    const supabase = createClient(supabaseUrl, supabaseAnonKey)
    
    console.log(`\n📝 Processing ${userData.profile.full_name}...`)
    
    // Try to sign in first (in case user already exists)
    let userId: string | null = null
    const { data: signInData } = await supabase.auth.signInWithPassword({
      email: userData.email,
      password: userData.password
    })
    
    if (signInData?.user) {
      userId = signInData.user.id
      console.log(`✅ Signed in existing user`)
    } else {
      // Create new user
      const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
        email: userData.email,
        password: userData.password,
        options: {
          data: {
            name: userData.profile.full_name
          }
        }
      })
      
      if (signUpError || !signUpData.user) {
        console.error(`❌ Error creating user: ${signUpError?.message}`)
        continue
      }
      
      userId = signUpData.user.id
      console.log(`✅ Created new user`)
    }
    
    // Update profile with comprehensive data
    const { error: profileError } = await supabase
      .from('profiles')
      .update({
        ...userData.profile,
        email_verified: true,
        onboarding_completed: true
      })
      .eq('id', userId)
    
    if (profileError) {
      console.error(`❌ Error updating profile: ${profileError.message}`)
      continue
    }
    console.log(`✅ Updated profile with all settings`)
    
    // Generate and insert weight history
    const weightHistory = generateWeightProgression(
      userData.journey.startWeight,
      userData.journey.currentWeight,
      userData.journey.startDate,
      new Date(),
      userData.journey.type
    )
    
    const metricsToInsert = weightHistory.map((entry, index) => {
      // Calculate body fat and measurements based on progress
      const bfProgress = userData.journey.bodyFatCurrent - userData.journey.bodyFatStart
      const waistProgress = userData.journey.waistCurrent - userData.journey.waistStart
      const hipProgress = userData.journey.hipCurrent - userData.journey.hipStart
      
      const bodyFat = userData.journey.bodyFatStart + (bfProgress * entry.progress)
      const waist = userData.journey.waistStart + (waistProgress * entry.progress)
      const hip = userData.journey.hipStart + (hipProgress * entry.progress)
      
      let muscle = undefined
      if (userData.journey.muscleStart && userData.journey.muscleCurrent) {
        const muscleProgress = userData.journey.muscleCurrent - userData.journey.muscleStart
        muscle = userData.journey.muscleStart + (muscleProgress * entry.progress)
      }
      
      return {
        user_id: userId,
        date: entry.date,
        weight: entry.weight,
        weight_unit: 'kg',
        body_fat_percentage: Math.round(bodyFat * 10) / 10,
        muscle_mass: muscle ? Math.round(muscle * 10) / 10 : undefined,
        waist_circumference: Math.round(waist),
        hip_circumference: Math.round(hip),
        waist_unit: 'cm',
        notes: index === 0 ? 'Starting measurement' : 
               index === weightHistory.length - 1 ? 'Most recent' : 
               undefined
      }
    })
    
    // Insert in batches to avoid timeouts
    const batchSize = 50
    for (let i = 0; i < metricsToInsert.length; i += batchSize) {
      const batch = metricsToInsert.slice(i, i + batchSize)
      const { error: metricsError } = await supabase
        .from('body_metrics')
        .upsert(batch, { onConflict: 'user_id,date' })
      
      if (metricsError) {
        console.error(`❌ Error inserting metrics batch: ${metricsError.message}`)
      }
    }
    console.log(`✅ Added ${metricsToInsert.length} weight entries over ${Math.round((new Date().getTime() - userData.journey.startDate.getTime()) / (1000 * 60 * 60 * 24 * 365))} years`)
    
    // Add progress photos (with placeholder URLs)
    const progressPhotos = userData.progressPhotos.map(photo => {
      const photoDate = new Date()
      photoDate.setDate(photoDate.getDate() - photo.daysAgo)
      
      return {
        user_id: userId,
        date: format(photoDate, 'yyyy-MM-dd'),
        // Using pravatar for progress photos as placeholders
        photo_url: getProfileAvatarUrl(`${userData.profile.username}-${photo.daysAgo}-${photo.angle}`, 600),
        thumbnail_url: getProfileAvatarUrl(`${userData.profile.username}-${photo.daysAgo}-${photo.angle}`, 150),
        angle: photo.angle,
        notes: photo.note,
        body_metrics_id: undefined // Would need to query for actual ID
      }
    })
    
    // Check if progress_photos table exists
    const { error: photosError } = await supabase
      .from('progress_photos')
      .insert(progressPhotos)
    
    if (photosError) {
      console.log(`⚠️  Progress photos table might not exist: ${photosError.message}`)
    } else {
      console.log(`✅ Added ${progressPhotos.length} progress photos`)
    }
    
    // Add daily steps for active users
    if (userData.profile.activity_level === 'very_active' || userData.profile.activity_level === 'extremely_active') {
      const stepsData = []
      for (let i = 0; i < 365; i += 1) { // Last year of steps
        const date = new Date()
        date.setDate(date.getDate() - i)
        
        // Base steps on activity level
        const baseSteps = userData.profile.activity_level === 'extremely_active' ? 12000 : 8000
        const variation = 3000
        
        stepsData.push({
          user_id: userId,
          date: format(date, 'yyyy-MM-dd'),
          steps: Math.floor(baseSteps + (Math.random() * variation * 2 - variation)),
          notes: i % 7 === 0 ? 'Rest day' : i % 7 === 3 ? 'Leg day - fewer steps' : undefined
        })
      }
      
      // Insert in batches
      for (let i = 0; i < stepsData.length; i += batchSize) {
        const batch = stepsData.slice(i, i + batchSize)
        const { error: stepsError } = await supabase
          .from('daily_metrics')
          .upsert(batch, { onConflict: 'user_id,date' })
        
        if (stepsError) {
          console.error(`❌ Error inserting steps batch: ${stepsError.message}`)
        }
      }
      console.log(`✅ Added 365 days of step data`)
    }
    
    console.log(`✅ Completed setup for ${userData.profile.full_name}`)
  }
  
  console.log('\n🎉 Comprehensive seeding complete!')
  console.log('\n📊 Summary:')
  console.log('- 5 users with full profiles and settings')
  console.log('- 2-4 years of weight history per user')
  console.log('- Body composition tracking (BF%, measurements)')
  console.log('- Progress photos for each user')
  console.log('- Daily step data for active users')
  console.log('- Research-based goals set for all users')
  console.log('\n🔑 Login: [email] / password123')
}

seedComprehensiveData()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Fatal error:', error)
    process.exit(1)
  })
