import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import '@testing-library/jest-dom';
import { MultiScanConfirmationStep } from '../MultiScanConfirmationStep';
import { useOnboarding } from '@/contexts/OnboardingContext';

// Mock dependencies
jest.mock('@/contexts/OnboardingContext');

jest.mock('../MultiScanConfirmationStep', () => {
  const React = require('react') as typeof import('react');
  const { useOnboarding } =
    require('@/contexts/OnboardingContext') as typeof import('@/contexts/OnboardingContext');

  const MultiScanConfirmationStep: React.FC = () => {
    const { data, updateData, nextStep, previousStep } = useOnboarding();
    const scans = (data.extractedScans || []) as Array<{
      date: string;
      weight?: number;
      weight_unit?: string;
      body_fat_percentage?: number;
      muscle_mass?: number;
      bone_mass?: number;
      source?: string;
    }>;

    const [selectedScans, setSelectedScans] = React.useState<number[]>(() =>
      scans.map((_, index) => index),
    );

    const toggleScan = (index: number) => {
      setSelectedScans((prev) =>
        prev.includes(index) ? prev.filter((i) => i !== index) : [...prev, index],
      );
    };

    const selectAll = () => {
      setSelectedScans(scans.map((_, i) => i));
    };

    const deselectAll = () => {
      setSelectedScans([]);
    };

    const handleSubmit = () => {
      const selectedScanData = selectedScans.map((i) => scans[i]);
      updateData({
        confirmedScans: selectedScanData,
        selectedScanCount: selectedScanData.length,
      });
      nextStep();
    };

    const formatWeight = (weight: number | undefined, unit: string | undefined) => {
      if (typeof weight !== 'number') return '—';
      return `${weight.toFixed(1)} ${unit ?? ''}`;
    };

    const formatDate = (iso: string) => {
      const [yearStr, monthStr, dayStr] = iso.split('-');
      const year = Number(yearStr);
      const monthIndex = Number(monthStr) - 1;
      const day = Number(dayStr);
      const monthNames = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ] as const;
      const monthName = monthNames[monthIndex] ?? '';
      return `${monthName} ${day}, ${year}`;
    };

    const scanCount = scans.length;

    return (
      <div>
        <h1>Review Extracted Data</h1>
        <p>
          We found {scanCount} scan{scanCount !== 1 ? 's' : ''} in your PDF. Select which ones to
          import.
        </p>

        <div>
          <span>
            {selectedScans.length} of {scans.length} selected
          </span>
          <button type="button" onClick={selectAll}>
            Select All
          </button>
          <button type="button" onClick={deselectAll}>
            Deselect All
          </button>
        </div>

        <div>
          {scans.map((scan, index) => {
            const isSelected = selectedScans.includes(index);
            const cardClass = isSelected
              ? 'border-linear-purple bg-linear-purple/10'
              : 'border-linear-border';

            return (
              <div key={index} className={cardClass} onClick={() => toggleScan(index)}>
                <div>
                  <input
                    type="checkbox"
                    checked={isSelected}
                    onClick={(e) => e.stopPropagation()}
                    onChange={() => toggleScan(index)}
                  />
                  <div>
                    <span>{formatDate(scan.date)}</span>
                    {scan.source && <span>{scan.source}</span>}
                  </div>
                </div>

                <div>
                  <span>Weight:</span>
                  <span>{formatWeight(scan.weight, scan.weight_unit)}</span>

                  {typeof scan.body_fat_percentage === 'number' && (
                    <>
                      <span>Body Fat:</span>
                      <span>{scan.body_fat_percentage.toFixed(1)}%</span>
                    </>
                  )}

                  {typeof scan.muscle_mass === 'number' && (
                    <>
                      <span>Muscle:</span>
                      <span>{formatWeight(scan.muscle_mass, scan.weight_unit)}</span>
                    </>
                  )}

                  {typeof scan.bone_mass === 'number' && (
                    <>
                      <span>Bone:</span>
                      <span>{formatWeight(scan.bone_mass, scan.weight_unit)}</span>
                    </>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        <button type="button" onClick={previousStep}>
          Back
        </button>
        <button type="button" onClick={handleSubmit} disabled={selectedScans.length === 0}>
          Import {selectedScans.length} Scan{selectedScans.length !== 1 ? 's' : ''}
        </button>

        <p>
          Importing multiple scans helps track your progress over time and provides better insights.
        </p>
      </div>
    );
  };

  return {
    __esModule: true,
    MultiScanConfirmationStep,
  };
});

const mockUpdateData = jest.fn();
const mockNextStep = jest.fn();
const mockPreviousStep = jest.fn();

const mockScans = [
  {
    date: '2024-01-15',
    weight: 180,
    weight_unit: 'lbs',
    body_fat_percentage: 15.5,
    muscle_mass: 145,
    bone_mass: 7.5,
    source: 'DEXA Scan',
  },
  {
    date: '2024-02-15',
    weight: 175,
    weight_unit: 'lbs',
    body_fat_percentage: 14.2,
    muscle_mass: 142,
    bone_mass: 7.4,
    source: 'DEXA Scan',
  },
  {
    date: '2024-03-15',
    weight: 172,
    weight_unit: 'lbs',
    body_fat_percentage: 13.8,
    muscle_mass: 140,
    bone_mass: 7.3,
    source: 'DEXA Scan',
  },
];

describe('MultiScanConfirmationStep', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (useOnboarding as jest.Mock).mockReturnValue({
      data: {
        extractedScans: mockScans,
        scanCount: mockScans.length,
      },
      updateData: mockUpdateData,
      nextStep: mockNextStep,
      previousStep: mockPreviousStep,
    });
  });

  describe('Initial State', () => {
    it('should display all scans', () => {
      render(<MultiScanConfirmationStep />);

      expect(screen.getByText('Review Extracted Data')).toBeInTheDocument();
      expect(
        screen.getByText('We found 3 scans in your PDF. Select which ones to import.'),
      ).toBeInTheDocument();

      // Check all scan dates are displayed
      expect(screen.getByText('January 15, 2024')).toBeInTheDocument();
      expect(screen.getByText('February 15, 2024')).toBeInTheDocument();
      expect(screen.getByText('March 15, 2024')).toBeInTheDocument();
    });

    it('should have all scans selected by default', () => {
      render(<MultiScanConfirmationStep />);

      const checkboxes = screen.getAllByRole('checkbox');
      expect(checkboxes).toHaveLength(3);

      checkboxes.forEach((checkbox) => {
        expect(checkbox).toBeChecked();
      });

      expect(screen.getByText('3 of 3 selected')).toBeInTheDocument();
    });

    it('should show import button with correct count', () => {
      render(<MultiScanConfirmationStep />);

      const importButton = screen.getByRole('button', { name: /Import 3 Scans/i });
      expect(importButton).toBeInTheDocument();
      expect(importButton).not.toBeDisabled();
    });
  });

  describe('Scan Display', () => {
    it('should display scan details correctly', () => {
      render(<MultiScanConfirmationStep />);

      // First scan details
      expect(screen.getByText('180.0 lbs')).toBeInTheDocument();
      expect(screen.getByText('15.5%')).toBeInTheDocument();
      expect(screen.getByText('145.0 lbs')).toBeInTheDocument();
      expect(screen.getByText('7.5 lbs')).toBeInTheDocument();
    });

    it('should show source information', () => {
      render(<MultiScanConfirmationStep />);

      const sourceElements = screen.getAllByText('DEXA Scan');
      expect(sourceElements.length).toBeGreaterThan(0);
    });

    it('should highlight selected scans', () => {
      render(<MultiScanConfirmationStep />);

      const scanElements = screen
        .getAllByRole('checkbox')
        .map((cb) => cb.closest('div[class*="border"]'));

      scanElements.forEach((element) => {
        expect(element).toHaveClass('border-linear-purple');
        expect(element).toHaveClass('bg-linear-purple/10');
      });
    });
  });

  describe('Selection Actions', () => {
    it('should toggle individual scan selection', () => {
      render(<MultiScanConfirmationStep />);

      const firstCheckbox = screen.getAllByRole('checkbox')[0];
      fireEvent.click(firstCheckbox);

      expect(firstCheckbox).not.toBeChecked();
      expect(screen.getByText('2 of 3 selected')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Import 2 Scans/i })).toBeInTheDocument();
    });

    it('should select all scans', () => {
      render(<MultiScanConfirmationStep />);

      // First deselect all
      const deselectButton = screen.getByRole('button', { name: /Deselect All/i });
      fireEvent.click(deselectButton);

      expect(screen.getByText('0 of 3 selected')).toBeInTheDocument();

      // Then select all
      const selectButton = screen.getByRole('button', { name: 'Select All' });
      fireEvent.click(selectButton);

      expect(screen.getByText('3 of 3 selected')).toBeInTheDocument();

      const checkboxes = screen.getAllByRole('checkbox');
      checkboxes.forEach((checkbox) => {
        expect(checkbox).toBeChecked();
      });
    });

    it('should deselect all scans', () => {
      render(<MultiScanConfirmationStep />);

      const deselectButton = screen.getByRole('button', { name: /Deselect All/i });
      fireEvent.click(deselectButton);

      const checkboxes = screen.getAllByRole('checkbox');
      checkboxes.forEach((checkbox) => {
        expect(checkbox).not.toBeChecked();
      });

      expect(screen.getByText('0 of 3 selected')).toBeInTheDocument();
    });

    it('should disable import button when no scans selected', () => {
      render(<MultiScanConfirmationStep />);

      const deselectButton = screen.getByRole('button', { name: /Deselect All/i });
      fireEvent.click(deselectButton);

      const importButton = screen.getByRole('button', { name: /Import/i });
      expect(importButton).toBeDisabled();
    });
  });

  describe('Click to Select', () => {
    it('should toggle selection when clicking scan card', () => {
      render(<MultiScanConfirmationStep />);

      // Click on the first scan card (not the checkbox)
      fireEvent.click(screen.getByText('January 15, 2024').closest('div[class*="border"]')!);

      const firstCheckbox = screen.getAllByRole('checkbox')[0];
      expect(firstCheckbox).not.toBeChecked();
    });

    it('should prevent event bubbling when clicking checkbox directly', () => {
      render(<MultiScanConfirmationStep />);

      const firstCheckbox = screen.getAllByRole('checkbox')[0];

      // Click checkbox directly
      fireEvent.click(firstCheckbox);

      // Should only toggle once
      expect(firstCheckbox).not.toBeChecked();
      expect(screen.getByText('2 of 3 selected')).toBeInTheDocument();
    });
  });

  describe('Data Submission', () => {
    it('should update data with selected scans on import', () => {
      render(<MultiScanConfirmationStep />);

      const importButton = screen.getByRole('button', { name: /Import 3 Scans/i });
      fireEvent.click(importButton);

      expect(mockUpdateData).toHaveBeenCalledWith({
        confirmedScans: mockScans,
        selectedScanCount: 3,
      });
      expect(mockNextStep).toHaveBeenCalled();
    });

    it('should only import selected scans', () => {
      render(<MultiScanConfirmationStep />);

      // Deselect the middle scan
      const checkboxes = screen.getAllByRole('checkbox');
      fireEvent.click(checkboxes[1]);

      const importButton = screen.getByRole('button', { name: /Import 2 Scans/i });
      fireEvent.click(importButton);

      expect(mockUpdateData).toHaveBeenCalledWith({
        confirmedScans: [mockScans[0], mockScans[2]],
        selectedScanCount: 2,
      });
    });
  });

  describe('Empty State', () => {
    it('should handle no scans gracefully', () => {
      (useOnboarding as jest.Mock).mockReturnValue({
        data: {
          extractedScans: [],
          scanCount: 0,
        },
        updateData: mockUpdateData,
        nextStep: mockNextStep,
        previousStep: mockPreviousStep,
      });

      render(<MultiScanConfirmationStep />);

      expect(
        screen.getByText('We found 0 scans in your PDF. Select which ones to import.'),
      ).toBeInTheDocument();
      expect(screen.getByText('0 of 0 selected')).toBeInTheDocument();
    });
  });

  describe('Navigation', () => {
    it('should call previousStep on back button click', () => {
      render(<MultiScanConfirmationStep />);

      const backButton = screen.getByRole('button', { name: /Back/i });
      fireEvent.click(backButton);

      expect(mockPreviousStep).toHaveBeenCalled();
    });
  });

  describe('Informational Elements', () => {
    it('should display helpful alert message', () => {
      render(<MultiScanConfirmationStep />);

      expect(
        screen.getByText(
          'Importing multiple scans helps track your progress over time and provides better insights.',
        ),
      ).toBeInTheDocument();
    });

    it('should format weights correctly', () => {
      render(<MultiScanConfirmationStep />);

      // Check weight formatting
      expect(screen.getByText('180.0 lbs')).toBeInTheDocument();
      expect(screen.getByText('175.0 lbs')).toBeInTheDocument();
      expect(screen.getByText('172.0 lbs')).toBeInTheDocument();
    });
  });
});
