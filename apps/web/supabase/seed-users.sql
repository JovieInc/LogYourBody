-- Seed script for 5 diverse users on different fitness journeys
-- Run this after the initial schema is set up

-- Clear existing test data (be careful in production!)
DELETE FROM body_metrics WHERE user_id IN (
  SELECT id FROM auth.users WHERE email LIKE '%@example.com'
);
DELETE FROM profiles WHERE id IN (
  SELECT id FROM auth.users WHERE email LIKE '%@example.com'
);

-- User 1: Sarah Chen - Weight Loss Journey (Overweight Female)
-- 5'4" (163cm), Started at 180 lbs, now 165 lbs, goal 140 lbs
DO $$
DECLARE
  user_id uuid;
BEGIN
  -- Create auth user
  INSERT INTO auth.users (
    id,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  ) VALUES (
    gen_random_uuid(),
    'sarah.chen@example.com',
    crypt('password123', gen_salt('bf')),
    now(),
    now() - interval '6 months',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Sarah Chen"}'
  ) RETURNING id INTO user_id;

  -- Create user profile
  INSERT INTO profiles (
    id,
    full_name,
    username,
    gender,
    date_of_birth,
    height,
    height_unit,
    activity_level,
    bio,
    goal_weight,
    goal_weight_unit
  ) VALUES (
    id,
    'Sarah Chen',
    'sarahc',
    'female',
    '1992-03-15',
    163,
    'cm',
    'moderately_active',
    'On a weight loss journey. Down 15 lbs so far! Love yoga and hiking.',
    63.5, -- 140 lbs goal
    'kg'
  );

  -- Add body metrics showing weight loss progress with waist/hip measurements
  INSERT INTO body_metrics (user_id, date, weight, weight_unit, body_fat_percentage, waist_circumference, hip_circumference, waist_unit, notes) VALUES
  (user_id, now() - interval '6 months', 81.6, 'kg', 35.0, 95, 110, 'cm', 'Starting my journey'),
  (user_id, now() - interval '5 months', 79.4, 'kg', 34.2, 92, 108, 'cm', 'First month down!'),
  (user_id, now() - interval '4 months', 77.1, 'kg', 33.0, 89, 106, 'cm', 'Feeling stronger'),
  (user_id, now() - interval '3 months', 76.2, 'kg', 32.5, 87, 105, 'cm', 'Hit a plateau'),
  (user_id, now() - interval '2 months', 75.3, 'kg', 31.8, 85, 104, 'cm', 'Broke through!'),
  (user_id, now() - interval '1 month', 74.8, 'kg', 31.2, 83, 103, 'cm', 'Steady progress'),
  (user_id, now(), 74.8, 'kg', 30.5, 81, 102, 'cm', 'Current weight - 15 lbs down!');
END $$;

-- User 2: Marcus Johnson - Bulking Journey (Athletic Male)
-- 6'1" (185cm), Started at 175 lbs, now 190 lbs, goal 200 lbs
DO $$
DECLARE
  user_id uuid;
BEGIN
  INSERT INTO auth.users (
    id,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  ) VALUES (
    gen_random_uuid(),
    'marcus.johnson@example.com',
    crypt('password123', gen_salt('bf')),
    now(),
    now() - interval '4 months',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Marcus Johnson"}'
  ) RETURNING id INTO user_id;

  INSERT INTO user_profiles (
    id,
    full_name,
    username,
    gender,
    date_of_birth,
    height,
    height_unit,
    activity_level,
    bio,
    goal_weight,
    goal_weight_unit
  ) VALUES (
    id,
    'Marcus Johnson',
    'marcusj',
    'male',
    '1995-07-22',
    73,
    'ft',
    'very_active',
    'Powerlifter on a lean bulk. 4 years of training experience.',
    90.7, -- 200 lbs goal
    'kg'
  );

  INSERT INTO body_metrics (user_id, date, weight, weight_unit, body_fat_percentage, muscle_mass, waist_circumference, hip_circumference, waist_unit, notes) VALUES
  (user_id, now() - interval '4 months', 79.4, 'kg', 12.0, 69.9, 80, 95, 'cm', 'Starting lean bulk'),
  (user_id, now() - interval '3 months', 81.2, 'kg', 12.5, 71.1, 81, 96, 'cm', 'Strength increasing'),
  (user_id, now() - interval '2 months', 83.0, 'kg', 13.0, 72.2, 82, 97, 'cm', 'Hit 315 bench!'),
  (user_id, now() - interval '1 month', 84.8, 'kg', 13.5, 73.4, 83, 98, 'cm', 'Feeling strong'),
  (user_id, now(), 86.2, 'kg', 14.0, 74.1, 84, 99, 'cm', '15 lbs gained, mostly muscle');
END $$;

-- User 3: Emily Rodriguez - Maintenance Phase (Fit Female)
-- 5'7" (170cm), Maintaining at 135 lbs, 22% body fat
DO $$
DECLARE
  user_id uuid;
BEGIN
  INSERT INTO auth.users (
    id,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  ) VALUES (
    gen_random_uuid(),
    'emily.rodriguez@example.com',
    crypt('password123', gen_salt('bf')),
    now(),
    now() - interval '1 year',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Emily Rodriguez"}'
  ) RETURNING id INTO user_id;

  INSERT INTO user_profiles (
    id,
    full_name,
    username,
    gender,
    date_of_birth,
    height,
    height_unit,
    activity_level,
    bio
  ) VALUES (
    id,
    'Emily Rodriguez',
    'emilyr',
    'female',
    '1990-11-08',
    67,
    'ft',
    'very_active',
    'Personal trainer. Maintaining my physique year-round.'
  );

  INSERT INTO body_metrics (user_id, date, weight, weight_unit, body_fat_percentage, muscle_mass, notes) VALUES
  (user_id, now() - interval '3 months', 61.2, 'kg', 22.0, 47.7, 'Summer shape'),
  (user_id, now() - interval '2 months', 61.5, 'kg', 22.2, 47.8, 'Maintaining well'),
  (user_id, now() - interval '1 month', 61.3, 'kg', 22.1, 47.7, 'Consistent training'),
  (user_id, now(), 61.2, 'kg', 22.0, 47.7, 'Perfect maintenance');
END $$;

-- User 4: David Kim - Weight Loss Journey (Overweight Male)
-- 5'9" (175cm), Started at 220 lbs, now 195 lbs, goal 170 lbs
DO $$
DECLARE
  user_id uuid;
BEGIN
  INSERT INTO auth.users (
    id,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  ) VALUES (
    gen_random_uuid(),
    'david.kim@example.com',
    crypt('password123', gen_salt('bf')),
    now(),
    now() - interval '8 months',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"David Kim"}'
  ) RETURNING id INTO user_id;

  INSERT INTO user_profiles (
    id,
    full_name,
    username,
    gender,
    date_of_birth,
    height,
    height_unit,
    activity_level,
    bio
  ) VALUES (
    id,
    'David Kim',
    'davidk',
    'male',
    '1988-05-30',
    175,
    'cm',
    'lightly_active',
    'Software engineer getting back in shape. Down 25 lbs!'
  );

  INSERT INTO body_metrics (user_id, date, weight, weight_unit, body_fat_percentage, notes) VALUES
  (user_id, now() - interval '8 months', 99.8, 'kg', 32.0, 'Time to make a change'),
  (user_id, now() - interval '6 months', 95.3, 'kg', 30.5, '10 lbs down'),
  (user_id, now() - interval '4 months', 91.2, 'kg', 28.5, 'Feeling better'),
  (user_id, now() - interval '2 months', 88.5, 'kg', 26.8, 'Clothes fitting better'),
  (user_id, now(), 88.5, 'kg', 25.5, '25 lbs lost! Halfway to goal');
END $$;

-- User 5: Jessica Thompson - Recomposition (Athletic Female)
-- 5'6" (168cm), Weight stable at 145 lbs, dropping body fat while building muscle
DO $$
DECLARE
  user_id uuid;
BEGIN
  INSERT INTO auth.users (
    id,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  ) VALUES (
    gen_random_uuid(),
    'jessica.thompson@example.com',
    crypt('password123', gen_salt('bf')),
    now(),
    now() - interval '5 months',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Jessica Thompson"}'
  ) RETURNING id INTO user_id;

  INSERT INTO user_profiles (
    id,
    full_name,
    username,
    gender,
    date_of_birth,
    height,
    height_unit,
    activity_level,
    bio
  ) VALUES (
    id,
    'Jessica Thompson',
    'jessicat',
    'female',
    '1993-09-18',
    168,
    'cm',
    'extremely_active',
    'CrossFit athlete. Body recomposition in progress!'
  );

  INSERT INTO body_metrics (user_id, date, weight, weight_unit, body_fat_percentage, muscle_mass, notes) VALUES
  (user_id, now() - interval '5 months', 65.8, 'kg', 28.0, 47.4, 'Starting recomp'),
  (user_id, now() - interval '4 months', 65.9, 'kg', 26.5, 48.5, 'Gaining strength'),
  (user_id, now() - interval '3 months', 66.0, 'kg', 25.0, 49.5, 'PRs every week'),
  (user_id, now() - interval '2 months', 65.8, 'kg', 24.0, 50.0, 'Visible abs!'),
  (user_id, now() - interval '1 month', 65.7, 'kg', 23.5, 50.3, 'Getting lean'),
  (user_id, now(), 65.8, 'kg', 23.0, 50.7, 'Same weight, new body!');
END $$;

-- Add some daily metrics for the most recent user (Jessica) to show step tracking
INSERT INTO daily_metrics (user_id, date, steps, notes)
SELECT 
  id,
  generate_series(now()::date - interval '7 days', now()::date, interval '1 day'),
  (random() * 5000 + 8000)::int,
  CASE 
    WHEN random() < 0.3 THEN 'Rest day'
    WHEN random() < 0.6 THEN 'Gym day'
    ELSE 'Active recovery'
  END
FROM auth.users WHERE email = 'jessica.thompson@example.com';
