'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface TestResult {
  success: boolean
  [key: string]: unknown
}

type TestResults = Record<string, TestResult>

export default function ComprehensiveTestPage() {
  const [testResults, setTestResults] = useState<TestResults>({})
  const [loading, setLoading] = useState(false)
  const supabase = createClient()

  const runTests = useCallback(async () => {
    setLoading(true)
    const results: TestResults = {}

    // Test 1: Check authentication status
    try {
      const { data: { user }, error } = await supabase.auth.getUser()
      results.auth = { 
        success: !error, 
        user: user?.email,
        error: error?.message 
      }
    } catch (e) {
      results.auth = { success: false, error: String(e) }
    }

    // Test 2: Check profile data
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        const { data, error } = await supabase
          .from('user_profiles')
          .select('*')
          .eq('user_id', user.id)
          .single()
        
        results.profile = {
          success: !error,
          data: data,
          error: error?.message
        }
      }
    } catch (e) {
      results.profile = { success: false, error: String(e) }
    }

    // Test 3: Check body metrics
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        const { data, error } = await supabase
          .from('body_metrics')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', { ascending: false })
          .limit(5)
        
        results.bodyMetrics = {
          success: !error,
          count: data?.length || 0,
          latest: data?.[0],
          error: error?.message
        }
      }
    } catch (e) {
      results.bodyMetrics = { success: false, error: String(e) }
    }

    // Test 4: Check storage access
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        const { data, error } = await supabase
          .storage
          .from('photos')
          .list(user.id, { limit: 5 })
        
        results.storage = {
          success: !error,
          fileCount: data?.length || 0,
          error: error?.message
        }
      }
    } catch (e) {
      results.storage = { success: false, error: String(e) }
    }

    // Test 5: Test calculations
    const testMetrics = {
      weight: 80,
      height: 180,
      body_fat_percentage: 20
    }
    
    try {
      const leanMass = testMetrics.weight * (1 - testMetrics.body_fat_percentage / 100)
      const ffmi = (leanMass / Math.pow(testMetrics.height / 100, 2))
      
      results.calculations = {
        success: true,
        input: testMetrics,
        leanMass: leanMass.toFixed(2),
        ffmi: ffmi.toFixed(2)
      }
    } catch (e) {
      results.calculations = { success: false, error: String(e) }
    }

    setTestResults(results)
    setLoading(false)
  }, [supabase])

  useEffect(() => {
    runTests()
  }, [runTests])

  return (
    <div className="container mx-auto py-8 px-4">
      <h1 className="text-3xl font-bold mb-8">Comprehensive System Test</h1>
      
      <div className="space-y-6">
        <Button onClick={runTests} disabled={loading}>
          {loading ? 'Running Tests...' : 'Re-run Tests'}
        </Button>

        {Object.entries(testResults).map(([testName, result]) => (
          <Card key={testName}>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <span className={result.success ? 'text-green-600' : 'text-red-600'}>
                  {result.success ? '✓' : '✗'}
                </span>
                {testName}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <pre className="text-sm bg-muted p-4 rounded overflow-auto">
                {JSON.stringify(result, null, 2)}
              </pre>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
