'use client'

import { useUser } from '@clerk/nextjs'
import { useClerkSupabaseClient } from '@/lib/supabase/clerk-client'
import { useState, useEffect, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import type { PostgrestError } from '@supabase/supabase-js'
import type { BodyMetrics } from '@/types/body-metrics'

type ProfileRow = Record<string, unknown> & { id?: string; email?: string | null }
type WeightLog = BodyMetrics

export default function TestClerkSupabasePage() {
  const { user, isLoaded } = useUser()
  const supabase = useClerkSupabaseClient()
  const [profile, setProfile] = useState<ProfileRow | null>(null)
  const [weights, setWeights] = useState<WeightLog[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const fetchData = useCallback(async () => {
    if (!user) return

    setLoading(true)
    setError(null)

    try {
      // Test fetching profile
      const { data: profileData, error: profileError } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single()

      if (profileError && (profileError as PostgrestError).code !== 'PGRST116') {
        console.error('Profile error:', profileError)
        setError(`Profile error: ${profileError.message}`)
      } else {
        setProfile(profileData as ProfileRow | null)
      }

      // Test fetching latest body metrics with weight entries
      const { data: weightsData, error: weightsError } = await supabase
        .from('body_metrics')
        .select('*')
        .eq('user_id', user.id)
        .order('date', { ascending: false })
        .limit(5)

      if (weightsError) {
        console.error('Weights error:', weightsError)
        setError(prev => prev ? `${prev}\nWeights error: ${weightsError.message}` : `Weights error: ${weightsError.message}`)
      } else {
        setWeights((weightsData as WeightLog[] | null) || [])
      }
    } catch (err: unknown) {
      console.error('Unexpected error:', err)
      setError(`Unexpected error: ${err instanceof Error ? err.message : String(err)}`)
    } finally {
      setLoading(false)
    }
  }, [supabase, user])

  useEffect(() => {
    if (isLoaded && user) {
      fetchData()
    }
  }, [fetchData, isLoaded, user])

  const createTestProfile = async () => {
    if (!user) return

    setLoading(true)
    setError(null)

    try {
      const { data, error } = await supabase
        .from('profiles')
        .upsert({
          id: user.id,
          email: user.emailAddresses[0]?.emailAddress,
          name: user.fullName || user.firstName || 'Test User',
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        })
        .select()
        .single()

      if (error) {
        setError(`Failed to create profile: ${error.message}`)
      } else {
        setProfile(data)
        await fetchData()
      }
    } catch (err: unknown) {
      setError(`Unexpected error: ${err instanceof Error ? err.message : String(err)}`)
    } finally {
      setLoading(false)
    }
  }

  const addTestWeight = async () => {
    if (!user) return

    setLoading(true)
    setError(null)

    try {
      const { error } = await supabase
        .from('body_metrics')
        .insert({
          user_id: user.id,
          date: new Date().toISOString(),
          weight: 70 + Math.random() * 10,
          weight_unit: 'kg',
          notes: 'Test weight entry'
        })
        .select()
        .single()

      if (error) {
        setError(`Failed to add weight: ${error.message}`)
      } else {
        await fetchData()
      }
    } catch (err: unknown) {
      setError(`Unexpected error: ${err instanceof Error ? err.message : String(err)}`)
    } finally {
      setLoading(false)
    }
  }

  if (!isLoaded) {
    return <div className="p-8">Loading...</div>
  }

  if (!user) {
    return <div className="p-8">Please sign in to test Clerk-Supabase integration</div>
  }

  return (
    <div className="container mx-auto p-8">
      <h1 className="text-2xl font-bold mb-6">Clerk-Supabase Integration Test</h1>

      <div className="grid gap-6">
        <Card>
          <CardHeader>
            <CardTitle>Clerk User Info</CardTitle>
          </CardHeader>
          <CardContent>
            <pre className="text-sm overflow-auto bg-gray-100 p-4 rounded">
              {JSON.stringify({
                id: user.id,
                email: user.emailAddresses[0]?.emailAddress,
                name: user.fullName || user.firstName
              }, null, 2)}
            </pre>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Supabase Profile</CardTitle>
          </CardHeader>
          <CardContent>
            {profile ? (
              <pre className="text-sm overflow-auto bg-gray-100 p-4 rounded">
                {JSON.stringify(profile, null, 2)}
              </pre>
            ) : (
              <div>
                <p className="mb-4">No profile found</p>
                <Button onClick={createTestProfile} disabled={loading}>
                  Create Test Profile
                </Button>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Weight Logs</CardTitle>
          </CardHeader>
          <CardContent>
            <Button onClick={addTestWeight} disabled={loading} className="mb-4">
              Add Test Weight
            </Button>
            {weights.length > 0 ? (
              <pre className="text-sm overflow-auto bg-gray-100 p-4 rounded">
                {JSON.stringify(weights, null, 2)}
              </pre>
            ) : (
              <p>No weight logs found</p>
            )}
          </CardContent>
        </Card>

        {error && (
          <Card>
            <CardHeader>
              <CardTitle className="text-red-600">Error</CardTitle>
            </CardHeader>
            <CardContent>
              <pre className="text-sm text-red-600 whitespace-pre-wrap">{error}</pre>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}
