# iOS App Configuration

This iOS app uses Xcode configuration files to manage environment-specific settings like API URLs and Supabase credentials.

## Setup Instructions

### 1. Create Configuration File

Copy the example configuration file:
```bash
cp LogYourBody/Config.xcconfig.example LogYourBody/Config.xcconfig
```

### 2. Add Your Credentials

Edit `LogYourBody/Config.xcconfig` and add your Supabase credentials:

```xcconfig
// Supabase Configuration
SUPABASE_URL = https://your-project.supabase.co
SUPABASE_ANON_KEY = your-anon-key-here

// API Base URL
API_BASE_URL_DEBUG = http://localhost:3000
API_BASE_URL_RELEASE = https://your-production-url.com
```

### 3. Configure Xcode Project

1. Open `LogYourBody.xcodeproj` in Xcode
2. Select the project in the navigator
3. Go to the project settings (not target)
4. Under "Configurations", click the "+" button and select "Add Configuration File..."
5. Select the `Config.xcconfig` file
6. Apply it to both Debug and Release configurations

### 4. Run the Setup Script

```bash
./setup-xcode-config.sh
```

## Security Notes

- **Never commit `Config.xcconfig` to version control** - it contains sensitive credentials
- The file is already added to `.gitignore`
- Share credentials securely with team members through a password manager or secure channel
- Use different Supabase projects for development and production

## Configuration Values

The following values are available in the app via the `Configuration` class:

- `Configuration.supabaseURL` - Your Supabase project URL
- `Configuration.supabaseAnonKey` - Your Supabase anonymous key
- `Configuration.apiBaseURL` - Backend API URL (changes based on Debug/Release build)

## Troubleshooting

If you see warnings like "SUPABASE_URL not configured":
1. Make sure `Config.xcconfig` exists
2. Verify it contains the correct values
3. Clean and rebuild the project (Cmd+Shift+K, then Cmd+B)
4. Make sure the configuration file is properly linked in Xcode project settings