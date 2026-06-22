#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🔧 Setting up Xcode configuration..."
echo ""
bash "$ROOT_DIR/scripts/ios/bootstrap-local-config.sh"

echo ""
echo "📝 Next steps:"
echo "1. Open LogYourBody.xcodeproj in Xcode"
echo "2. Select the project in the navigator"
echo "3. Select the LogYourBody target"
echo "4. Go to the 'Info' tab"
echo "5. Under 'Configurations', set both Debug and Release to use 'Config'"
echo ""
echo "Or use this command to set it programmatically:"
echo "cd LogYourBody.xcodeproj && plutil -replace 'buildConfigurationList' -xml '<dict><key>defaultConfigurationName</key><string>Release</string></dict>' project.pbxproj"
