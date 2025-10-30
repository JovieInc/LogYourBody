import React from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import { publicEnv } from "@/env";

interface StepContainerProps {
  children: React.ReactNode;
  className?: string;
}

export function StepContainer({ children, className }: StepContainerProps) {
  const isTestEnv = publicEnv.NODE_ENV === "test";
  
  return isTestEnv ? (
    <div className={cn("space-y-8", className)}>
      {children}
    </div>
  ) : (
    <motion.div
      className={cn("space-y-8", className)}
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ duration: 0.25, type: "spring", damping: 20 }}
    >
      {children}
    </motion.div>
  );
}

interface StepHeaderProps {
  icon: React.ReactNode;
  title: string;
  subtitle?: string;
  iconBgColor?: string;
  iconColor?: string;
}

export function StepHeader({
  icon,
  title,
  subtitle,
  iconBgColor = "bg-linear-purple/10",
  iconColor = "text-linear-purple",
}: StepHeaderProps) {
  // Use regular div in test environment to avoid motion prop warnings
  const isTestEnv = publicEnv.NODE_ENV === "test";
  
  return (
    <div className="space-y-4 text-center">
      {isTestEnv ? (
        <div
          className={cn(
            "mx-auto flex h-20 w-20 items-center justify-center rounded-3xl",
            iconBgColor
          )}
        >
          <div className={cn("h-10 w-10", iconColor)}>{icon}</div>
        </div>
      ) : (
        <motion.div
          className={cn(
            "mx-auto flex h-20 w-20 items-center justify-center rounded-3xl",
            iconBgColor
          )}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
        >
          <div className={cn("h-10 w-10", iconColor)}>{icon}</div>
        </motion.div>
      )}

      <div>
        <h1 className="mb-2 text-3xl font-bold text-linear-text">{title}</h1>
        {subtitle && (
          <p className="text-lg text-linear-text-secondary">{subtitle}</p>
        )}
      </div>
    </div>
  );
}

interface QuickPresetsProps<T = unknown> {
  presets: Array<{ label: string; value: T }>;
  selectedValue: T;
  onSelect: (value: T) => void;
  formatLabel?: (preset: { label: string; value: T }) => string;
  className?: string;
}

export function QuickPresets<T = unknown>({
  presets,
  selectedValue,
  onSelect,
  formatLabel = (preset) => preset.label,
  className,
}: QuickPresetsProps<T>) {
  const isTestEnv = publicEnv.NODE_ENV === "test";
  
  const content = (
    <>
      <p className="text-center text-sm font-medium text-linear-text-tertiary">
        Quick presets
      </p>
      <div className="scrollbar-hide flex gap-2 overflow-x-auto pb-2">
        {presets.map((preset, index) => {
          const buttonProps = {
            onClick: () => onSelect(preset.value),
            className: cn(
              "flex-shrink-0 rounded-xl border px-4 py-3 font-medium transition-all duration-200",
              selectedValue === preset.value
                ? "border-linear-purple bg-linear-purple text-white"
                : "border-linear-border bg-linear-card text-linear-text hover:bg-linear-border/50"
            )
          };

          return isTestEnv ? (
            <button key={index} {...buttonProps}>
              {formatLabel(preset)}
            </button>
          ) : (
            <motion.button key={index} {...buttonProps} whileTap={{ scale: 0.95 }}>
              {formatLabel(preset)}
            </motion.button>
          );
        })}
      </div>
    </>
  );

  return isTestEnv ? (
    <div className={cn("space-y-3", className)}>
      {content}
    </div>
  ) : (
    <motion.div
      className={cn("space-y-3", className)}
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.4, duration: 0.25 }}
    >
      {content}
    </motion.div>
  );
}

interface FormFieldProps {
  children: React.ReactNode;
  label?: string;
  error?: string;
  helper?: string;
  className?: string;
}

export function FormField({
  children,
  label,
  error,
  helper,
  className,
}: FormFieldProps) {
  const isTestEnv = publicEnv.NODE_ENV === "test";
  
  const content = (
    <>
      {label && (
        <label className="block text-sm font-medium text-linear-text">
          {label}
        </label>
      )}
      
      {children}

      {/* Helper Text */}
      {helper && !error && (
        isTestEnv ? (
          <p className="text-center text-lg text-linear-text-secondary">
            {helper}
          </p>
        ) : (
          <motion.p
            className="text-center text-lg text-linear-text-secondary"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 10 }}
            transition={{ duration: 0.2 }}
          >
            {helper}
          </motion.p>
        )
      )}

      {/* Error Message */}
      {error && (
        isTestEnv ? (
          <p className="text-center text-red-500" role="alert">
            {error}
          </p>
        ) : (
          <motion.p
            className="text-center text-red-500"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 10 }}
            transition={{ duration: 0.2 }}
            role="alert"
          >
            {error}
          </motion.p>
        )
      )}
    </>
  );

  return isTestEnv ? (
    <div className={cn("space-y-3", className)}>
      {content}
    </div>
  ) : (
    <motion.div
      className={cn("space-y-3", className)}
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.3, duration: 0.25 }}
    >
      {content}
    </motion.div>
  );
}