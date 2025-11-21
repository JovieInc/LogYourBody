'use client'

import { useUser, useAuth as useClerkAuth, useSignIn, useSignUp, useClerk } from '@clerk/nextjs'
import { createContext, useContext, useMemo, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { processImageFile, validateImageFile } from '@/lib/clerk-avatar-upload'

type ClerkUserResource = ReturnType<typeof useUser>['user']
type ClerkGetToken = ReturnType<typeof useClerkAuth>['getToken']

interface AuthSession {
  getToken: ClerkGetToken
}

interface AuthContextType {
  user: ClerkUserResource | null
  session: AuthSession | null
  loading: boolean
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>
  signUp: (email: string, password: string) => Promise<{ error: Error | null }>
  signOut: () => Promise<void>
  signInWithProvider: (provider: 'google' | 'apple') => Promise<{ error: Error | null }>
  uploadProfileImage: (file: File) => Promise<{ imageUrl?: string; error: Error | null }>
  deleteProfileImage: () => Promise<{ error: Error | null }>
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function ClerkAuthProvider({ children }: { children: React.ReactNode }) {
  const { user, isLoaded } = useUser()
  const { signOut: clerkSignOut, getToken } = useClerkAuth()
  const { setActive } = useClerk()
  const { signIn: clerkSignIn } = useSignIn()
  const { signUp: clerkSignUp } = useSignUp()
  const router = useRouter()

  const signIn = useCallback(async (email: string, password: string) => {
    try {
      if (!clerkSignIn) throw new Error('Sign in not available')

      const result = await clerkSignIn.create({
        identifier: email,
        password,
      })

      if (result.status === 'complete') {
        await setActive({ session: result.createdSessionId })
        router.push('/dashboard')
        return { error: null }
      }

      return { error: new Error('Sign in failed') }
    } catch (error) {
      return { error: error as Error }
    }
  }, [clerkSignIn, setActive, router])

  const signUp = useCallback(async (email: string, password: string) => {
    try {
      if (!clerkSignUp) throw new Error('Sign up not available')

      const result = await clerkSignUp.create({
        emailAddress: email,
        password,
      })

      if (result.status === 'complete') {
        await setActive({ session: result.createdSessionId })
        return { error: null }
      }

      // Handle email verification if needed
      if (result.status === 'missing_requirements') {
        await result.prepareEmailAddressVerification({ strategy: 'email_code' })
        // You might want to redirect to email verification page here
      }

      return { error: null }
    } catch (error) {
      return { error: error as Error }
    }
  }, [clerkSignUp, setActive])

  const signOut = useCallback(async () => {
    await clerkSignOut()
    router.push('/')
  }, [clerkSignOut, router])

  const signInWithProvider = useCallback(async (provider: 'google' | 'apple') => {
    try {
      if (!clerkSignIn) throw new Error('Sign in not available')

      const providerMap: Record<'google' | 'apple', 'oauth_google' | 'oauth_apple'> = {
        google: 'oauth_google',
        apple: 'oauth_apple'
      }

      await clerkSignIn.authenticateWithRedirect({
        strategy: providerMap[provider],
        redirectUrl: '/auth/callback',
        redirectUrlComplete: '/dashboard',
      })

      return { error: null }
    } catch (error) {
      return { error: error as Error }
    }
  }, [clerkSignIn])

  const uploadProfileImage = useCallback(async (file: File) => {
    try {
      if (!user) {
        throw new Error('User not authenticated')
      }

      // Validate the file
      const validation = validateImageFile(file)
      if (!validation.valid) {
        throw new Error(validation.error)
      }

      // Process the image (resize and compress to match iOS implementation)
      const processedBlob = await processImageFile(file)

      // Convert blob to File for Clerk API
      const processedFile = new File([processedBlob], file.name, {
        type: 'image/jpeg',
      })

      // Upload to Clerk using the user's setProfileImage method
      await user.setProfileImage({ file: processedFile })

      // Reload user to get updated imageUrl
      await user.reload()

      return { imageUrl: user.imageUrl, error: null }
    } catch (error) {
      console.error('Avatar upload error:', error)
      return { error: error as Error }
    }
  }, [user])

  const deleteProfileImage = useCallback(async () => {
    try {
      if (!user) {
        throw new Error('User not authenticated')
      }

      // Delete profile image using Clerk API
      await user.setProfileImage({ file: null })

      // Reload user to get updated state
      await user.reload()

      return { error: null }
    } catch (error) {
      console.error('Avatar delete error:', error)
      return { error: error as Error }
    }
  }, [user])

  const value = useMemo(() => {
    const currentSession: AuthSession | null = isLoaded ? { getToken } : null
    return ({
      user,
      session: currentSession,
      loading: !isLoaded,
      signIn,
      signUp,
      signOut,
      signInWithProvider,
      uploadProfileImage,
      deleteProfileImage,
    })
  }, [user, getToken, isLoaded, signIn, signUp, signOut, signInWithProvider, uploadProfileImage, deleteProfileImage])

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within a ClerkAuthProvider')
  }
  return context
}

// Export alias for compatibility
export const AuthProvider = ClerkAuthProvider
