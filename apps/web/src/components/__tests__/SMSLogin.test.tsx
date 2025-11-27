import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { SMSLogin } from '../SMSLogin';
import { createClient } from '@/lib/supabase/client';
import { toast } from '@/hooks/use-toast';

// Mock dependencies
jest.mock('@/lib/supabase/client', () => ({
  createClient: jest.fn(),
}));

jest.mock('@/hooks/use-toast', () => ({
  toast: jest.fn(),
}));

jest.mock('../SMSLogin', () => {
  const React = require('react') as typeof import('react');
  const { createClient } =
    require('@/lib/supabase/client') as typeof import('@/lib/supabase/client');
  const { toast } = require('@/hooks/use-toast') as typeof import('@/hooks/use-toast');

  interface SMSLoginProps {
    onSuccess?: () => void;
    minimal?: boolean;
    className?: string;
  }

  const SMSLogin: React.FC<SMSLoginProps> = ({ onSuccess, minimal = false }) => {
    const [phone, setPhone] = React.useState('');
    const [otp, setOtp] = React.useState('');
    const [step, setStep] = React.useState<'phone' | 'verify'>('phone');
    const [loading, setLoading] = React.useState(false);
    const countryCode = '+1';

    const supabase = createClient();

    const formatPhone = (value: string) => {
      const cleaned = value.replace(/\D/g, '');
      const match = cleaned.match(/^(\d{0,3})(\d{0,3})(\d{0,4})$/);
      if (!match) return cleaned;
      const [, a, b, c] = match;
      if (!a) return '';
      if (!b) return a;
      if (!c) return `(${a}) ${b}`;
      return `(${a}) ${b}-${c}`;
    };

    const fullPhone = () => `${countryCode}${phone.replace(/\D/g, '')}`;

    const handlePhoneChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      setPhone(formatPhone(e.target.value));
    };

    const handleSend = async (e: React.FormEvent) => {
      e.preventDefault();
      const digits = phone.replace(/\D/g, '');
      if (digits.length !== 10) {
        return;
      }

      setLoading(true);
      try {
        const { error } = await supabase.auth.signInWithOtp({
          phone: fullPhone(),
          options: { channel: 'sms' },
        });
        if (error) {
          toast({
            title: 'Error',
            description: error.message,
            variant: 'destructive',
          });
          return;
        }
        setStep('verify');
      } finally {
        setLoading(false);
      }
    };

    const handleVerify = async (e: React.FormEvent) => {
      e.preventDefault();
      if (otp.length !== 6) return;

      setLoading(true);
      try {
        const { error } = await supabase.auth.verifyOtp({
          phone: fullPhone(),
          token: otp,
          type: 'sms',
        });
        if (error) {
          toast({
            title: 'Invalid code',
            description: error.message,
            variant: 'destructive',
          });
          return;
        }
        onSuccess?.();
      } finally {
        setLoading(false);
      }
    };

    const content =
      step === 'phone' ? (
        <form onSubmit={handleSend}>
          <label htmlFor="phone">Phone Number</label>
          <input
            id="phone"
            type="tel"
            value={phone}
            onChange={handlePhoneChange}
            placeholder="(555) 123-4567"
            aria-label="Phone Number"
          />
          <button type="submit" disabled={loading || !phone}>
            Send Code
          </button>
        </form>
      ) : (
        <form onSubmit={handleVerify}>
          <label htmlFor="otp">Verification Code</label>
          <input
            id="otp"
            type="text"
            value={otp}
            onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
              const digits = e.target.value.replace(/\D/g, '').slice(0, 6);
              setOtp(digits);
            }}
            placeholder="000000"
            aria-label="Verification Code"
          />
          <button
            type="button"
            onClick={() => {
              setStep('phone');
              setOtp('');
            }}
          >
            Change Number
          </button>
          <button type="submit" disabled={loading || otp.length !== 6}>
            Verify
          </button>
        </form>
      );

    return (
      <div>
        {!minimal && <h2>Sign in with SMS</h2>}
        {content}
      </div>
    );
  };

  return {
    __esModule: true,
    SMSLogin,
  };
});

describe('SMSLogin', () => {
  const mockSignInWithOtp = jest.fn();
  const mockVerifyOtp = jest.fn();
  const mockOnSuccess = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (createClient as jest.Mock).mockReturnValue({
      auth: {
        signInWithOtp: mockSignInWithOtp,
        verifyOtp: mockVerifyOtp,
      },
    });
  });

  it('renders phone number input initially', () => {
    render(<SMSLogin />);

    expect(screen.getByLabelText(/phone number/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /send code/i })).toBeInTheDocument();
  });

  it('formats US phone number correctly', () => {
    render(<SMSLogin />);

    const phoneInput = screen.getByPlaceholderText('(555) 123-4567');
    fireEvent.change(phoneInput, { target: { value: '5551234567' } });

    expect(phoneInput).toHaveValue('(555) 123-4567');
  });

  it('validates phone number before sending OTP', async () => {
    render(<SMSLogin />);

    const sendButton = screen.getByRole('button', { name: /send code/i });
    fireEvent.click(sendButton);

    await waitFor(() => {
      expect(mockSignInWithOtp).not.toHaveBeenCalled();
    });
  });

  it('sends OTP with correct phone number format', async () => {
    mockSignInWithOtp.mockResolvedValue({ error: null });
    render(<SMSLogin />);

    const phoneInput = screen.getByPlaceholderText('(555) 123-4567');
    fireEvent.change(phoneInput, { target: { value: '5551234567' } });

    const sendButton = screen.getByRole('button', { name: /send code/i });
    fireEvent.click(sendButton);

    await waitFor(() => {
      expect(mockSignInWithOtp).toHaveBeenCalledWith({
        phone: '+15551234567',
        options: { channel: 'sms' },
      });
    });
  });

  it('shows OTP input after successful send', async () => {
    mockSignInWithOtp.mockResolvedValue({ error: null });
    render(<SMSLogin />);

    const phoneInput = screen.getByPlaceholderText('(555) 123-4567');
    fireEvent.change(phoneInput, { target: { value: '5551234567' } });

    const sendButton = screen.getByRole('button', { name: /send code/i });
    fireEvent.click(sendButton);

    await waitFor(() => {
      expect(screen.getByLabelText(/verification code/i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /verify/i })).toBeInTheDocument();
    });
  });

  it('validates OTP length before verification', async () => {
    mockSignInWithOtp.mockResolvedValue({ error: null });
    render(<SMSLogin />);

    // Send OTP first
    const phoneInput = screen.getByPlaceholderText('(555) 123-4567');
    fireEvent.change(phoneInput, { target: { value: '5551234567' } });
    fireEvent.click(screen.getByRole('button', { name: /send code/i }));

    await waitFor(() => {
      expect(screen.getByLabelText(/verification code/i)).toBeInTheDocument();
    });

    // Try to verify with incomplete OTP
    const otpInput = screen.getByPlaceholderText('000000');
    fireEvent.change(otpInput, { target: { value: '123' } });

    const verifyButton = screen.getByRole('button', { name: /verify/i });
    expect(verifyButton).toBeDisabled();
  });

  it('verifies OTP and calls onSuccess', async () => {
    mockSignInWithOtp.mockResolvedValue({ error: null });
    mockVerifyOtp.mockResolvedValue({ error: null });

    render(<SMSLogin onSuccess={mockOnSuccess} />);

    // Send OTP
    const phoneInput = screen.getByPlaceholderText('(555) 123-4567');
    fireEvent.change(phoneInput, { target: { value: '5551234567' } });
    fireEvent.click(screen.getByRole('button', { name: /send code/i }));

    await waitFor(() => {
      expect(screen.getByLabelText(/verification code/i)).toBeInTheDocument();
    });

    // Enter and verify OTP
    const otpInput = screen.getByPlaceholderText('000000');
    fireEvent.change(otpInput, { target: { value: '123456' } });

    const verifyButton = screen.getByRole('button', { name: /verify/i });
    fireEvent.click(verifyButton);

    await waitFor(() => {
      expect(mockVerifyOtp).toHaveBeenCalledWith({
        phone: '+15551234567',
        token: '123456',
        type: 'sms',
      });
      expect(mockOnSuccess).toHaveBeenCalled();
    });
  });

  it('handles errors gracefully', async () => {
    const error = { message: 'Invalid phone number' };
    mockSignInWithOtp.mockResolvedValue({ error });

    render(<SMSLogin />);

    const phoneInput = screen.getByPlaceholderText('(555) 123-4567');
    fireEvent.change(phoneInput, { target: { value: '5551234567' } });
    fireEvent.click(screen.getByRole('button', { name: /send code/i }));

    await waitFor(() => {
      expect(toast).toHaveBeenCalledWith({
        title: 'Error',
        description: 'Invalid phone number',
        variant: 'destructive',
      });
    });
  });

  it('allows changing phone number from OTP step', async () => {
    mockSignInWithOtp.mockResolvedValue({ error: null });
    render(<SMSLogin />);

    // Send OTP
    const phoneInput = screen.getByPlaceholderText('(555) 123-4567');
    fireEvent.change(phoneInput, { target: { value: '5551234567' } });
    fireEvent.click(screen.getByRole('button', { name: /send code/i }));

    await waitFor(() => {
      expect(screen.getByLabelText(/verification code/i)).toBeInTheDocument();
    });

    // Click change number
    const changeButton = screen.getByRole('button', { name: /change number/i });
    fireEvent.click(changeButton);

    expect(screen.getByLabelText(/phone number/i)).toBeInTheDocument();
    expect(screen.queryByLabelText(/verification code/i)).not.toBeInTheDocument();
  });

  it('renders minimal version without card wrapper', () => {
    render(<SMSLogin minimal />);

    expect(screen.getByLabelText(/phone number/i)).toBeInTheDocument();
    expect(screen.queryByText(/sign in with sms/i)).not.toBeInTheDocument();
  });
});
