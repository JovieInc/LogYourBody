import React, { useState, useRef, useEffect } from 'react';
import { cn } from '@shared-lib/utils';

interface WheelPickerProps {
  items: string[] | number[];
  selectedIndex: number;
  onSelectionChange: (index: number) => void;
  className?: string;
  itemHeight?: number;
  visibleItems?: number;
}

export const WheelPicker: React.FC<WheelPickerProps> = ({
  items,
  selectedIndex,
  onSelectionChange,
  className,
  itemHeight = 48,
  visibleItems = 5,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [startY, setStartY] = useState(0);
  const [startScrollTop, setStartScrollTop] = useState(0);

  const containerHeight = itemHeight * visibleItems;
  const centerOffset = Math.floor(visibleItems / 2) * itemHeight;

  // Scroll to selected item
  useEffect(() => {
    if (containerRef.current) {
      const scrollTop = selectedIndex * itemHeight;
      containerRef.current.scrollTop = scrollTop;
    }
  }, [selectedIndex, itemHeight]);

  const handleScroll = () => {
    if (!containerRef.current || isDragging) return;

    const scrollTop = containerRef.current.scrollTop;
    const newIndex = Math.round(scrollTop / itemHeight);
    const clampedIndex = Math.max(0, Math.min(items.length - 1, newIndex));

    if (clampedIndex !== selectedIndex) {
      onSelectionChange(clampedIndex);
    }
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    setIsDragging(true);
    setStartY(e.clientY);
    setStartScrollTop(containerRef.current?.scrollTop || 0);
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!isDragging || !containerRef.current) return;

    const deltaY = e.clientY - startY;
    const newScrollTop = startScrollTop - deltaY;
    containerRef.current.scrollTop = newScrollTop;
  };

  const handleMouseUp = () => {
    setIsDragging(false);
    snapToNearestItem();
  };

  const handleTouchStart = (e: React.TouchEvent) => {
    setIsDragging(true);
    setStartY(e.touches[0].clientY);
    setStartScrollTop(containerRef.current?.scrollTop || 0);
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (!isDragging || !containerRef.current) return;

    const deltaY = e.touches[0].clientY - startY;
    const newScrollTop = startScrollTop - deltaY;
    containerRef.current.scrollTop = newScrollTop;
  };

  const handleTouchEnd = () => {
    setIsDragging(false);
    snapToNearestItem();
  };

  const snapToNearestItem = () => {
    if (!containerRef.current) return;

    const scrollTop = containerRef.current.scrollTop;
    const nearestIndex = Math.round(scrollTop / itemHeight);
    const clampedIndex = Math.max(0, Math.min(items.length - 1, nearestIndex));

    containerRef.current.scrollTo({
      top: clampedIndex * itemHeight,
      behavior: 'smooth',
    });

    onSelectionChange(clampedIndex);
  };

  return (
    <div className={cn('relative select-none', className)}>
      {/* Selection highlight */}
      <div
        className="border-primary/20 bg-primary/10 pointer-events-none absolute right-0 left-0 z-10 border-y"
        style={{
          top: centerOffset,
          height: itemHeight,
        }}
      />

      {/* Scrollable container */}
      <div
        ref={containerRef}
        className="scrollbar-hide overflow-hidden"
        style={{ height: containerHeight }}
        role="listbox"
        tabIndex={0}
        aria-label="Select value"
        onScroll={handleScroll}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        onTouchEnd={handleTouchEnd}
      >
        {/* Padding items at start */}
        {Array(Math.floor(visibleItems / 2))
          .fill(null)
          .map((_, index) => (
            <div key={`padding-start-${index}`} style={{ height: itemHeight }} />
          ))}

        {/* Actual items */}
        {items.map((item, index) => (
          <div
            key={index}
            role="option"
            aria-selected={index === selectedIndex}
            tabIndex={-1}
            className={cn(
              'flex cursor-pointer items-center justify-center text-center transition-opacity duration-200',
              index === selectedIndex ? 'text-foreground font-medium' : 'text-muted-foreground',
            )}
            style={{ height: itemHeight }}
            onClick={() => onSelectionChange(index)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onSelectionChange(index);
              }
            }}
          >
            {item}
          </div>
        ))}

        {/* Padding items at end */}
        {Array(Math.floor(visibleItems / 2))
          .fill(null)
          .map((_, index) => (
            <div key={`padding-end-${index}`} style={{ height: itemHeight }} />
          ))}
      </div>
    </div>
  );
};

interface HeightWheelPickerProps {
  heightInCm: number;
  units: 'imperial' | 'metric';
  onHeightChange: (heightInCm: number) => void;
  className?: string;
}

export const HeightWheelPicker: React.FC<HeightWheelPickerProps> = ({
  heightInCm,
  units,
  onHeightChange,
  className,
}) => {
  if (units === 'imperial') {
    const totalInches = Math.round(heightInCm / 2.54);
    const feet = Math.floor(totalInches / 12);
    const inches = totalInches % 12;

    const feetOptions = Array.from({ length: 6 }, (_, i) => i + 3); // 3-8 feet
    const inchesOptions = Array.from({ length: 12 }, (_, i) => i); // 0-11 inches

    const handleFeetChange = (feetIndex: number) => {
      const newFeet = feetOptions[feetIndex];
      const newTotalInches = newFeet * 12 + inches;
      onHeightChange(newTotalInches * 2.54);
    };

    const handleInchesChange = (inchesIndex: number) => {
      const newInches = inchesOptions[inchesIndex];
      const newTotalInches = feet * 12 + newInches;
      onHeightChange(newTotalInches * 2.54);
    };

    return (
      <div className={cn('flex gap-4', className)}>
        <div className="flex-1">
          <div className="mb-2 text-center text-sm font-medium">Feet</div>
          <WheelPicker
            items={feetOptions.map((f) => `${f} ft`)}
            selectedIndex={feet - 3}
            onSelectionChange={handleFeetChange}
            className="bg-secondary rounded-lg"
          />
        </div>
        <div className="flex-1">
          <div className="mb-2 text-center text-sm font-medium">Inches</div>
          <WheelPicker
            items={inchesOptions.map((i) => `${i} in`)}
            selectedIndex={inches}
            onSelectionChange={handleInchesChange}
            className="bg-secondary rounded-lg"
          />
        </div>
      </div>
    );
  } else {
    const cmOptions = Array.from({ length: 151 }, (_, i) => i + 100); // 100-250 cm
    const selectedIndex = Math.max(0, heightInCm - 100);

    const handleCmChange = (index: number) => {
      onHeightChange(cmOptions[index]);
    };

    return (
      <div className={className}>
        <div className="mb-2 text-center text-sm font-medium">Centimeters</div>
        <WheelPicker
          items={cmOptions.map((cm) => `${cm} cm`)}
          selectedIndex={selectedIndex}
          onSelectionChange={handleCmChange}
          className="bg-secondary rounded-lg"
        />
      </div>
    );
  }
};

interface DateWheelPickerProps {
  date: Date;
  onDateChange: (date: Date) => void;
  className?: string;
}

export const DateWheelPicker: React.FC<DateWheelPickerProps> = ({
  date,
  onDateChange,
  className,
}) => {
  const currentYear = new Date().getFullYear();
  const months = [
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
  ];

  // Generate years from 1920 to current year
  const years = Array.from({ length: currentYear - 1919 }, (_, i) => currentYear - i);

  // Generate days based on selected month/year
  const getDaysInMonth = (month: number, year: number) => {
    return new Date(year, month + 1, 0).getDate();
  };

  const selectedMonth = date.getMonth();
  const selectedYear = date.getFullYear();
  const selectedDay = date.getDate();

  const daysInMonth = getDaysInMonth(selectedMonth, selectedYear);
  const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);

  const handleMonthChange = (monthIndex: number) => {
    const newDate = new Date(
      selectedYear,
      monthIndex,
      Math.min(selectedDay, getDaysInMonth(monthIndex, selectedYear)),
    );
    onDateChange(newDate);
  };

  const handleDayChange = (dayIndex: number) => {
    const newDate = new Date(selectedYear, selectedMonth, days[dayIndex]);
    onDateChange(newDate);
  };

  const handleYearChange = (yearIndex: number) => {
    const newYear = years[yearIndex];
    const newDate = new Date(
      newYear,
      selectedMonth,
      Math.min(selectedDay, getDaysInMonth(selectedMonth, newYear)),
    );
    onDateChange(newDate);
  };

  return (
    <div className={cn('flex gap-2', className)}>
      <div className="flex-1">
        <div className="mb-2 text-center text-sm font-medium">Month</div>
        <WheelPicker
          items={months}
          selectedIndex={selectedMonth}
          onSelectionChange={handleMonthChange}
          className="bg-secondary rounded-lg"
        />
      </div>
      <div className="w-16">
        <div className="mb-2 text-center text-sm font-medium">Day</div>
        <WheelPicker
          items={days}
          selectedIndex={selectedDay - 1}
          onSelectionChange={handleDayChange}
          className="bg-secondary rounded-lg"
        />
      </div>
      <div className="w-20">
        <div className="mb-2 text-center text-sm font-medium">Year</div>
        <WheelPicker
          items={years}
          selectedIndex={years.indexOf(selectedYear)}
          onSelectionChange={handleYearChange}
          className="bg-secondary rounded-lg"
        />
      </div>
    </div>
  );
};
