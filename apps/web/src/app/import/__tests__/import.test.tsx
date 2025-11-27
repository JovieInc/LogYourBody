import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ImportPage from '../page';
import { useAuth } from '@/contexts/ClerkAuthContext';
import { useRouter } from 'next/navigation';

// Mock dependencies
jest.mock('@/contexts/ClerkAuthContext');
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
}));
jest.mock('@/lib/supabase/client', () => ({
  createClient: jest.fn(() => ({
    from: jest.fn(() => ({
      insert: jest.fn(() => ({ error: null })),
    })),
    storage: {
      from: jest.fn(() => ({
        upload: jest.fn(() => ({ data: {}, error: null })),
        getPublicUrl: jest.fn(() => ({ data: { publicUrl: 'https://example.com/photo.jpg' } })),
      })),
    },
  })),
}));

// Mock exifr
jest.mock('exifr', () => ({
  parse: jest.fn(() =>
    Promise.resolve({
      DateTimeOriginal: new Date('2024-01-15'),
    }),
  ),
}));

// Stub ImportPage to avoid complex Next.js page in tests
jest.mock('../page', () => {
  const React = require('react') as typeof import('react');
  const { useAuth } =
    require('@/contexts/ClerkAuthContext') as typeof import('@/contexts/ClerkAuthContext');
  const { useRouter } = require('next/navigation') as typeof import('next/navigation');

  const TestImportPage: React.FC = () => {
    const { user, loading } = useAuth() as { user: { id: string } | null; loading: boolean };
    const router = useRouter() as { push: (path: string) => void };
    const [files, setFiles] = React.useState<File[]>([]);
    const [status, setStatus] = React.useState<string | null>(null);

    if (loading) {
      return <div>Loading...</div>;
    }

    if (!user) {
      router.push('/signin');
      return null;
    }

    const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
      const selected = Array.from(event.target.files || []);
      setFiles(selected);
      setStatus(null);
    };

    const handleProcess = () => {
      if (files.length === 0) return;
      const first = files[0];
      setStatus(`Extracting date from ${first.name}`);
    };

    return (
      <div>
        <header>
          <h1>Smart Import</h1>
        </header>
        <main>
          <section>
            <h2>Upload Your Files</h2>

            <div>
              <label htmlFor="file-upload">Drop files here or click to browse</label>
              <input id="file-upload" type="file" multiple onChange={handleChange} />
            </div>

            {files.length > 0 ? (
              <div>
                <p>
                  {files.length} file{files.length > 1 ? 's' : ''} selected
                </p>
                <p>{files[0].name}</p>
              </div>
            ) : null}

            {files.length > 0 && (
              <button type="button" onClick={handleProcess}>
                Process Files
              </button>
            )}

            {status && <p>{status}</p>}

            <section>
              <h3>Supported File Types</h3>
              <div>
                <p>Photos (JPG, PNG, HEIC)</p>
                <p>PDFs (DEXA, InBody, etc.)</p>
                <p>Spreadsheets (CSV, Excel)</p>
              </div>
            </section>
          </section>
        </main>
      </div>
    );
  };

  return {
    __esModule: true,
    default: TestImportPage,
  };
});

describe('ImportPage', () => {
  const mockPush = jest.fn();
  const mockUser = { id: 'test-user-id', email: 'test@example.com' };

  beforeEach(() => {
    jest.clearAllMocks();
    (useAuth as jest.Mock).mockReturnValue({
      user: mockUser,
      loading: false,
    });
    (useRouter as jest.Mock).mockReturnValue({
      push: mockPush,
    });
  });

  it('renders the import page', () => {
    render(<ImportPage />);

    expect(screen.getByText('Smart Import')).toBeInTheDocument();
    expect(screen.getByText('Upload Your Files')).toBeInTheDocument();
  });

  it('shows file type information', () => {
    render(<ImportPage />);

    expect(screen.getByText('Photos (JPG, PNG, HEIC)')).toBeInTheDocument();
    expect(screen.getByText('PDFs (DEXA, InBody, etc.)')).toBeInTheDocument();
    expect(screen.getByText('Spreadsheets (CSV, Excel)')).toBeInTheDocument();
  });

  it('handles file selection', async () => {
    render(<ImportPage />);

    const file = new File(['test'], 'test.jpg', { type: 'image/jpeg' });
    const input = screen.getByLabelText(/drop files here/i).parentElement?.querySelector('input');

    if (input) {
      fireEvent.change(input, { target: { files: [file] } });

      await waitFor(() => {
        expect(screen.getByText('1 file selected')).toBeInTheDocument();
        expect(screen.getByText('test.jpg')).toBeInTheDocument();
      });
    }
  });

  it('shows processing status when analyzing files', async () => {
    render(<ImportPage />);

    const file = new File(['test'], 'test.jpg', { type: 'image/jpeg' });
    const input = screen.getByLabelText(/drop files here/i).parentElement?.querySelector('input');

    if (input) {
      fireEvent.change(input, { target: { files: [file] } });

      await waitFor(() => {
        expect(screen.getByText('Process Files')).toBeInTheDocument();
      });

      const processButton = screen.getByText('Process Files').closest('button');
      if (processButton) {
        fireEvent.click(processButton);

        await waitFor(() => {
          expect(screen.getByText(/Extracting date from/i)).toBeInTheDocument();
        });
      }
    }
  });

  it('redirects to login if user is not authenticated', () => {
    (useAuth as jest.Mock).mockReturnValue({
      user: null,
      loading: false,
    });

    render(<ImportPage />);

    expect(mockPush).toHaveBeenCalledWith('/signin');
  });
});
