// Unmock the profile module since it's mocked globally in jest.setup.js
jest.unmock('@/lib/supabase/profile')

import { getProfile, updateProfile, createProfile } from '../profile'
import { createClient } from '../client'
import { UserProfile } from '@/types/body-metrics'

// Mock Supabase client
jest.mock('../client', () => ({
  createClient: jest.fn()
}))

describe('Profile API', () => {
  const mockSupabase: any = {
    from: jest.fn(),
    select: jest.fn(),
    eq: jest.fn(),
    single: jest.fn(),
    update: jest.fn(),
    insert: jest.fn()
  }
  
  // Set up method chaining
  mockSupabase.from.mockReturnValue(mockSupabase)
  mockSupabase.select.mockReturnValue(mockSupabase)
  mockSupabase.eq.mockReturnValue(mockSupabase)
  mockSupabase.single.mockReturnValue(mockSupabase)
  mockSupabase.update.mockReturnValue(mockSupabase)
  mockSupabase.insert.mockReturnValue(mockSupabase)

  const mockProfileData = {
    id: 'test-user-id',
    email: 'test@example.com',
    full_name: 'Test User',
    username: 'testuser',
    height: 180,
    height_unit: 'cm',
    gender: 'male',
    date_of_birth: '1990-01-01',
    bio: 'Test bio',
    activity_level: 'moderately_active',
    avatar_url: 'https://example.com/avatar.png',
    email_verified: true,
    onboarding_completed: true,
    settings: { units: { weight: 'kg' } },
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z'
  }

  beforeEach(() => {
    jest.clearAllMocks()
    ;(createClient as jest.Mock).mockReturnValue(mockSupabase)
  })

  describe('getProfile', () => {
    it('fetches profile successfully', async () => {
      mockSupabase.single.mockResolvedValue({
        data: mockProfileData,
        error: null
      })

      const result = await getProfile('test-user-id')

      expect(mockSupabase.from).toHaveBeenCalledWith('profiles')
      expect(mockSupabase.select).toHaveBeenCalledWith('*')
      expect(mockSupabase.eq).toHaveBeenCalledWith('id', 'test-user-id')
      expect(result).toEqual(mockProfileData)
    })

    it('returns null on error', async () => {
      mockSupabase.single.mockResolvedValue({
        data: null,
        error: { message: 'Profile not found' }
      })

      const result = await getProfile('test-user-id')

      expect(result).toBeNull()
    })

    it('handles missing settings gracefully', async () => {
      const profileWithoutSettings = { ...mockProfileData, settings: null }
      mockSupabase.single.mockResolvedValue({
        data: profileWithoutSettings,
        error: null
      })

      const result = await getProfile('test-user-id')

      expect(result?.settings).toEqual({})
    })
  })

  describe('updateProfile', () => {
    it('updates profile successfully', async () => {
      const updates: Partial<UserProfile> = {
        full_name: 'Updated Name',
        height: 185,
        date_of_birth: '1991-02-02'
      }

      mockSupabase.single.mockResolvedValue({
        data: { ...mockProfileData, ...updates },
        error: null
      })

      const result = await updateProfile('test-user-id', updates)

      expect(mockSupabase.from).toHaveBeenCalledWith('profiles')
      expect(mockSupabase.update).toHaveBeenCalledWith({
        full_name: 'Updated Name',
        height: 185,
        date_of_birth: '1991-02-02',
        updated_at: expect.any(String)
      })
      expect(mockSupabase.eq).toHaveBeenCalledWith('id', 'test-user-id')
      expect(result).toEqual({ ...mockProfileData, ...updates })
    })

    it('removes computed fields from updates', async () => {
      const updates: Partial<UserProfile> = {
        id: 'should-be-removed',
        full_name: 'Updated Name',
        created_at: '2024-02-02T00:00:00Z',
        updated_at: '2024-02-02T00:00:00Z',
        settings: { units: { weight: 'lbs' } }
      }

      mockSupabase.single.mockResolvedValue({
        data: mockProfileData,
        error: null
      })

      await updateProfile('test-user-id', updates)

      expect(mockSupabase.update).toHaveBeenCalledWith({
        full_name: 'Updated Name',
        updated_at: expect.any(String)
      })
    })

    it('throws error on update failure', async () => {
      const error = { message: 'Update failed' }
      mockSupabase.single.mockResolvedValue({
        data: null,
        error
      })

      await expect(updateProfile('test-user-id', { full_name: 'Test' }))
        .rejects.toEqual(error)
    })
  })

  describe('createProfile', () => {
    it('creates profile successfully', async () => {
      const newProfile = {
        id: 'new-user-id',
        email: 'new@example.com',
        settings: {},
        email_verified: false,
        onboarding_completed: false
      }

      mockSupabase.single.mockResolvedValue({
        data: newProfile,
        error: null
      })

      const result = await createProfile('new-user-id', 'new@example.com')

      expect(mockSupabase.from).toHaveBeenCalledWith('profiles')
      expect(mockSupabase.insert).toHaveBeenCalledWith({
        id: 'new-user-id',
        email: 'new@example.com',
        settings: {},
        email_verified: false,
        onboarding_completed: false
      })
      expect(result).toEqual(newProfile)
    })

    it('throws error on creation failure', async () => {
      const error = { message: 'Creation failed' }
      mockSupabase.single.mockResolvedValue({
        data: null,
        error
      })

      await expect(createProfile('new-user-id', 'new@example.com'))
        .rejects.toEqual(error)
    })
  })
})