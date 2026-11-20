#!/bin/bash
set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly guard="$repo_root/apps/ios/Scripts/verify-app-store-min-sdk.mjs"
artifact_dir="${1:?Usage: verify-ios-ipa-min-sdk.sh <IPA directory>}"
[[ -f "$guard" ]] || { echo "::error::Missing App Store minimum-SDK guard: $guard"; exit 1; }
[[ -d "$artifact_dir" ]] || { echo "::error::Missing IPA directory: $artifact_dir"; exit 1; }

plist_dir="$(mktemp -d)"
trap 'rm -rf "$plist_dir"' EXIT

# Extract only the host app's plist. Reject ambiguous artifacts; never pick the
# first IPA or an extension plist and then upload a different application.
python3 - "$artifact_dir" "$plist_dir/Info.plist" <<'PY'
from pathlib import Path
import re
import sys
import zipfile

try:
    ipas = sorted(path for path in Path(sys.argv[1]).rglob('*.ipa') if path.is_file())
    if len(ipas) != 1:
        raise ValueError(f'Expected exactly one IPA, found {len(ipas)}')
    with zipfile.ZipFile(ipas[0]) as archive:
        plists = [entry for entry in archive.infolist()
                  if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', entry.filename)]
        if len(plists) != 1:
            raise ValueError(f'Expected exactly one host app Info.plist, found {len(plists)}')
        Path(sys.argv[2]).write_bytes(archive.read(plists[0]))
    print(f'Checking archived app SDK in {ipas[0]}', flush=True)
except (OSError, ValueError, zipfile.BadZipFile, RuntimeError) as error:
    print(f'::error::Cannot verify IPA SDK: {error}', file=sys.stderr)
    sys.exit(1)
PY

plutil -convert xml1 "$plist_dir/Info.plist"
node "$guard" --info-plist "$plist_dir/Info.plist"
