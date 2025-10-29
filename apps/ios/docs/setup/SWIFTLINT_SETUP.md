# SwiftLint Setup for LogYourBody

## Installation Steps

### 1. Install SwiftLint (if not already installed)

```bash
brew install swiftlint
```

Or if you're using Apple Silicon Mac:
```bash
arch -arm64 brew install swiftlint
```

### 2. Add Build Phase to Xcode

1. Open `LogYourBody.xcodeproj` in Xcode
2. Select the LogYourBody target
3. Go to Build Phases tab
4. Click the + button and select "New Run Script Phase"
5. Name it "SwiftLint"
6. Add this script:

```bash
if [[ "$(uname -m)" == arm64 ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

if which swiftlint > /dev/null; then
    swiftlint
else
    echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

7. Drag the SwiftLint phase to run before "Compile Sources"

### 3. Configuration

The `.swiftlint.yml` file has been created with:
- Sensible rules for Swift development
- iOS-specific configurations
- Custom rules for LogYourBody project standards

### 4. Running SwiftLint

#### From Terminal:
```bash
cd /path/to/LogYourBody/apps/ios
swiftlint
```

#### Auto-fix issues:
```bash
swiftlint --fix
```

#### In Xcode:
Build the project (⌘B) and SwiftLint will run automatically, showing warnings and errors in Xcode.

## Current Configuration Highlights

### Enabled Rules:
- Code quality rules (empty_count, redundant_nil_coalescing, etc.)
- Performance rules (contains_over_filter_count, reduce_into, etc.)
- Style rules (closure_spacing, operator_usage_whitespace, etc.)
- Safety rules (unowned_variable_capture, force_unwrapping, etc.)

### Custom Rules:
- **No Hardcoded Strings**: Warns about hardcoded UI strings
- **MARK Format**: Enforces consistent MARK comment format
- **No Print Statements**: Warns about print statements in code
- **Force HTTPS**: Errors on HTTP URLs

### Thresholds:
- Line length: Warning at 150, error at 200
- File length: Warning at 600 lines, error at 1000
- Function length: Warning at 60 lines, error at 100
- Type length: Warning at 500 lines, error at 750

## Fixing Common Issues

### Line Too Long
```swift
// Before
let veryLongLineOfCodeThatExceedsTheMaximumLineLengthAndNeedsToBeWrapped = someVeryLongFunctionCall(with: parameter1, and: parameter2, also: parameter3)

// After
let veryLongLineOfCodeThatExceedsTheMaximumLineLengthAndNeedsToBeWrapped = 
    someVeryLongFunctionCall(
        with: parameter1, 
        and: parameter2, 
        also: parameter3
    )
```

### Force Unwrapping
```swift
// Before
let value = optionalValue!

// After
guard let value = optionalValue else { return }
// or
let value = optionalValue ?? defaultValue
```

### Empty Count
```swift
// Before
if array.count == 0 { }

// After
if array.isEmpty { }
```

## Disabling Rules

### For a specific line:
```swift
// swiftlint:disable:next force_cast
let view = superview as! CustomView
```

### For a file section:
```swift
// swiftlint:disable type_body_length
class VeryLargeClass {
    // ...
}
// swiftlint:enable type_body_length
```

### For an entire file:
```swift
// swiftlint:disable:this file_length
```

## Benefits

1. **Consistent Code Style**: Entire team follows same conventions
2. **Catch Bugs Early**: Many rules catch potential bugs
3. **Better Performance**: Rules like `contains_over_filter_count` improve performance
4. **Cleaner Code**: Enforces best practices and clean code principles
5. **CI/CD Integration**: Can be integrated into build pipelines

## Next Steps

1. Install SwiftLint using brew
2. Add the build phase in Xcode
3. Run SwiftLint and fix any issues
4. Consider adding SwiftLint to CI/CD pipeline