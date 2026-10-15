#!/usr/bin/env bash
# Builds, installs, and launches the iPad app on the first connected+paired
# physical iPad devicectl can see. Pass a UDID explicitly to skip detection:
#   ./deploy.sh 00008103-001C058E1A84C01E
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Missing xcodegen. Run: brew install xcodegen" >&2
    exit 1
fi

UDID="${1:-}"
if [ -z "$UDID" ]; then
    # Anchored on the "(UDID)" marker rather than fixed column positions:
    # a blank Hostname column (e.g. a device named without one) shifts
    # whitespace-split fields left, so absolute positions aren't reliable.
    # "connected" is preferred; "available (paired)" is what devicectl reports
    # for a paired iPad whose connection isn't active yet (locked/just
    # plugged in), and install/launch will bring it up. Unpaired ("available"
    # without "(paired)") and "unavailable" devices are still excluded.
    UDID=$(xcrun devicectl list devices 2>/dev/null \
        | awk '{for (i=1;i<=NF;i++) if ($i=="(UDID)" && $NF=="physical") {
                    if ($(i+1)=="connected") print "0 " $(i-1)
                    else if ($(i+1)=="available" && $(i+2)=="(paired)") print "1 " $(i-1)
                }}' \
        | sort -s -k1,1 | head -1 | cut -d' ' -f2)
fi

if [ -z "$UDID" ]; then
    echo "No connected or paired physical iPad found." >&2
    echo "Check: cable carries data (not charge-only), iPad is unlocked," >&2
    echo "and 'Trust This Computer?' has been accepted. Verify with:" >&2
    echo "  xcrun devicectl list devices" >&2
    exit 1
fi

echo "Deploying to device $UDID..."
xcodegen generate
xcodebuild -project IpadTablet.xcodeproj -scheme IpadTablet -sdk iphoneos \
    -destination "id=$UDID" -derivedDataPath build -allowProvisioningUpdates build

APP_PATH="build/Build/Products/Debug-iphoneos/IpadTablet.app"
xcrun devicectl device install app --device "$UDID" "$APP_PATH"
xcrun devicectl device process launch --device "$UDID" com.dc.ipadtablet

cat <<'EOF'

Launched. If this is the first install on this iPad, and it fails with a
signature/trust error, do this once on the iPad then rerun this script:
  Settings > Privacy & Security > Developer Mode -> enable, restart, confirm
  Settings > General > VPN & Device Management -> trust the developer cert
EOF
