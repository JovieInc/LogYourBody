import { render, screen } from '@testing-library/react';
import { AuthSignIn, AuthSignUp } from '../auth-ui';

describe('shared auth UI', () => {
  it.each([
    ['sign in', <AuthSignIn />],
    ['sign up', <AuthSignUp />],
  ])('uses only the direct Jovie phone flow for %s', (_label, surface) => {
    render(surface);

    expect(screen.getByRole('link', { name: 'Continue with phone' })).toHaveAttribute(
      'href',
      '/api/auth/login',
    );
    expect(screen.queryByText(/apple|google|email|password/i)).not.toBeInTheDocument();
  });
});
