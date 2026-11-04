#!/usr/bin/env bash
set -e

SIM_ID="485A60A4-3455-4C34-9671-E2F9EB2491B8"
BUNDLE_ID="com.unicornsonlsd.finamp-ios"

echo "=== Finamp iOS Simulator Launcher ==="

# 1. Ensure build output directory exists (required by build symlink)
mkdir -p /tmp/finamp-build-output

# 2. Check and establish backend SSH tunnel if needed
if ! lsof -i :8765 >/dev/null 2>&1; then
    echo "Starting SSH tunnel to koltensserver (port 8765)..."
    ssh -f -N -L 8765:127.0.0.1:8765 koltensserver
    sleep 1
fi

if lsof -i :8765 >/dev/null 2>&1; then
    echo "✓ Catalog backend tunnel active (http://127.0.0.1:8765)"
else
    echo "⚠️ Warning: Catalog backend tunnel could not be verified on port 8765."
fi

# 3. Boot simulator if shutdown
if ! xcrun simctl list devices | grep "$SIM_ID" | grep -q "Booted"; then
    echo "Booting iPhone 17 Pro simulator..."
    xcrun simctl boot "$SIM_ID"
    xcrun simctl bootstatus "$SIM_ID" -b
fi
echo "✓ iPhone 17 Pro simulator is booted"

# 4. Open Device Hub GUI
echo "Opening Device Hub..."
open -a "/Applications/Xcode.app/Contents/Applications/DeviceHub.app"

# 5. Launch Finamp application
echo "Launching Finamp..."
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "✓ Finamp running on simulator"

# 6. Bring Device Hub to foreground
osascript -e 'tell application "Device Hub" to activate' 2>/dev/null || true

echo "=== Ready! Device Hub with Finamp is on screen. ==="
