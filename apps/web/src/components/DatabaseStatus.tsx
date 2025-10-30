'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { createClient } from '@/lib/supabase/client'
import { publicEnv } from '@/env'
import { 
  Database, 
  CheckCircle, 
  XCircle, 
  RefreshCw,
  Eye,
  EyeOff
} from 'lucide-react'

interface ConnectionStatus {
  success: boolean
  error?: string
  details?: string
  message?: string
}

export function DatabaseStatus() {
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [showDetails, setShowDetails] = useState(false)
  const [showKeys, setShowKeys] = useState(false)
  
  const supabase = createClient()

  const testConnection = async () => {
    setIsLoading(true)
    try {
      // Test connection by trying to select from a non-existent table
      const { error } = await supabase.from('_').select('*').limit(1)
      
      if (error && error.code === '42P01') {
        // Table doesn't exist error means we're connected
        setConnectionStatus({
          success: true,
          message: 'Connected successfully'
        })
      } else if (error) {
        setConnectionStatus({
          success: false,
          error: error.message,
          details: 'Database connection failed'
        })
      } else {
        setConnectionStatus({
          success: true,
          message: 'Connected successfully'
        })
      }
    } catch (error) {
      setConnectionStatus({
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
        details: 'Connection test failed'
      })
    } finally {
      setIsLoading(false)
    }
  }

  useEffect(() => {
    testConnection()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const getStatusColor = (status: boolean) => {
    return status ? 'text-green-500' : 'text-red-500'
  }

  const getStatusIcon = (status: boolean) => {
    return status ? <CheckCircle className="h-4 w-4" /> : <XCircle className="h-4 w-4" />
  }

  const getEnvironmentBadgeVariant = (env: string) => {
    switch (env) {
      case 'production':
        return 'destructive'
      case 'preview':
      case 'staging':
        return 'secondary'
      case 'development':
      case 'local':
        return 'outline'
      default:
        return 'secondary'
    }
  }

  const vercelEnv = publicEnv.NEXT_PUBLIC_VERCEL_ENV || 'development'
  const hasSupabaseUrl = !!publicEnv.NEXT_PUBLIC_SUPABASE_URL
  const hasSupabaseKey = !!publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY

  return (
    <Card className="border-linear-border bg-linear-card/50 backdrop-blur-sm">
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-linear-text">
          <Database className="h-5 w-5 text-linear-purple" />
          Database Status
          <Button
            variant="ghost"
            size="sm"
            onClick={testConnection}
            disabled={isLoading}
            className="ml-auto"
          >
            <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
          </Button>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Environment Information */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <div className="text-xs text-linear-text-tertiary mb-1">Environment</div>
            <Badge variant={getEnvironmentBadgeVariant(vercelEnv)} className="text-xs">
              {vercelEnv.toUpperCase()}
            </Badge>
          </div>
          <div>
            <div className="text-xs text-linear-text-tertiary mb-1">Node Environment</div>
            <Badge variant="outline" className="text-xs">
              {publicEnv.NODE_ENV || 'unknown'}
            </Badge>
          </div>
        </div>

        {/* Connection Status */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span className="text-sm text-linear-text-secondary">Connection Status</span>
            {connectionStatus && (
              <div className={`flex items-center gap-1 ${getStatusColor(connectionStatus.success)}`}>
                {getStatusIcon(connectionStatus.success)}
                <span className="text-xs">
                  {connectionStatus.success ? 'Connected' : 'Failed'}
                </span>
              </div>
            )}
          </div>
          
          {connectionStatus && !connectionStatus.success && (
            <div className="text-xs text-red-400 bg-red-500/10 p-2 rounded border border-red-500/20">
              <div className="font-medium">Error: {connectionStatus.error}</div>
              {connectionStatus.details && (
                <div className="text-red-300 mt-1">{connectionStatus.details}</div>
              )}
            </div>
          )}
        </div>

        {/* API Keys Validation */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span className="text-sm text-linear-text-secondary">API Keys</span>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowKeys(!showKeys)}
              className="h-6 px-2"
            >
              {showKeys ? <EyeOff className="h-3 w-3" /> : <Eye className="h-3 w-3" />}
            </Button>
          </div>
          
          <div className="space-y-1">
            <div className="flex items-center justify-between text-xs">
              <span className="text-linear-text-tertiary">Supabase URL</span>
              <div className={`flex items-center gap-1 ${getStatusColor(hasSupabaseUrl)}`}>
                {getStatusIcon(hasSupabaseUrl)}
                <span>{hasSupabaseUrl ? 'Set' : 'Missing'}</span>
              </div>
            </div>
            
            <div className="flex items-center justify-between text-xs">
              <span className="text-linear-text-tertiary">Anon Key</span>
              <div className={`flex items-center gap-1 ${getStatusColor(hasSupabaseKey)}`}>
                {getStatusIcon(hasSupabaseKey)}
                <span>{hasSupabaseKey ? 'Set' : 'Missing'}</span>
              </div>
            </div>
          </div>

          {showKeys && (
            <div className="text-xs space-y-1 bg-linear-border/20 p-2 rounded">
              <div>
                <span className="text-linear-text-tertiary">URL: </span>
                <span className="text-linear-text font-mono text-[10px]">
                  {publicEnv.NEXT_PUBLIC_SUPABASE_URL || 'Not set'}
                </span>
              </div>
              <div>
                <span className="text-linear-text-tertiary">Key: </span>
                <span className="text-linear-text font-mono text-[10px]">
                  {publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY ?
                    `${publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY.substring(0, 20)}...` :
                    'Not set'}
                </span>
              </div>
            </div>
          )}
        </div>

        {/* Show/Hide Details Toggle */}
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setShowDetails(!showDetails)}
          className="w-full text-xs text-linear-text-tertiary hover:text-linear-text"
        >
          {showDetails ? 'Hide Details' : 'Show Details'}
        </Button>

        {/* Detailed Information */}
        {showDetails && (
          <div className="text-xs space-y-2 bg-linear-border/10 p-3 rounded border border-linear-border/30">
            <div>
              <span className="text-linear-text-secondary font-medium">Environment Variables:</span>
              <div className="mt-1 space-y-1 text-linear-text-tertiary">
                <div>VERCEL_ENV: {publicEnv.VERCEL_ENV || 'undefined'}</div>
                <div>NODE_ENV: {publicEnv.NODE_ENV || 'undefined'}</div>
                <div>NEXT_PUBLIC_SUPABASE_URL: {hasSupabaseUrl ? '✓ Set' : '✗ Missing'}</div>
                <div>NEXT_PUBLIC_SUPABASE_ANON_KEY: {hasSupabaseKey ? '✓ Set' : '✗ Missing'}</div>
              </div>
            </div>
            
            {connectionStatus && (
              <div>
                <span className="text-linear-text-secondary font-medium">Connection Details:</span>
                <div className="mt-1 text-linear-text-tertiary">
                  {connectionStatus.success ? (
                    <div className="text-green-400">✓ Database connection successful</div>
                  ) : (
                    <div className="text-red-400">✗ {connectionStatus.error}</div>
                  )}
                </div>
              </div>
            )}
            
            <div className="pt-2 border-t border-linear-border/30">
              <div className="text-linear-text-tertiary text-[10px]">
                This status panel will be removed after launch. It&apos;s for debugging only.
              </div>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}