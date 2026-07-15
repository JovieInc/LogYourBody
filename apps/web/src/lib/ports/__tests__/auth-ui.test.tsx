import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { AuthSignIn, AuthSignUp } from '../auth-ui';
import { supabase } from '@/lib/supabase/client';

describe('shared auth UI', () => {
  const signInWithOAuth = supabase.auth.signInWithOAuth as jest.Mock;

  beforeEach(() => {
    signInWithOAuth.mockClear();
    signInWithOAuth.mockResolvedValue({ error: null });
  });

  it.each([
    ['sign in', <AuthSignIn />],
    ['sign up', <AuthSignUp />],
  ])('uses only the Jovie phone flow for %s', async (_label, surface) => {
    render(surface);

    fireEvent.click(screen.getByRole('button', { name: 'Continue with phone' }));

    await waitFor(() =>
      expect(signInWithOAuth).toHaveBeenCalledWith({
        provider: 'custom:jovie',
        options: { redirectTo: 'http://localhost/auth/callback' },
      }),
    );
    expect(screen.queryByText(/apple|google|email|password/i)).not.toBeInTheDocument();
  });
});
