# Clerk iOS Setup Guide

## Prerequisites
1. A Clerk account with an application created
2. Your Clerk publishable key and Frontend API URL

## Configuration Steps

### 1. Update Constants.swift
Replace the placeholder values in `LogYourBody/Utils/Constants.swift`:

```swift
// MARK: - Clerk Configuration
static let clerkPublishableKey = "pk_test_YOUR_ACTUAL_PUBLISHABLE_KEY"
static let clerkFrontendAPI = "your-subdomain.clerk.accounts.dev"
```

### 2. Clerk Dashboard Settings
In your Clerk Dashboard (https://dashboard.clerk.com):

1. **Authentication Settings**:
   - Go to "User & Authentication" → "Email, Phone, Username"
   - Enable "Email address" authentication
   - Enable "Password" authentication
   - Configure email verification settings

2. **Session Settings**:
   - Go to "Sessions"
   - Set appropriate session lifetime
   - Configure security settings

3. **Application Settings**:
   - Ensure your application is in the correct environment (Development/Production)
   - Note your Frontend API URL from the dashboard home

### 3. Testing the Integration

1. **Sign Up Flow**:
   - Launch the app
   - Navigate to Sign Up
   - Enter email and password
   - Verify email with the code sent
   - Confirm successful authentication

2. **Sign In Flow**:
   - Use existing credentials
   - Verify session persistence
   - Test logout functionality

### 4. Apple Sign In Setup (Optional)

To enable Apple Sign In with Clerk:

1. **Clerk Dashboard**:
   - Go to "User & Authentication" → "Social Connections"
   - Enable "Sign in with Apple"
   - Configure Apple OAuth settings

2. **Xcode Configuration**:
   - Add Sign in with Apple capability
   - Configure bundle identifier
   - Update provisioning profiles

### 5. Production Considerations

1. **API Keys**:
   - Use production keys when deploying
   - Store sensitive keys securely
   - Don't commit keys to version control

2. **Error Handling**:
   - Implement proper error messages
   - Handle network failures gracefully
   - Add retry logic for failed requests

3. **Session Management**:
   - Implement token refresh logic
   - Handle session expiration
   - Secure token storage

## Troubleshooting

### Common Issues:

1. **"Invalid publishable key" error**:
   - Verify the key starts with `pk_test_` or `pk_live_`
   - Check for extra spaces or characters
   - Ensure you're using the correct environment key

2. **"Network error" on sign up/sign in**:
   - Verify the Frontend API URL is correct
   - Check internet connectivity
   - Ensure Clerk services are operational

3. **Email verification not working**:
   - Check spam folder for verification emails
   - Verify email settings in Clerk dashboard
   - Ensure email provider isn't blocking Clerk emails

### Support Resources:
- Clerk Documentation: https://clerk.com/docs
- Clerk Support: https://clerk.com/support
- Community Discord: https://discord.com/invite/b5rXHjAg7A