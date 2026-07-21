import type { Config } from 'tailwindcss';

export default {
  content: [
    './pages/**/*.{ts,tsx}',
    './components/**/*.{ts,tsx}',
    './app/**/*.{ts,tsx}',
    './src/**/*.{ts,tsx}',
  ],
  theme: {
    container: {
      center: true,
      padding: '2rem',
      screens: {
        '2xl': '1400px',
      },
    },
    extend: {
      colors: {
        // Jovie System B marketing tokens
        'system-bg': '#050506',
        'system-surface': '#0A0B0D',
        'system-panel': '#0D0F12',
        'system-border': 'rgba(255,255,255,0.10)',
        'system-text': '#FFFFFF',
        'system-muted': 'rgba(255,255,255,0.62)',
        'system-subtle': 'rgba(255,255,255,0.42)',
        'system-blue': '#60A5FA',
        'system-green': '#6EE7B7',
        'system-amber': '#FDE68A',
        'system-rose': '#FDA4AF',
        // Linear-inspired design system
        'linear-purple': '#5E6AD2',
        'linear-cyan': '#5de7ff', // Beautiful Linear accent color
        'linear-bg': '#000000',
        'linear-card': '#0B0B0B',
        'linear-border': '#2A2A2C',
        'linear-text': '#F7F8F8',
        'linear-text-secondary': '#9CA0A8',
        'linear-text-tertiary': '#6E7178',
        // Core accent colors for rotation
        'accent-cyan': '#5de7ff', // Linear cyan
        'accent-purple': '#5E6AD2', // Linear purple
        'accent-green': '#2F9E44', // Success green
        'accent-orange': '#FF9800', // Warning orange
        'accent-pink': '#ec4899', // Pink accent
        // Legacy colors (kept for backward compatibility)
        'magic-blue': '#5E6AD2',
        'mercury-white': '#F4F5F8',
        'nordic-gray': '#222326',
        'text-secondary': '#95A2B3',
        // Existing colors
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
        sidebar: {
          DEFAULT: 'hsl(var(--sidebar-background))',
          foreground: 'hsl(var(--sidebar-foreground))',
          primary: 'hsl(var(--sidebar-primary))',
          'primary-foreground': 'hsl(var(--sidebar-primary-foreground))',
          accent: 'hsl(var(--sidebar-accent))',
          'accent-foreground': 'hsl(var(--sidebar-accent-foreground))',
          border: 'hsl(var(--sidebar-border))',
          ring: 'hsl(var(--sidebar-ring))',
        },
      },
      fontFamily: {
        inter: ['Inter', 'system-ui', 'sans-serif'],
      },
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      height: {
        '14pt': '18.67px',
        '16pt': '21.33px',
        '28pt': '37.33px',
        '44pt': '58.67px',
        '48pt': '64px',
        '56pt': '74.67px',
      },
      fontSize: {
        '14pt': ['18.67px', { lineHeight: '1.5' }],
        '16pt': ['21.33px', { lineHeight: '1.5' }],
        '28pt': ['37.33px', { lineHeight: '1.2' }],
      },
      padding: {
        safe: 'env(safe-area-inset-bottom)',
        'safe-top': 'env(safe-area-inset-top)',
        'safe-bottom': 'env(safe-area-inset-bottom)',
        'safe-left': 'env(safe-area-inset-left)',
        'safe-right': 'env(safe-area-inset-right)',
      },
      paddingBottom: {
        safe: 'env(safe-area-inset-bottom)',
      },
      paddingLeft: {
        safe: 'env(safe-area-inset-left)',
      },
      paddingRight: {
        safe: 'env(safe-area-inset-right)',
      },
      keyframes: {
        'accordion-down': {
          from: {
            height: '0',
          },
          to: {
            height: 'var(--radix-accordion-content-height)',
          },
        },
        'accordion-up': {
          from: {
            height: 'var(--radix-accordion-content-height)',
          },
          to: {
            height: '0',
          },
        },
      },
      animation: {
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
      },
    },
  },
} satisfies Config;
