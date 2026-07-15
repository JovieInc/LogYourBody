export const authCookies = {
  accessToken: 'lyb_access_token',
  refreshToken: 'lyb_refresh_token',
  idToken: 'lyb_id_token',
  state: 'lyb_oauth_state',
  verifier: 'lyb_oauth_verifier',
  returnTo: 'lyb_oauth_return_to',
} as const;

export type JovieUserInfo = {
  sub: string;
  name?: string;
  given_name?: string;
  family_name?: string;
  email?: string;
  email_verified?: boolean;
  phone_number?: string;
  phone_number_verified?: boolean;
  picture?: string;
  updated_at?: number;
};
