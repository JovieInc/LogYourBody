---
description: 
auto_execution_mode: 3
---

# Autonomous lint + fix loop: keep running until there are 0 errors

while true; do
  echo "Running lint…"
  if bundle exec fastlane ios lint; then
    echo "✅ Lint passed with 0 errors."
    break
  fi

  echo "Lint failed. Attempting auto-fix…"
  bundle exec fastlane ios fix_style

  echo "Re-running lint after auto-fix…"
  if bundle exec fastlane ios lint; then
    echo "✅ Lint passed after auto-fix."
    break
  fi

  echo "Still failing. Looping to try again…"
done