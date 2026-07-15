#!/usr/bin/env tsx

import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import { readFileSync } from 'fs';
import path from 'path';

// Load environment variables
dotenv.config({ path: '.env.local' });

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('❌ Missing required environment variables');
  console.error('Make sure NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are set');
  process.exit(1);
}

// Note: For production, use service role key. Using anon key with RLS disabled for seeding.
console.warn(
  '⚠️  Using anon key for seeding. Make sure RLS is temporarily disabled or use service role key.',
);

const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

async function seedDatabase() {
  console.log('🌱 Seeding database with test users...\n');

  try {
    // First, delete existing test users
    console.log('🧹 Cleaning up existing test users...');

    // Get test user IDs
    const { data: testUsers, error: fetchError } = await supabase
      .from('profiles')
      .select('id')
      .like('email', '%@example.com');

    if (fetchError) {
      console.error('❌ Error fetching test users:', fetchError);
      return;
    }

    if (testUsers && testUsers.length > 0) {
      const userIds = testUsers.map((u) => u.id);

      // Delete from body_metrics
      await supabase.from('body_metrics').delete().in('user_id', userIds);

      // Delete from daily_metrics
      await supabase.from('daily_metrics').delete().in('user_id', userIds);

      // Delete from profiles
      await supabase.from('profiles').delete().in('id', userIds);

      console.log(`✅ Deleted ${testUsers.length} test users\n`);
    }

    // Seed data for each user
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
        },
        metrics: [
          {
            daysAgo: 180,
            weight: 81.6,
            bf: 35.0,
            waist: 95,
            hip: 110,
            notes: 'Starting my journey',
          },
          { daysAgo: 150, weight: 79.4, bf: 34.2, waist: 92, hip: 108, notes: 'First month down!' },
          { daysAgo: 120, weight: 77.1, bf: 33.0, waist: 89, hip: 106, notes: 'Feeling stronger' },
          { daysAgo: 90, weight: 76.2, bf: 32.5, waist: 87, hip: 105, notes: 'Hit a plateau' },
          { daysAgo: 60, weight: 75.3, bf: 31.8, waist: 85, hip: 104, notes: 'Broke through!' },
          { daysAgo: 30, weight: 74.8, bf: 31.2, waist: 83, hip: 103, notes: 'Steady progress' },
          {
            daysAgo: 0,
            weight: 74.8,
            bf: 30.5,
            waist: 81,
            hip: 102,
            notes: 'Current weight - 15 lbs down!',
          },
        ],
      },
      {
        email: 'marcus.johnson@example.com',
        password: 'password123',
        profile: {
          full_name: 'Marcus Johnson',
          username: 'marcusj',
          gender: 'male',
          date_of_birth: '1995-07-22',
          height: 73,
          height_unit: 'ft',
          activity_level: 'very_active',
          bio: 'Powerlifter on a lean bulk. 4 years of training experience.',
          goal_weight: 90.7,
          goal_weight_unit: 'kg',
          goal_body_fat_percentage: null,
          goal_ffmi: null,
          goal_waist_to_hip_ratio: null,
          goal_waist_to_height_ratio: null,
        },
        metrics: [
          {
            daysAgo: 120,
            weight: 79.4,
            bf: 12.0,
            muscle: 69.9,
            waist: 80,
            hip: 95,
            notes: 'Starting lean bulk',
          },
          {
            daysAgo: 90,
            weight: 81.2,
            bf: 12.5,
            muscle: 71.1,
            waist: 81,
            hip: 96,
            notes: 'Strength increasing',
          },
          {
            daysAgo: 60,
            weight: 83.0,
            bf: 13.0,
            muscle: 72.2,
            waist: 82,
            hip: 97,
            notes: 'Hit 315 bench!',
          },
          {
            daysAgo: 30,
            weight: 84.8,
            bf: 13.5,
            muscle: 73.4,
            waist: 83,
            hip: 98,
            notes: 'Feeling strong',
          },
          {
            daysAgo: 0,
            weight: 86.2,
            bf: 14.0,
            muscle: 74.1,
            waist: 84,
            hip: 99,
            notes: '15 lbs gained, mostly muscle',
          },
        ],
      },
      {
        email: 'emily.rodriguez@example.com',
        password: 'password123',
        profile: {
          full_name: 'Emily Rodriguez',
          username: 'emilyr',
          gender: 'female',
          date_of_birth: '1990-11-08',
          height: 67,
          height_unit: 'ft',
          activity_level: 'very_active',
          bio: 'Personal trainer. Maintaining my physique year-round.',
          goal_body_fat_percentage: null,
          goal_waist_to_hip_ratio: null,
          goal_waist_to_height_ratio: null,
        },
        metrics: [
          { daysAgo: 90, weight: 61.2, bf: 22.0, muscle: 47.7, notes: 'Summer shape' },
          { daysAgo: 60, weight: 61.5, bf: 22.2, muscle: 47.8, notes: 'Maintaining well' },
          { daysAgo: 30, weight: 61.3, bf: 22.1, muscle: 47.7, notes: 'Consistent training' },
          { daysAgo: 0, weight: 61.2, bf: 22.0, muscle: 47.7, notes: 'Perfect maintenance' },
        ],
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
        },
        metrics: [
          { daysAgo: 240, weight: 99.8, bf: 32.0, notes: 'Time to make a change' },
          { daysAgo: 180, weight: 95.3, bf: 30.5, notes: '10 lbs down' },
          { daysAgo: 120, weight: 91.2, bf: 28.5, notes: 'Feeling better' },
          { daysAgo: 60, weight: 88.5, bf: 26.8, notes: 'Clothes fitting better' },
          { daysAgo: 0, weight: 88.5, bf: 25.5, notes: '25 lbs lost! Halfway to goal' },
        ],
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
        },
        metrics: [
          { daysAgo: 150, weight: 65.8, bf: 28.0, muscle: 47.4, notes: 'Starting recomp' },
          { daysAgo: 120, weight: 65.9, bf: 26.5, muscle: 48.5, notes: 'Gaining strength' },
          { daysAgo: 90, weight: 66.0, bf: 25.0, muscle: 49.5, notes: 'PRs every week' },
          { daysAgo: 60, weight: 65.8, bf: 24.0, muscle: 50.0, notes: 'Visible abs!' },
          { daysAgo: 30, weight: 65.7, bf: 23.5, muscle: 50.3, notes: 'Getting lean' },
          { daysAgo: 0, weight: 65.8, bf: 23.0, muscle: 50.7, notes: 'Same weight, new body!' },
        ],
      },
    ];

    // Create each user
    for (const userData of users) {
      console.log(`👤 Creating ${userData.profile.full_name}...`);

      // Create auth user
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email: userData.email,
        password: userData.password,
        email_confirm: true,
        user_metadata: {
          name: userData.profile.full_name,
        },
      });

      if (authError) {
        console.error(`❌ Error creating auth user ${userData.email}:`, authError);
        continue;
      }

      const userId = authData.user.id;

      // Update profile with additional data
      const { error: profileError } = await supabase
        .from('profiles')
        .update(userData.profile)
        .eq('id', userId);

      if (profileError) {
        console.error(`❌ Error updating profile for ${userData.email}:`, profileError);
        continue;
      }

      // Add body metrics
      const metricsToInsert = userData.metrics.map((m) => {
        const date = new Date();
        date.setDate(date.getDate() - m.daysAgo);

        return {
          user_id: userId,
          date: date.toISOString().split('T')[0],
          weight: m.weight,
          weight_unit: 'kg',
          body_fat_percentage: m.bf,
          muscle_mass: m.muscle,
          waist_circumference: m.waist,
          hip_circumference: m.hip,
          waist_unit: 'cm',
          notes: m.notes,
        };
      });

      const { error: metricsError } = await supabase.from('body_metrics').insert(metricsToInsert);

      if (metricsError) {
        console.error(`❌ Error adding metrics for ${userData.email}:`, metricsError);
      }

      // Add daily steps for Jessica
      if (userData.email === 'jessica.thompson@example.com') {
        const stepsData = [];
        for (let i = 0; i < 7; i++) {
          const date = new Date();
          date.setDate(date.getDate() - i);
          stepsData.push({
            user_id: userId,
            date: date.toISOString().split('T')[0],
            steps: Math.floor(Math.random() * 5000 + 8000),
            notes: ['Rest day', 'Gym day', 'Active recovery'][Math.floor(Math.random() * 3)],
          });
        }

        await supabase.from('daily_metrics').insert(stepsData);
      }

      console.log(`✅ Created ${userData.profile.full_name}`);
    }

    console.log('\n✅ Database seeded successfully!');
    console.log('\n📝 Test users created:');
    console.log('   - sarah.chen@example.com (Weight loss journey - Female)');
    console.log('   - marcus.johnson@example.com (Bulking - Male)');
    console.log('   - emily.rodriguez@example.com (Maintenance - Female)');
    console.log('   - david.kim@example.com (Weight loss journey - Male)');
    console.log('   - jessica.thompson@example.com (Recomposition - Female)');
    console.log('\n🔑 All users have password: password123');
  } catch (error) {
    console.error('❌ Unexpected error:', error);
  }
}

// Run the seed
seedDatabase()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
