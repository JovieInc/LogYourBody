'use client';

import React, { useState, useRef, useEffect, useCallback } from 'react';
import { Input } from '@shared-ui/atoms/input';
import { cn } from '@shared-lib/utils';

interface SmartEmailInputProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type' | 'onChange'> {
  value: string;
  onChange: (value: string) => void;
  onValidationChange?: (isValid: boolean) => void;
  showSuggestions?: boolean;
}

const commonDomains = [
  'gmail.com',
  'yahoo.com',
  'outlook.com',
  'hotmail.com',
  'icloud.com',
  'aol.com',
  'protonmail.com',
  'me.com',
  'mac.com',
];

const domainCorrections: Record<string, string> = {
  'gmial.com': 'gmail.com',
  'gmil.com': 'gmail.com',
  'gmai.com': 'gmail.com',
  'yahooo.com': 'yahoo.com',
  'yaho.com': 'yahoo.com',
  'outloo.com': 'outlook.com',
  'outlok.com': 'outlook.com',
  'hotmial.com': 'hotmail.com',
  'hotmai.com': 'hotmail.com',
  'iclould.com': 'icloud.com',
  'icoud.com': 'icloud.com',
};

export function SmartEmailInput({
  value,
  onChange,
  onValidationChange,
  showSuggestions = true,
  className,
  ...props
}: SmartEmailInputProps) {
  const [isFocused, setIsFocused] = useState(false);
  const [showDomainSuggestions, setShowDomainSuggestions] = useState(false);
  const [selectedSuggestion, setSelectedSuggestion] = useState(-1);
  const [isValid, setIsValid] = useState(true);
  const [showError, setShowError] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const suggestionsRef = useRef<HTMLDivElement>(null);

  // Parse email parts
  const atIndex = value.indexOf('@');
  const localPart = atIndex > -1 ? value.substring(0, atIndex) : value;
  const domainPart = atIndex > -1 ? value.substring(atIndex + 1) : '';

  // Get domain suggestions
  const getDomainSuggestions = useCallback(() => {
    if (!domainPart || domainPart.length === 0) return commonDomains;

    const lowercaseDomain = domainPart.toLowerCase();

    // Check for typos first
    if (domainCorrections[lowercaseDomain]) {
      return [domainCorrections[lowercaseDomain]];
    }

    // Filter common domains
    return commonDomains.filter(
      (domain) => domain.toLowerCase().startsWith(lowercaseDomain) && domain !== lowercaseDomain,
    );
  }, [domainPart]);

  const suggestions = getDomainSuggestions();

  // Validate email
  useEffect(() => {
    const validateEmail = () => {
      // Basic validation
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      const valid = value.length === 0 || emailRegex.test(value);
      setIsValid(valid);
      onValidationChange?.(valid);

      // Only show error after blur
      if (!valid && showError) {
        setShowError(true);
      }
    };

    validateEmail();
  }, [value, showError, onValidationChange]);

  // Handle keyboard navigation
  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (!showDomainSuggestions || suggestions.length === 0) return;

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        setSelectedSuggestion((prev) => (prev < suggestions.length - 1 ? prev + 1 : 0));
        break;
      case 'ArrowUp':
        e.preventDefault();
        setSelectedSuggestion((prev) => (prev > 0 ? prev - 1 : suggestions.length - 1));
        break;
      case 'Enter':
      case 'Tab':
        if (selectedSuggestion >= 0 && suggestions[selectedSuggestion]) {
          e.preventDefault();
          onChange(`${localPart}@${suggestions[selectedSuggestion]}`);
          setShowDomainSuggestions(false);
        }
        break;
      case 'Escape':
        setShowDomainSuggestions(false);
        setSelectedSuggestion(-1);
        break;
    }
  };

  // Handle input change
  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value;
    onChange(newValue);

    // Show suggestions when @ is typed
    if (newValue.includes('@') && !value.includes('@')) {
      setShowDomainSuggestions(true);
    }

    // Hide suggestions when domain is complete
    if (newValue.includes('@') && newValue.split('@')[1]?.includes('.')) {
      setShowDomainSuggestions(false);
    }
  };

  // Handle suggestion click
  const handleSuggestionClick = (domain: string) => {
    onChange(`${localPart}@${domain}`);
    setShowDomainSuggestions(false);
    inputRef.current?.focus();
  };

  const displayValue = value;

  return (
    <div className="relative">
      <Input
        ref={inputRef}
        type="email"
        value={displayValue}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        onFocus={() => {
          setIsFocused(true);
          setShowError(false);
          if (atIndex > -1 && !domainPart.includes('.')) {
            setShowDomainSuggestions(true);
          }
        }}
        onBlur={() => {
          setIsFocused(false);
          setShowError(!isValid && value.length > 0);
          // Delay to allow clicking suggestions
          setTimeout(() => setShowDomainSuggestions(false), 200);
        }}
        aria-invalid={showError && !isValid}
        className={cn(
          'transition-all duration-200',
          showError && !isValid && 'border-red-500 focus:border-red-500',
          isValid && value.length > 0 && isFocused && 'border-green-500',
          className,
        )}
        {...props}
      />

      {/* Domain suggestions - Linear style */}
      {showSuggestions && showDomainSuggestions && suggestions.length > 0 && atIndex > -1 && (
        <div
          ref={suggestionsRef}
          className="bg-linear-card border-linear-border absolute z-50 mt-2 w-full overflow-hidden rounded-lg border shadow-xl"
          role="listbox"
          aria-label="Email domain suggestions"
        >
          {suggestions.map((domain, index) => (
            <button
              key={domain}
              type="button"
              onClick={() => handleSuggestionClick(domain)}
              className={cn(
                'w-full px-4 py-3 text-left transition-colors duration-150',
                'hover:bg-linear-purple/10 focus:bg-linear-purple/10 focus:outline-none',
                'border-linear-border border-b last:border-0',
                selectedSuggestion === index && 'bg-linear-purple/10',
              )}
              role="option"
              aria-selected={selectedSuggestion === index}
            >
              <span className="text-linear-text-secondary text-sm">{localPart}@</span>
              <span className="text-linear-text font-medium">{domain}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
