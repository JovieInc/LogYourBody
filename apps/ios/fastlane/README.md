fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios lint

```sh
[bundle exec] fastlane ios lint
```

Run SwiftLint

### ios validate_profile

```sh
[bundle exec] fastlane ios validate_profile
```

Validate provisioning profile

### ios test

```sh
[bundle exec] fastlane ios test
```

Run tests with configurable options

### ios test_ui

```sh
[bundle exec] fastlane ios test_ui
```

Run UI tests

### ios ui_snapshot

```sh
[bundle exec] fastlane ios ui_snapshot
```

Run snapshot tests for UI regression

### ios test_sanitizers

```sh
[bundle exec] fastlane ios test_sanitizers
```

Run tests with sanitizers enabled

### ios build

```sh
[bundle exec] fastlane ios build
```

Generic build lane with configurable parameters

### ios build_check

```sh
[bundle exec] fastlane ios build_check
```

Quick build check for CI rapid validation

### ios pr_verify

```sh
[bundle exec] fastlane ios pr_verify
```

PR verification - lint, build, and test

### ios build_dev

```sh
[bundle exec] fastlane ios build_dev
```

Build for development

### ios alpha

```sh
[bundle exec] fastlane ios alpha
```

Build and upload Alpha to TestFlight (dev branch - rapid)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight (preview branch - beta)

### ios ci_build

```sh
[bundle exec] fastlane ios ci_build
```

Build for CI

### ios build_release

```sh
[bundle exec] fastlane ios build_release
```

Build for release (archive only)

### ios upload_testflight

```sh
[bundle exec] fastlane ios upload_testflight
```

Upload existing IPA to TestFlight

### ios submit_app_store

```sh
[bundle exec] fastlane ios submit_app_store
```

Submit existing IPA to App Store

### ios release

```sh
[bundle exec] fastlane ios release
```

Deploy to App Store (build + upload)

### ios setup_provisioning

```sh
[bundle exec] fastlane ios setup_provisioning
```

Setup provisioning with match (readonly mode for CI)

### ios setup_certificates

```sh
[bundle exec] fastlane ios setup_certificates
```

Create development certificates and profiles

### ios setup_distribution

```sh
[bundle exec] fastlane ios setup_distribution
```

Create distribution certificates and profiles

### ios nuke_all_certs

```sh
[bundle exec] fastlane ios nuke_all_certs
```

Nuke all certificates from Apple Developer Portal

### ios regenerate_profiles

```sh
[bundle exec] fastlane ios regenerate_profiles
```

Force regenerate all provisioning profiles with Match

### ios notify_success

```sh
[bundle exec] fastlane ios notify_success
```

Post-build success actions

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
