-- Stop silently assigning aesthetic targets from sex. Existing values are
-- intentionally preserved because their provenance (automatic vs user-set)
-- cannot be determined safely.
drop trigger if exists set_default_goals_trigger on public.profiles;
drop function if exists public.set_default_goals();

comment on column public.profiles.goal_body_fat_percentage is
  'Optional body fat percentage target explicitly selected by the user.';
comment on column public.profiles.goal_ffmi is
  'Optional Fat-Free Mass Index target explicitly selected by the user.';
comment on column public.profiles.goal_waist_to_hip_ratio is
  'Optional waist-to-hip ratio target explicitly selected by the user.';
comment on column public.profiles.goal_waist_to_height_ratio is
  'Optional waist-to-height ratio target explicitly selected by the user.';
