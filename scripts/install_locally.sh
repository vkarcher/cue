#!/bin/bash
# Builds Cue in Release, signed for development, and installs it in ~/Applications for daily use on this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
xcodebuild build -project Cue.xcodeproj -scheme Cue -configuration Release -derivedDataPath "$WORK" -allowProvisioningUpdates -quiet
rm -rf "$HOME/Applications/Cue.app"
ditto "$WORK/Build/Products/Release/Cue.app" "$HOME/Applications/Cue.app"
echo "installed: $HOME/Applications/Cue.app"
