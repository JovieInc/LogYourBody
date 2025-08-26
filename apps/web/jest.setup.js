// Learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom'

// Mock Clerk Next.js - do this early before any components try to import it
jest.mock('@clerk/nextjs', () => ({
  useUser: jest.fn(() => ({
    user: null,
    isLoaded: true,
  })),
  useAuth: jest.fn(() => ({
    signOut: jest.fn(),
    getToken: jest.fn(() => Promise.resolve('test-token')),
  })),
  useSignIn: jest.fn(() => ({
    signIn: {
      create: jest.fn(() => Promise.resolve({
        status: 'complete',
        createdSessionId: 'test-session-id',
      })),
      authenticateWithRedirect: jest.fn(),
    },
  })),
  useSignUp: jest.fn(() => ({
    signUp: {
      create: jest.fn(() => Promise.resolve({
        status: 'complete',
        createdSessionId: 'test-session-id',
      })),
    },
  })),
  useClerk: jest.fn(() => ({
    setActive: jest.fn(),
  })),
  ClerkProvider: ({ children }) => children,
  SignIn: ({ children }) => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const React = require('react')
    return React.createElement('div', { 'data-testid': 'clerk-signin' }, [
      React.createElement('form', { key: 'form' }, [
        React.createElement('input', { key: 'email', type: 'email', 'aria-label': 'Email', role: 'textbox' }),
        React.createElement('input', { key: 'password', type: 'password', 'aria-label': 'Password' }),
        React.createElement('button', { key: 'submit', type: 'submit' }, 'Sign in'),
        React.createElement('a', { key: 'signup', href: '/signup' }, 'Sign up'),
        React.createElement('a', { key: 'forgot', href: '/forgot-password' }, 'Forgot?')
      ])
    ])
  },
  SignUp: ({ children }) => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const React = require('react')
    return React.createElement('div', { 'data-testid': 'clerk-signup' }, [
      React.createElement('form', { key: 'form' }, [
        React.createElement('input', { key: 'email', type: 'email', 'aria-label': 'Email', role: 'textbox' }),
        React.createElement('input', { key: 'password', type: 'password', 'aria-label': 'Password' }),
        React.createElement('button', { key: 'submit', type: 'submit' }, 'Create account'),
        React.createElement('a', { key: 'signin', href: '/signin' }, 'Sign in')
      ])
    ])
  },
}))

// Check if we're in Node environment
const isNode = typeof window === 'undefined'

// Mock Next.js router
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(() => ({
    push: jest.fn(),
    replace: jest.fn(),
    prefetch: jest.fn(),
    back: jest.fn(),
    refresh: jest.fn(),
    forward: jest.fn(),
  })),
  usePathname: jest.fn(() => '/'),
  useSearchParams: jest.fn(() => new URLSearchParams()),
  useParams: jest.fn(() => ({})),
  notFound: jest.fn(),
  redirect: jest.fn(),
}))

// Clerk mock is already set up at the top of the file

// Mock Supabase client
jest.mock('@/lib/supabase/client', () => ({
  supabase: {
    auth: {
      getSession: jest.fn(() => Promise.resolve({ data: { session: null } })),
      signInWithPassword: jest.fn(),
      signUp: jest.fn(),
      signOut: jest.fn(),
      signInWithOAuth: jest.fn(),
      onAuthStateChange: jest.fn(() => ({
        data: {
          subscription: {
            unsubscribe: jest.fn(),
          },
        },
      })),
    },
    from: jest.fn(() => ({
      select: jest.fn(() => ({
        limit: jest.fn(() => Promise.resolve({ error: null })),
      })),
    })),
  },
  getSupabaseEnvironment: jest.fn(() => 'test'),
  validateSupabaseKeys: jest.fn(() => ({
    url: { exists: true, valid: true, value: 'https://test.supabase.co' },
    anonKey: { exists: true, valid: true, value: 'test-key' },
  })),
  testSupabaseConnection: jest.fn(() => 
    Promise.resolve({ success: true, message: 'Connected successfully' })
  ),
}))

// Mock indexedDB and related APIs
if (typeof global !== 'undefined') {
  // Create a mock IDBRequest with event listener support
  class MockIDBRequest {
    constructor() {
      this.onsuccess = null
      this.onerror = null
      this.result = null
      this.error = null
      this.readyState = 'pending'
    }
    
    addEventListener(event, handler) {
      if (event === 'success') this.onsuccess = handler
      if (event === 'error') this.onerror = handler
    }
    
    removeEventListener() {}
  }
  
  // Set up global IndexedDB mocks
  global.IDBRequest = MockIDBRequest
  global.IDBDatabase = jest.fn()
  global.IDBTransaction = jest.fn()
  global.IDBObjectStore = jest.fn()
  global.IDBIndex = jest.fn()
  global.IDBCursor = jest.fn()
  global.IDBKeyRange = {
    bound: jest.fn(),
    lowerBound: jest.fn(),
    upperBound: jest.fn(),
    only: jest.fn(),
  }
  
  global.indexedDB = {
    open: jest.fn(() => {
      const request = new MockIDBRequest()
      request.result = {
        transaction: jest.fn(),
        close: jest.fn(),
        objectStoreNames: { contains: jest.fn(() => false) },
        createObjectStore: jest.fn(),
      }
      setTimeout(() => {
        if (request.onsuccess) request.onsuccess({ target: request })
      }, 0)
      return request
    }),
    deleteDatabase: jest.fn(() => new MockIDBRequest()),
  }
}

// Mock window.matchMedia only if window is defined
if (typeof window !== 'undefined') {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: jest.fn(), // deprecated
      removeListener: jest.fn(), // deprecated
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      dispatchEvent: jest.fn(),
    })),
  })
  
  // Also add window.location.origin for tests - don't delete, just extend
  if (!window.location.origin) {
    Object.defineProperty(window.location, 'origin', {
      value: 'http://localhost:3000',
      writable: true,
      configurable: true
    })
  }
}

// Add pointer events polyfill for Radix UI only if Element is defined
if (typeof Element !== 'undefined') {
  if (!Element.prototype.hasPointerCapture) {
    Element.prototype.hasPointerCapture = jest.fn()
  }
  if (!Element.prototype.setPointerCapture) {
    Element.prototype.setPointerCapture = jest.fn()
  }
  if (!Element.prototype.releasePointerCapture) {
    Element.prototype.releasePointerCapture = jest.fn()
  }
}

// Mock date-fns to avoid timezone issues in tests
jest.mock('date-fns', () => ({
  ...jest.requireActual('date-fns'),
  format: (date, formatStr) => {
    const actual = jest.requireActual('date-fns')
    if (formatStr === 'yyyy-MM-dd' && typeof date === 'string') {
      return date // Return the string as-is for DB formatting
    }
    return actual.format(date, formatStr)
  }
}))

// Mock ClerkAuthContext - This should be before individual test mocks
jest.mock('@/contexts/ClerkAuthContext', () => ({
  ClerkAuthProvider: ({ children }) => children,
  AuthProvider: ({ children }) => children,
  useAuth: jest.fn(() => ({
    user: null,
    session: null,
    loading: false,
    signIn: jest.fn(),
    signUp: jest.fn(),
    signOut: jest.fn(),
    signInWithProvider: jest.fn(),
  })),
}))

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  BarChart3: function BarChart3() {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    return require('react').createElement('svg')
  },
  // Add other icons as needed
}))

// Mock framer-motion
jest.mock('framer-motion', () => ({
  motion: {
    div: ({ children, ...props }) => {
      const { initial, animate, exit, transition, ...restProps } = props
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      return require('react').createElement('div', restProps, children)
    },
    button: ({ children, ...props }) => {
      const { initial, animate, exit, transition, whileHover, whileTap, ...restProps } = props
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      return require('react').createElement('button', restProps, children)
    },
    span: ({ children, ...props }) => {
      const { initial, animate, exit, transition, ...restProps } = props
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      return require('react').createElement('span', restProps, children)
    }
  },
  AnimatePresence: ({ children }) => children
}))

// Mock Supabase profile module
jest.mock('@/lib/supabase/profile', () => ({
  getProfile: jest.fn().mockResolvedValue({
    height: 71,
    height_unit: 'ft',
    gender: 'male',
    settings: {
      units: {
        weight: 'lbs',
        height: 'ft',
        measurements: 'in'
      }
    }
  })
}))

// Mock createClient from Supabase
jest.mock('@supabase/supabase-js', () => ({
  createClient: jest.fn(() => ({
    from: jest.fn(() => ({
      insert: jest.fn().mockResolvedValue({ error: null }),
      select: jest.fn().mockReturnThis(),
      update: jest.fn().mockReturnThis(),
      delete: jest.fn().mockReturnThis(),
      eq: jest.fn().mockReturnThis(),
      single: jest.fn().mockReturnThis(),
    })),
    auth: {
      getSession: jest.fn(() => Promise.resolve({ data: { session: null } })),
    },
  })),
}))