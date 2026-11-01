import { redirect } from 'next/navigation';
import SignInPage from '../page';
import SignupPage from '../../signup/page';
import { GET as login } from '../../login/route';

it.each([SignInPage, SignupPage, login])(
  'sends legacy authentication URLs to the iPhone landing page',
  (handler) => {
    jest.mocked(redirect).mockClear();
    handler();
    expect(redirect).toHaveBeenCalledWith('/download/ios');
  },
);
