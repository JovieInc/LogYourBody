import React from 'react';
import '@testing-library/jest-dom';
import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { HeightWheelPicker, DateWheelPicker } from '../wheel-picker';

describe('HeightWheelPicker', () => {
  it('renders metric height picker', () => {
    const mockOnChange = vi.fn();
    render(<HeightWheelPicker heightInCm={180} units="metric" onHeightChange={mockOnChange} />);

    // Should show cm picker - look for the label
    expect(screen.getByText('Centimeters')).toBeInTheDocument();
  });

  it('renders imperial height picker', () => {
    const mockOnChange = vi.fn();
    render(<HeightWheelPicker heightInCm={180} units="imperial" onHeightChange={mockOnChange} />);

    // Should show feet and inches pickers - look for the labels
    expect(screen.getByText('Feet')).toBeInTheDocument();
    expect(screen.getByText('Inches')).toBeInTheDocument();
  });

  it('converts height correctly between units', () => {
    const mockOnChange = vi.fn();
    const { rerender } = render(
      <HeightWheelPicker heightInCm={180} units="metric" onHeightChange={mockOnChange} />,
    );

    // 180cm should be approximately 5'11"
    rerender(<HeightWheelPicker heightInCm={180} units="imperial" onHeightChange={mockOnChange} />);

    // Check if the conversion is displayed correctly
    // 180cm = 70.87 inches ≈ 5'11"
    expect(screen.getByText('5 ft')).toBeInTheDocument();
  });
});

describe('DateWheelPicker', () => {
  it('renders date picker with correct values', () => {
    const mockOnChange = vi.fn();
    const testDate = new Date(1990, 0, 15); // Jan 15, 1990

    render(<DateWheelPicker date={testDate} onDateChange={mockOnChange} />);

    // Should show month, day, and year pickers
    expect(screen.getByText('January')).toBeInTheDocument();
    expect(screen.getByText('15')).toBeInTheDocument();
    expect(screen.getByText('1990')).toBeInTheDocument();
  });

  it('includes appropriate year range', () => {
    const mockOnChange = vi.fn();
    const currentYear = new Date().getFullYear();
    const testDate = new Date(2000, 0, 1);

    render(<DateWheelPicker date={testDate} onDateChange={mockOnChange} />);

    // Should include years from 1920 to current year
    const yearOptions = screen.getAllByRole('option', { hidden: true });
    const years = yearOptions
      .map((option) => option.textContent)
      .filter((text) => text && /^\d{4}$/.test(text));

    // Check that it includes 1920 and current year
    expect(years).toContain('1920');
    expect(years).toContain(currentYear.toString());

    // Should be in descending order (current year first)
    const yearNums = years.map((y) => parseInt(y!));
    expect(yearNums[0]).toBe(currentYear);
    expect(yearNums[yearNums.length - 1]).toBe(1920);
  });
});
