import React, { useEffect } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { ArrowLeft, ArrowRight, Check, X } from 'lucide-react';
import { VisuallyHidden } from '@radix-ui/react-visually-hidden';

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogOverlay,
  DialogPortal,
  DialogTitle,
} from '../atoms/dialog';
import { cn } from '@shared-lib/utils';
import { useResponsive } from '@shared-lib/hooks/use-responsive';

interface ResponsiveFlowWrapperProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  className?: string;
  showCloseButton?: boolean;
  preventScroll?: boolean;
  fullscreenOnTablet?: boolean;
}

export function ResponsiveFlowWrapper({
  isOpen,
  onClose,
  children,
  className,
  showCloseButton = true,
  preventScroll = true,
  fullscreenOnTablet = false,
}: ResponsiveFlowWrapperProps) {
  const { isMobile, isTablet } = useResponsive();
  const isFullscreen = isMobile || (fullscreenOnTablet && isTablet);

  // Prevent body scroll when modal is open
  useEffect(() => {
    if (!preventScroll || !isOpen) return;

    const originalStyle = window.getComputedStyle(document.body).overflow;
    document.body.style.overflow = 'hidden';

    return () => {
      document.body.style.overflow = originalStyle;
    };
  }, [isOpen, preventScroll]);

  // Handle escape key
  useEffect(() => {
    if (!isOpen) return;

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen, onClose]);

  if (isFullscreen) {
    // Fullscreen mode for mobile/tablet
    return (
      <AnimatePresence mode="wait">
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: '100%' }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: '100%' }}
            transition={{ type: 'spring', damping: 25, stiffness: 300 }}
            className={cn('bg-background fixed inset-0 z-50', 'flex flex-col', className)}
          >
            {showCloseButton && (
              <button
                onClick={onClose}
                className="bg-secondary/20 text-muted-foreground hover:bg-secondary/30 hover:text-foreground absolute top-4 right-4 z-50 flex h-10 w-10 items-center justify-center rounded-full transition-colors"
                aria-label="Close"
              >
                <X className="h-5 w-5" />
              </button>
            )}
            {children}
          </motion.div>
        )}
      </AnimatePresence>
    );
  }

  // Modal mode for desktop
  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogPortal>
        <DialogOverlay className="bg-black/50 backdrop-blur-sm" />
        <DialogContent
          className={cn('max-h-[90vh] max-w-2xl overflow-hidden p-0', 'shadow-2xl', className)}
          onEscapeKeyDown={(e) => {
            e.preventDefault();
            onClose();
          }}
          onPointerDownOutside={(e) => {
            e.preventDefault();
            onClose();
          }}
        >
          <VisuallyHidden>
            <DialogTitle>Modal Content</DialogTitle>
            <DialogDescription>Interactive flow modal</DialogDescription>
          </VisuallyHidden>
          {showCloseButton && (
            <button
              onClick={onClose}
              className="bg-secondary/20 text-muted-foreground hover:bg-secondary/30 hover:text-foreground absolute top-4 right-4 z-50 flex h-10 w-10 items-center justify-center rounded-full transition-colors"
              aria-label="Close"
            >
              <X className="h-5 w-5" />
            </button>
          )}
          <div className="h-full overflow-y-auto">{children}</div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  );
}

// Common stepper navigation component
interface StepperNavigationProps {
  currentStep: number;
  totalSteps: number;
  stepTitles: string[];
  progress: number;
  onBack: () => void;
  onCancel: () => void;
  canGoBack?: boolean;
  className?: string;
}

export function StepperNavigation({
  currentStep,
  totalSteps,
  stepTitles,
  progress,
  onBack,
  onCancel,
  canGoBack = true,
  className,
}: StepperNavigationProps) {
  return (
    <div className={cn('pt-safe-top flex-shrink-0 px-6', className)}>
      {/* Navigation */}
      <div className="flex h-14 items-center justify-between">
        <button
          onClick={currentStep === 0 || !canGoBack ? onCancel : onBack}
          className="bg-linear-border/30 text-linear-text-secondary hover:bg-linear-border/50 hover:text-linear-text flex h-10 w-10 items-center justify-center rounded-full transition-colors"
          aria-label={currentStep === 0 || !canGoBack ? 'Cancel' : 'Go back'}
        >
          <ArrowLeft className="h-5 w-5" />
        </button>

        <div className="text-center">
          <div className="text-linear-text-secondary text-sm font-medium">
            Step {currentStep + 1} of {totalSteps}
          </div>
          <div className="text-linear-text text-lg font-semibold">{stepTitles[currentStep]}</div>
        </div>

        <div className="flex h-10 w-10 items-center justify-center">
          <div className="text-linear-text-secondary text-sm font-medium">
            {Math.round(progress)}%
          </div>
        </div>
      </div>

      {/* Progress Bar */}
      <div className="mt-4 mb-6">
        <div className="bg-linear-border h-2 w-full overflow-hidden rounded-full">
          <motion.div
            className="bg-linear-purple h-full rounded-full"
            initial={{ width: 0 }}
            animate={{ width: `${progress}%` }}
            transition={{ duration: 0.3, ease: 'easeOut' }}
          />
        </div>
      </div>
    </div>
  );
}

// Common footer actions component
interface StepperActionsProps {
  currentStep: number;
  totalSteps: number;
  canGoNext: boolean;
  onBack: () => void;
  onNext: () => void;
  nextLabel?: string;
  completeLabel?: string;
  className?: string;
}

export function StepperActions({
  currentStep,
  totalSteps,
  canGoNext,
  onBack,
  onNext,
  nextLabel = 'Next',
  completeLabel = 'Save Entry',
  className,
}: StepperActionsProps) {
  return (
    <div className={cn('flex-shrink-0 px-6 pt-4 pb-6', className)}>
      <div className="flex gap-3">
        {/* Back Button (hidden on first step) */}
        {currentStep > 0 && (
          <motion.button
            onClick={onBack}
            className="border-linear-border bg-linear-card text-linear-text-secondary hover:bg-linear-border/50 hover:text-linear-text h-14 flex-1 rounded-xl border font-medium transition-colors"
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95 }}
            transition={{ duration: 0.2 }}
          >
            Back
          </motion.button>
        )}

        {/* Next/Complete Button */}
        {(() => {
          const isTestEnv = typeof process !== 'undefined' && process.env.NODE_ENV === 'test';
          const buttonProps = {
            onClick: onNext,
            disabled: !canGoNext,
            className: cn(
              'flex h-14 items-center justify-center gap-2 rounded-xl font-medium transition-all duration-200',
              currentStep === 0 ? 'flex-1' : 'flex-[2]',
              canGoNext
                ? 'bg-linear-text text-linear-bg hover:bg-linear-text/90'
                : 'cursor-not-allowed border border-linear-border bg-linear-card text-linear-text-tertiary',
            ),
          };

          return isTestEnv ? (
            <button {...buttonProps}>
              {currentStep === totalSteps - 1 ? (
                <>
                  <Check className="h-5 w-5" />
                  {completeLabel}
                </>
              ) : (
                <>
                  {nextLabel}
                  <ArrowRight className="h-5 w-5" />
                </>
              )}
            </button>
          ) : (
            <motion.button {...buttonProps} whileTap={canGoNext ? { scale: 0.98 } : {}}>
              {currentStep === totalSteps - 1 ? (
                <>
                  <Check className="h-5 w-5" />
                  {completeLabel}
                </>
              ) : (
                <>
                  {nextLabel}
                  <ArrowRight className="h-5 w-5" />
                </>
              )}
            </motion.button>
          );
        })()}
      </div>
    </div>
  );
}
