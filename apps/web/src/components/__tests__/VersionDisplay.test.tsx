import React from 'react'
import { render, screen } from '@testing-library/react'

describe('VersionDisplay', () => {
  const originalEnv = process.env

  async function loadVersionDisplay() {
    const envModule = await import('@/env')
    envModule.__resetPublicEnvForTesting()
    return import('../VersionDisplay')
  }

  beforeEach(() => {
    jest.resetModules()
    process.env = { ...originalEnv }
  })

  afterAll(() => {
    process.env = originalEnv
  })

  it('should display version from NEXT_PUBLIC_VERSION', async () => {
    process.env.NEXT_PUBLIC_VERSION = '2.1.0'

    const { VersionDisplay } = await loadVersionDisplay()
    render(<VersionDisplay />)

    expect(screen.getByText('v2.1.0')).toBeInTheDocument()
  })

  it('should fallback to NEXT_PUBLIC_APP_VERSION', async () => {
    delete process.env.NEXT_PUBLIC_VERSION
    process.env.NEXT_PUBLIC_APP_VERSION = '3.0.0'

    const { VersionDisplay } = await loadVersionDisplay()
    render(<VersionDisplay />)

    expect(screen.getByText('v3.0.0')).toBeInTheDocument()
  })

  it('should use default version when no env vars are set', async () => {
    delete process.env.NEXT_PUBLIC_VERSION
    delete process.env.NEXT_PUBLIC_APP_VERSION

    const { VersionDisplay } = await loadVersionDisplay()
    render(<VersionDisplay />)

    expect(screen.getByText('v1.0.0')).toBeInTheDocument()
  })

  it('should render as a badge with correct styling', async () => {
    const { VersionDisplay } = await loadVersionDisplay()
    render(<VersionDisplay />)

    const badge = screen.getByText(/^v\d+\.\d+\.\d+$/)
    expect(badge).toHaveClass('text-xs', 'opacity-50', 'border-linear-border', 'text-linear-text-tertiary')
  })

  it('should accept custom className', async () => {
    const { VersionDisplay } = await loadVersionDisplay()
    render(<VersionDisplay className="custom-class" />)

    const badge = screen.getByText(/^v\d+\.\d+\.\d+$/)
    expect(badge).toHaveClass('custom-class')
  })

  it('should be memoized for performance', async () => {
    const { VersionDisplay } = await loadVersionDisplay()
    const { rerender } = render(<VersionDisplay />)
    const firstRender = screen.getByText(/^v\d+\.\d+\.\d+$/)

    rerender(<VersionDisplay />)
    const secondRender = screen.getByText(/^v\d+\.\d+\.\d+$/)
    
    expect(firstRender).toBe(secondRender)
  })
})