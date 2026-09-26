#!/usr/bin/env bash
# One-command setup: checks prerequisites, deploys the iPad app, then runs
# the Mac daemon in the foreground (Ctrl-C to stop). Run it again any time
# you rebuild/redeploy — it's idempotent.
set -euo pipefail
cd "$(dirname "$0")"

missing=()
command -v brew >/dev/null 2>&1 || { echo "Homebrew is required: https://brew.sh" >&2; exit 1; }
command -v xcodegen >/dev/null 2>&1 || missing+=(xcodegen)
command -v iproxy >/dev/null 2>&1 || missing+=(libimobiledevice)
if [ "${#missing[@]}" -gt 0 ]; then
    echo "Installing missing dependencies: ${missing[*]}"
    brew install "${missing[@]}"
fi

if ! xcode-select -p >/dev/null 2>&1 || [[ "$(xcode-select -p)" != *"Xcode.app"* ]]; then
    cat <<'EOF' >&2
Xcode.app (the full app, not just Command Line Tools) must be installed and
selected. Install it from the App Store, then run:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license
EOF
    exit 1
fi

echo "== Deploying iPad app =="
./ipad-client/deploy.sh

echo "== Starting Mac daemon (Ctrl-C to stop) =="
exec ./mac-daemon/run.sh
