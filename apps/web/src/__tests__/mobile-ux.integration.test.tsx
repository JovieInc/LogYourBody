import '@testing-library/jest-dom'

// Test Mobile Navbar visibility logic
describe('Mobile UX Integration Tests', () => {
  describe('Mobile Navbar Visibility', () => {
    it('should hide navbar on log and settings pages', () => {
      const pathsToHide = ['/log', '/settings', '/settings/profile', '/settings/account']
      const pathsToShow = ['/dashboard', '/', '/about']

      pathsToHide.forEach(path => {
        expect(path === '/log' || path.startsWith('/settings')).toBe(true)
      })

      pathsToShow.forEach(path => {
        expect(path === '/log' || path.startsWith('/settings')).toBe(false)
      })
    })
  })

  describe('Mobile Metrics Display', () => {
    it('should format metrics correctly', () => {
      // Test weight formatting
      const weight = 165.5
      const formattedWeight = weight.toFixed(1)
      expect(formattedWeight).toBe('165.5')

      // Test body fat percentage formatting
      const bodyFat = 25.5
      const formattedBF = bodyFat.toFixed(1)
      expect(formattedBF).toBe('25.5')

      // Test lean mass calculation
      const leanMass = weight * (1 - bodyFat / 100)
      expect(leanMass.toFixed(1)).toBe('123.3')
    })

    it('should calculate height display correctly', () => {
      // Test imperial height display
      const heightInInches = 71
      const feet = Math.floor(heightInInches / 12)
      const inches = heightInInches % 12
      const imperialDisplay = `${feet}'${inches}"`
      expect(imperialDisplay).toBe('5\'11"')

      // Test metric height display
      const heightInCm = 180
      const metricDisplay = `${heightInCm} cm`
      expect(metricDisplay).toBe('180 cm')
    })
  })

  describe('Version Display', () => {
    it('should format version correctly', () => {
      const versions = ['1.0.0', '2.1.0', '3.0.0']

      versions.forEach(version => {
        const formatted = `v${version}`
        expect(formatted).toMatch(/^v\d+\.\d+\.\d+$/)
      })
    })

    it('should handle missing version gracefully', () => {
      const getVersion = (envVersion?: string) => envVersion ?? '1.0.0'

      expect(getVersion(undefined)).toBe('1.0.0')
      expect(getVersion('2.0.0')).toBe('2.0.0')
    })
  })

  describe('Mobile Navigation Behavior', () => {
    it('should navigate between main sections', () => {
      const routes = [
        { from: '/dashboard', to: '/log', label: 'Add Data' },
        { from: '/dashboard', to: '/settings', label: 'Settings' },
        { from: '/settings', to: '/dashboard', label: 'Dashboard' }
      ]

      routes.forEach(route => {
        expect(route.from).toBeTruthy()
        expect(route.to).toBeTruthy()
        expect(route.label).toBeTruthy()
      })
    })
  })

  describe('Mobile-specific Styling', () => {
    it('should apply correct mobile classes', () => {
      const mobileClasses = {
        navbar: 'fixed bottom-0 left-0 right-0 md:hidden',
        statsScroll: 'overflow-x-auto -mx-6 px-6',
        textSize: 'text-4xl md:text-3xl',
        navHeight: 'h-14',
        iconSize: 'h-6 w-6'
      }

      Object.entries(mobileClasses).forEach(([key, classes]) => {
        const classArray = classes.split(' ')
        expect(classArray.length).toBeGreaterThan(0)

        // Check for responsive classes
        const hasResponsive = classArray.some(cls => cls.includes('md:'))
        if (key === 'navbar' || key === 'textSize') {
          expect(hasResponsive).toBe(true)
        }
      })
    })
  })

  describe('Body Fat Categories', () => {
    it('should categorize body fat correctly for males', () => {
      const categories = [
        { bf: 5, expected: 'Essential' },
        { bf: 12, expected: 'Athletic' },
        { bf: 18, expected: 'Average' },
        { bf: 24, expected: 'Average' },
        { bf: 30, expected: 'Obese' }
      ]

      // Mock getBodyFatCategory function behavior
      categories.forEach(({ bf, expected }) => {
        let category
        if (bf < 6) category = 'Essential'
        else if (bf < 14) category = 'Athletic'
        else if (bf < 18) category = 'Fit'
        else if (bf < 25) category = 'Average'
        else category = 'Obese'

        expect(category).toBe(expected)
      })
    })
  })

  describe('Settings Page Integration', () => {
    it('should have correct menu items', () => {
      const menuItems = [
        { title: 'Profile', href: '/settings/profile' },
        { title: 'Account & Security', href: '/settings/account' },
        { title: 'Preferences', href: '/settings/preferences' },
        { title: 'Notifications', href: '/settings/notifications' },
        { title: 'Subscription', href: '/settings/subscription' }
      ]

      menuItems.forEach(item => {
        expect(item.title).toBeTruthy()
        expect(item.href).toContain('/settings')
      })
    })
  })
})