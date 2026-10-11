/**
 * Design System Tokens for LogYourBody
 * Centralized design tokens for consistent UI across all components
 */

export const tokens = {
  // Typography
  typography: {
    // Profile screen typography tokens
    profileValue: {
      fontSize: '32pt',
      fontWeight: '600', // semibold
      lineHeight: '1.1',
    },
    profileLabel: {
      fontSize: '14pt',
      fontWeight: '500',
      textTransform: 'uppercase' as const,
      opacity: '0.8', // AA compliant (was 0.6)
      letterSpacing: '0.05em',
    },
    profileUnit: {
      fontSize: '28pt',
      fontWeight: '500',
      opacity: '0.9',
    },
    bodyFatOverlay: {
      fontSize: '16pt',
      fontWeight: '500',
      textAlign: 'center' as const,
    },
    attributeLabel: {
      fontSize: '12pt',
      fontWeight: '500',
      textTransform: 'uppercase' as const,
      opacity: '0.8',
      letterSpacing: '0.05em',
    },
    attributeValue: {
      fontSize: '14pt',
      fontWeight: '600',
    },
    timelineLabel: {
      fontSize: '12pt',
      fontWeight: '500',
      opacity: '0.8',
    },
    timelineValue: {
      fontSize: '16pt',
      fontWeight: '600',
    },
  },

  // Spacing
  spacing: {
    statsGridGap: '16pt',
    sectionGap: '24pt',
    containerPadding: '20pt',
    safeAreaPadding: 'env(safe-area-inset-bottom)',
  },

  // Colors (Linear Design System)
  colors: {
    primary: '#5E6AD2', // Linear purple
    foreground: '#F7F8F8', // Linear text
    background: '#0A0B0D', // Linear bg
    muted: '#8B909B', // Linear text tertiary
    border: '#1F2023', // Linear border
    // Linear text colors
    text: {
      primary: '#F7F8F8', // Linear text
      secondary: '#9CA0A8', // Linear text secondary
      tertiary: '#8B909B', // Linear text tertiary
    },
  },

  // Animation
  animation: {
    spring: {
      type: 'spring' as const,
      damping: 20,
      stiffness: 300,
    },
    fadeIn: {
      duration: 0.25,
      ease: 'easeOut' as const,
    },
    slideIn: {
      duration: 0.3,
      ease: 'easeInOut' as const,
    },
  },

  // Breakpoints
  breakpoints: {
    mobile: '0px',
    tablet: '768px',
    desktop: '1024px',
    wide: '1280px',
  },

  // Component-specific tokens
  components: {
    statsGrid: {
      mobile: {
        columns: 2,
        gap: '16pt',
        alignment: 'center',
      },
      desktop: {
        columns: 1,
        gap: '20pt',
        alignment: 'left',
      },
    },
    attributeRow: {
      columns: 3,
      gap: '16pt',
      minHeight: '60pt',
    },
    avatar: {
      containerHeight: '400pt',
      overlayPosition: 'absolute',
      overlayTop: '20pt',
    },
    timeline: {
      trackHeight: '8pt',
      thumbSize: '24pt',
      labelSpacing: '12pt',
      containerPadding: '16pt',
    },
    tabs: {
      height: '48pt',
      borderRadius: '12pt',
      activeOpacity: 1,
      inactiveOpacity: 0.7,
    },
  },

  // Accessibility
  accessibility: {
    minimumTapTarget: '44pt',
    focusRingWidth: '2px',
    focusRingColor: 'hsl(var(--primary))',
    contrastRatio: {
      normal: 4.5,
      large: 3,
      minimum: 3,
    },
  },
} as const;

// Utility functions for design tokens
export const getTypographyStyle = (tokenPath: string) => {
  const pathParts = tokenPath.split('.');
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let value: any = tokens.typography;

  for (const part of pathParts) {
    value = value[part];
  }

  return value;
};

export const getSpacing = (tokenName: keyof typeof tokens.spacing) => {
  return tokens.spacing[tokenName];
};

export const getColor = (tokenPath: string) => {
  const pathParts = tokenPath.split('.');
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let value: any = tokens.colors;

  for (const part of pathParts) {
    value = value[part];
  }

  return value;
};

export const getAnimation = (tokenName: keyof typeof tokens.animation) => {
  return tokens.animation[tokenName];
};

// Tailwind class generators based on tokens - Ultra compact mobile layout
export const tw = {
  profileValue: 'text-xl md:text-3xl lg:text-4xl font-semibold leading-none text-linear-text',
  profileLabel:
    'text-[10px] md:text-sm font-medium uppercase opacity-70 tracking-wider text-linear-text-secondary',
  profileUnit: 'text-lg md:text-2xl font-medium opacity-80 text-linear-text-secondary',
  bodyFatOverlay: 'text-sm md:text-base font-medium text-center text-linear-text',
  attributeLabel:
    'text-[9px] md:text-xs font-medium uppercase opacity-70 tracking-wider text-linear-text-tertiary',
  attributeValue: 'text-[11px] md:text-sm font-semibold text-linear-text',
  timelineLabel: 'text-[9px] md:text-xs font-medium opacity-70 text-linear-text-tertiary',
  timelineValue: 'text-xs md:text-base font-semibold text-linear-text',

  // Layout utilities - ultra compact mobile with minimal gaps
  statsGrid: 'grid grid-cols-2 gap-2 md:flex md:flex-col md:gap-4',
  attributeRow: 'grid grid-cols-3 gap-2 min-h-[32px] md:min-h-[48px]',
  avatarContainer: 'relative h-[35vh] max-h-[280px] md:h-full w-full',
  safeArea: 'pb-[env(safe-area-inset-bottom)]',

  // Interactive states
  focus: 'focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2',
  hover: 'hover:opacity-80 transition-opacity duration-200',
  active: 'active:scale-95 transition-transform duration-100',
} as const;
