export type FooterVariant = 'auto' | 'full' | 'compact';
export type ResolvedFooterVariant = 'full' | 'compact';

export interface FooterProps {
  readonly variant?: FooterVariant;
  readonly className?: string;
}
