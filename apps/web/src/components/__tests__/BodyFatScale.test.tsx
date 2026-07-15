import { render, screen } from '@testing-library/react';

import { BodyFatScale } from '@/components/BodyFatScale';

describe('BodyFatScale', () => {
  it('omits goal presentation when no explicit range is supplied', () => {
    render(<BodyFatScale currentBF={18} gender="male" />);

    expect(screen.queryByTestId('body-fat-goal-range')).not.toBeInTheDocument();
    expect(screen.queryByText(/^Goal:/)).not.toBeInTheDocument();
  });

  it('renders an explicitly supplied goal range', () => {
    render(<BodyFatScale currentBF={18} gender="male" goalRange={{ min: 14, max: 17 }} />);

    expect(screen.getByTestId('body-fat-goal-range')).toBeInTheDocument();
    expect(screen.getByText('Goal: 14-17%')).toBeInTheDocument();
  });
});
