// Learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom';
import React from 'react';

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
}));

// Mock Supabase client
jest.mock('@/lib/supabase/client', () => {
  const client = {
    auth: {
      getSession: jest.fn(() => Promise.resolve({ data: { session: null } })),
      getUser: jest.fn(() => Promise.resolve({ data: { user: null } })),
      signUp: jest.fn(),
      signOut: jest.fn(() => Promise.resolve({ error: null })),
      signInWithOAuth: jest.fn(() => Promise.resolve({ error: null })),
      exchangeCodeForSession: jest.fn(() => Promise.resolve({ error: null })),
      updateUser: jest.fn(() => Promise.resolve({ error: null })),
      onAuthStateChange: jest.fn(() => ({
        data: { subscription: { unsubscribe: jest.fn() } },
      })),
    },
    storage: {
      from: jest.fn(() => ({
        upload: jest.fn(() => Promise.resolve({ error: null })),
        getPublicUrl: jest.fn(() => ({ data: { publicUrl: 'https://example.com/avatar.jpg' } })),
      })),
    },
    from: jest.fn(() => ({
      select: jest.fn(() => ({ limit: jest.fn(() => Promise.resolve({ error: null })) })),
    })),
  };

  return {
    createClient: jest.fn(() => client),
    supabase: client,
    getSupabaseEnvironment: jest.fn(() => 'test'),
    validateSupabaseKeys: jest.fn(() => ({
      url: { exists: true, valid: true, value: 'https://test.supabase.co' },
      anonKey: { exists: true, valid: true, value: 'test-key' },
    })),
    testSupabaseConnection: jest.fn(() =>
      Promise.resolve({ success: true, message: 'Connected successfully' }),
    ),
  };
});

// Mock indexedDB and related APIs
if (typeof globalThis !== 'undefined') {
  // Create a mock IDBRequest with event listener support
  class MockIDBRequest {
    constructor() {
      this.onsuccess = null;
      this.onerror = null;
      this.result = null;
      this.error = null;
      this.readyState = 'pending';
    }

    addEventListener(event, handler) {
      if (event === 'success') this.onsuccess = handler;
      if (event === 'error') this.onerror = handler;
    }

    removeEventListener() {}
  }

  // Set up global IndexedDB mocks
  globalThis.IDBRequest = MockIDBRequest;
  globalThis.IDBDatabase = jest.fn();
  globalThis.IDBTransaction = jest.fn();
  globalThis.IDBObjectStore = jest.fn();
  globalThis.IDBIndex = jest.fn();
  globalThis.IDBCursor = jest.fn();
  globalThis.IDBKeyRange = {
    bound: jest.fn(),
    lowerBound: jest.fn(),
    upperBound: jest.fn(),
    only: jest.fn(),
  };

  globalThis.indexedDB = {
    open: jest.fn(() => {
      const request = new MockIDBRequest();
      request.result = {
        transaction: jest.fn(),
        close: jest.fn(),
        objectStoreNames: { contains: jest.fn(() => false) },
        createObjectStore: jest.fn(),
      };
      setTimeout(() => {
        if (request.onsuccess) request.onsuccess({ target: request });
      }, 0);
      return request;
    }),
    deleteDatabase: jest.fn(() => new MockIDBRequest()),
  };
}

// Mock window.matchMedia only if window is defined
if (typeof window !== 'undefined') {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation((query) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: jest.fn(), // deprecated
      removeListener: jest.fn(), // deprecated
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      dispatchEvent: jest.fn(),
    })),
  });

  // Also add window.location.origin for tests - don't delete, just extend
  if (!window.location.origin) {
    Object.defineProperty(window.location, 'origin', {
      value: 'http://localhost:3000',
      writable: true,
      configurable: true,
    });
  }
}

// Add pointer events polyfill for Radix UI only if Element is defined
if (typeof Element !== 'undefined') {
  if (!Element.prototype.hasPointerCapture) {
    Element.prototype.hasPointerCapture = jest.fn();
  }
  if (!Element.prototype.setPointerCapture) {
    Element.prototype.setPointerCapture = jest.fn();
  }
  if (!Element.prototype.releasePointerCapture) {
    Element.prototype.releasePointerCapture = jest.fn();
  }
}

// Mock date-fns to avoid timezone issues in tests
jest.mock('date-fns', () => ({
  ...jest.requireActual('date-fns'),
  format: (date, formatStr) => {
    const actual = jest.requireActual('date-fns');
    if (formatStr === 'yyyy-MM-dd' && typeof date === 'string') {
      return date; // Return the string as-is for DB formatting
    }
    return actual.format(date, formatStr);
  },
}));

// Mock product auth context before individual test overrides.
jest.mock('@/contexts/ProductAuthContext', () => ({
  ProductAuthProvider: ({ children }) => children,
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
}));

// Mock framer-motion
jest.mock('framer-motion', () => ({
  motion: {
    div: ({ children, ...props }) => {
      const restProps = { ...props };
      delete restProps.initial;
      delete restProps.animate;
      delete restProps.exit;
      delete restProps.transition;
      return React.createElement('div', restProps, children);
    },
    button: ({ children, ...props }) => {
      const restProps = { ...props };
      delete restProps.initial;
      delete restProps.animate;
      delete restProps.exit;
      delete restProps.transition;
      delete restProps.whileHover;
      delete restProps.whileTap;
      return React.createElement('button', restProps, children);
    },
    span: ({ children, ...props }) => {
      const restProps = { ...props };
      delete restProps.initial;
      delete restProps.animate;
      delete restProps.exit;
      delete restProps.transition;
      return React.createElement('span', restProps, children);
    },
  },
  AnimatePresence: ({ children }) => children,
}));

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
        measurements: 'in',
      },
    },
  }),
}));

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
}));
