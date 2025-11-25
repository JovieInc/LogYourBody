---
description: Run the iOS alpha TestFlight lane
auto_execution_mode: 3
---

1. **Open a terminal at the repo root**

   ```bash
   # cd apps/ios
   ```

2. **Ensure Ruby dependencies are installed** (only needed after Gemfile changes or toolchain updates):

   ```bash
   # bundle install
   ```

3. **Run the iOS alpha Fastlane lane** to build, upload to TestFlight, and upload dSYMs:

   ```bash
   # bundle exec fastlane alpha
   ```

4. **If the lane fails at `build_app`**:

   - Scroll up in the Fastlane output to the first `❌` or `error:` line from `xcodebuild`.
   - Copy the last ~40 lines around that error.
   - Paste them into this chat so we can debug the underlying Xcode build issue (codesigning, compile error, missing file, etc.).

5. **If the lane succeeds**:

   - Confirm the new build appears in App Store Connect → TestFlight.
   - Verify the correct version/build number (e.g. `1.2.0 (YYYYMMDDHHMMSS)`).
   - Check that the changelog and tester notification behavior match expectations for alpha.