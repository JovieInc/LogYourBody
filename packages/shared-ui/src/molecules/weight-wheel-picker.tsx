import React, { useState, useEffect, useMemo } from 'react';
import { cn } from '@shared-lib/utils';
import { WheelPicker } from './wheel-picker';

interface WeightWheelPickerProps {
  weight: number;
  unit: 'kg' | 'lbs';
  onWeightChange: (weight: number) => void;
  className?: string;
}

export const WeightWheelPicker: React.FC<WeightWheelPickerProps> = ({
  weight,
  unit,
  onWeightChange,
  className,
}) => {
  // Generate weight ranges
  const minWeight = unit === 'kg' ? 20 : 44; // 20kg or 44lbs min
  const maxWeight = unit === 'kg' ? 300 : 660; // 300kg or 660lbs max

  // Generate whole numbers
  const wholeNumbers = useMemo(() => {
    const numbers: number[] = [];
    for (let i = minWeight; i <= maxWeight; i++) {
      numbers.push(i);
    }
    return numbers;
  }, [minWeight, maxWeight]);

  // Generate decimals (0.0 to 0.9)
  const decimals = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

  // Calculate initial indices
  const wholeWeight = Math.floor(weight);
  const decimalWeight = Math.round((weight - wholeWeight) * 10);

  const [wholeIndex, setWholeIndex] = useState(Math.max(0, wholeNumbers.indexOf(wholeWeight)));
  const [decimalIndex, setDecimalIndex] = useState(decimalWeight);

  // Update indices when weight or unit changes
  useEffect(() => {
    const whole = Math.floor(weight);
    const decimal = Math.round((weight - whole) * 10);
    setWholeIndex(Math.max(0, wholeNumbers.indexOf(whole)));
    setDecimalIndex(decimal);
  }, [weight, unit, wholeNumbers]);

  const handleWholeChange = (index: number) => {
    setWholeIndex(index);
    const newWeight = wholeNumbers[index] + decimals[decimalIndex] / 10;
    onWeightChange(newWeight);
  };

  const handleDecimalChange = (index: number) => {
    setDecimalIndex(index);
    const newWeight = wholeNumbers[wholeIndex] + decimals[index] / 10;
    onWeightChange(newWeight);
  };

  return (
    <div className={cn('flex items-center justify-center', className)}>
      {/* Whole numbers */}
      <div className="relative">
        <WheelPicker
          items={wholeNumbers}
          selectedIndex={wholeIndex}
          onSelectionChange={handleWholeChange}
          className="w-24"
          itemHeight={48}
          visibleItems={5}
        />
      </div>

      {/* Decimal point */}
      <div className="text-linear-text px-2 text-2xl font-bold">.</div>

      {/* Decimal */}
      <div className="relative">
        <WheelPicker
          items={decimals}
          selectedIndex={decimalIndex}
          onSelectionChange={handleDecimalChange}
          className="w-16"
          itemHeight={48}
          visibleItems={5}
        />
      </div>

      {/* Unit label */}
      <div className="text-linear-text-secondary ml-4 text-xl font-medium">{unit}</div>

      {/* Selection indicator */}
      <div
        className="border-linear-purple/30 pointer-events-none absolute inset-x-0 h-12 border-t-2 border-b-2"
        style={{ top: 'calc(50% - 24px)' }}
      />
    </div>
  );
};

interface BodyFatWheelPickerProps {
  bodyFat: number;
  onBodyFatChange: (bf: number) => void;
  className?: string;
}

export const BodyFatWheelPicker: React.FC<BodyFatWheelPickerProps> = ({
  bodyFat,
  onBodyFatChange,
  className,
}) => {
  // Generate body fat percentages from 0 to 70
  const wholeNumbers: number[] = [];
  for (let i = 0; i <= 70; i++) {
    wholeNumbers.push(i);
  }

  // Generate decimals (0.0 to 0.9)
  const decimals = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

  // Calculate initial indices
  const wholeBF = Math.floor(bodyFat);
  const decimalBF = Math.round((bodyFat - wholeBF) * 10);

  const [wholeIndex, setWholeIndex] = useState(wholeBF);
  const [decimalIndex, setDecimalIndex] = useState(decimalBF);

  // Update indices when body fat changes
  useEffect(() => {
    const whole = Math.floor(bodyFat);
    const decimal = Math.round((bodyFat - whole) * 10);
    setWholeIndex(whole);
    setDecimalIndex(decimal);
  }, [bodyFat]);

  const handleWholeChange = (index: number) => {
    setWholeIndex(index);
    const newBF = wholeNumbers[index] + decimals[decimalIndex] / 10;
    onBodyFatChange(newBF);
  };

  const handleDecimalChange = (index: number) => {
    setDecimalIndex(index);
    const newBF = wholeNumbers[wholeIndex] + decimals[index] / 10;
    onBodyFatChange(newBF);
  };

  return (
    <div className={cn('flex items-center justify-center', className)}>
      {/* Whole numbers */}
      <div className="relative">
        <WheelPicker
          items={wholeNumbers}
          selectedIndex={wholeIndex}
          onSelectionChange={handleWholeChange}
          className="w-20"
          itemHeight={48}
          visibleItems={5}
        />
      </div>

      {/* Decimal point */}
      <div className="text-linear-text px-2 text-2xl font-bold">.</div>

      {/* Decimal */}
      <div className="relative">
        <WheelPicker
          items={decimals}
          selectedIndex={decimalIndex}
          onSelectionChange={handleDecimalChange}
          className="w-16"
          itemHeight={48}
          visibleItems={5}
        />
      </div>

      {/* Percentage sign */}
      <div className="text-linear-text-secondary ml-3 text-xl font-medium">%</div>

      {/* Selection indicator */}
      <div
        className="border-linear-purple/30 pointer-events-none absolute inset-x-0 h-12 border-t-2 border-b-2"
        style={{ top: 'calc(50% - 24px)' }}
      />
    </div>
  );
};
