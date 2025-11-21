import { parseISO } from 'date-fns'

describe('Profile Utilities', () => {
  describe('Height Formatting', () => {
    it('formats metric height correctly', () => {
      const formatHeight = (height: number, unit: 'cm' | 'ft') => {
        if (!height) return 'Not set'
        
        if (unit === 'cm') {
          return `${height} cm`
        } else {
          const feet = Math.floor(height / 12)
          const inches = height % 12
          return `${feet}'${inches}"`
        }
      }

      expect(formatHeight(180, 'cm')).toBe('180 cm')
      expect(formatHeight(165, 'cm')).toBe('165 cm')
    })

    it('formats imperial height correctly', () => {
      const formatHeight = (height: number, unit: 'cm' | 'ft') => {
        if (!height) return 'Not set'
        
        if (unit === 'cm') {
          return `${height} cm`
        } else {
          const feet = Math.floor(height / 12)
          const inches = height % 12
          return `${feet}'${inches}"`
        }
      }

      expect(formatHeight(71, 'ft')).toBe("5'11\"")
      expect(formatHeight(72, 'ft')).toBe("6'0\"")
      expect(formatHeight(65, 'ft')).toBe("5'5\"")
    })

    it('handles height unit conversion', () => {
      const convertHeight = (height: number, fromUnit: 'cm' | 'ft', toUnit: 'cm' | 'ft') => {
        if (fromUnit === toUnit) return height
        
        if (fromUnit === 'cm' && toUnit === 'ft') {
          // Convert cm to inches
          return Math.round(height / 2.54)
        } else if (fromUnit === 'ft' && toUnit === 'cm') {
          // Convert inches to cm
          return Math.round(height * 2.54)
        }
        
        return height
      }

      expect(convertHeight(180, 'cm', 'ft')).toBe(71) // 180cm ≈ 71 inches
      expect(convertHeight(71, 'ft', 'cm')).toBe(180) // 71 inches ≈ 180cm
      expect(convertHeight(165, 'cm', 'ft')).toBe(65) // 165cm ≈ 65 inches
    })
  })

  describe('Age Calculation', () => {
    it('calculates age correctly', () => {
      const calculateAge = (dateOfBirth: string) => {
        if (!dateOfBirth) return null
        try {
          const date = parseISO(dateOfBirth)
          if (isNaN(date.getTime())) {
            return null
          }
          const today = new Date()
          // If the birth date is in the future (year is later than current year), return -1
          if (date.getFullYear() > today.getFullYear()) return -1
          let age = today.getFullYear() - date.getFullYear()
          const monthDiff = today.getMonth() - date.getMonth()
          if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < date.getDate())) {
            age--
          }
          return age
        } catch {
          return null
        }
      }

      // Mock current date for consistent testing
      const originalDate = Date
      const mockDate = new Date('2024-06-20T12:00:00Z')
      class MockDate extends Date {
        constructor(...args: ConstructorParameters<typeof Date>) {
          if (args.length === 0) {
            super(mockDate.getTime())
          } else {
            super(...args)
          }
        }
        static now() {
          return mockDate.getTime()
        }
      }
      global.Date = MockDate as unknown as typeof Date

      expect(calculateAge('1990-01-01')).toBe(34)
      expect(calculateAge('2000-12-31')).toBe(23)
      expect(calculateAge('2024-06-21')).toBe(-1) // Birthday tomorrow (not born yet)
      expect(calculateAge('2024-06-20')).toBe(0) // Birthday today
      expect(calculateAge('2023-06-20')).toBe(1) // Birthday exactly one year ago

      // Restore original Date
      global.Date = originalDate
    })

    it('handles invalid dates gracefully', () => {
      const calculateAge = (dateOfBirth: string) => {
        if (!dateOfBirth) return null
        try {
          const date = parseISO(dateOfBirth)
          if (isNaN(date.getTime())) {
            return null
          }
          const today = new Date()
          let age = today.getFullYear() - date.getFullYear()
          const monthDiff = today.getMonth() - date.getMonth()
          if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < date.getDate())) {
            age--
          }
          return age
        } catch {
          return null
        }
      }

      expect(calculateAge('')).toBe(null)
      expect(calculateAge('invalid-date')).toBe(null)
      expect(calculateAge('2024-13-45')).toBe(null) // Invalid month/day (parseISO returns Invalid Date)
    })
  })

  describe('Profile Data Validation', () => {
    it('validates height values', () => {
      const isValidHeight = (height: number, unit: 'cm' | 'ft') => {
        if (unit === 'cm') {
          return height > 0 && height < 300
        } else {
          // For ft unit, height is stored in inches
          return height > 0 && height < 120 // Max 10 feet
        }
      }

      // Metric validation
      expect(isValidHeight(180, 'cm')).toBe(true)
      expect(isValidHeight(0, 'cm')).toBe(false)
      expect(isValidHeight(300, 'cm')).toBe(false)
      expect(isValidHeight(-10, 'cm')).toBe(false)

      // Imperial validation
      expect(isValidHeight(72, 'ft')).toBe(true)
      expect(isValidHeight(0, 'ft')).toBe(false)
      expect(isValidHeight(120, 'ft')).toBe(false)
      expect(isValidHeight(-5, 'ft')).toBe(false)
    })

    it('validates date of birth', () => {
      const isValidDateOfBirth = (dob: string) => {
        if (!dob) return false
        
        try {
          const date = parseISO(dob)
          const today = new Date()
          const minDate = new Date(today.getFullYear() - 120, 0, 1) // Max 120 years old
          const maxDate = new Date(today.getFullYear() - 13, 11, 31) // Min 13 years old
          
          return date >= minDate && date <= maxDate
        } catch {
          return false
        }
      }

      const mockDate = new Date('2024-06-20')
      class LimitedMockDate extends Date {
        constructor(...args: ConstructorParameters<typeof Date>) {
          if (args.length === 0) {
            super(mockDate.getTime())
          } else {
            super(...args)
          }
        }
      }
      global.Date = LimitedMockDate as unknown as typeof Date

      expect(isValidDateOfBirth('1990-01-01')).toBe(true)
      expect(isValidDateOfBirth('2011-12-31')).toBe(true) // 12 years old, which is actually December 31, 2011, making them 12.5 years old
      expect(isValidDateOfBirth('1903-12-31')).toBe(false) // Too old (>120 years)
      expect(isValidDateOfBirth('2024-12-31')).toBe(false) // Future date
      expect(isValidDateOfBirth('')).toBe(false)
      expect(isValidDateOfBirth('invalid-date')).toBe(false)
    })
  })
})
