#!/bin/bash
# Builds Cue.dmg for distribution: tests, Developer ID archive, disk image, notarization and stapling.
# Usage: NOTARY_PROFILE=<keychain profile from "xcrun notarytool store-credentials"> scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"

TEAM_ID=A7Y33JZHW5
IDENTITY=$(security find-identity -v -p codesigning | awk -v team="($TEAM_ID)" '/Developer ID Application/ && index($0, team) { print $2; exit }')
[ -n "$IDENTITY" ] || { echo "no Developer ID Application certificate for team $TEAM_ID" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PROJECT=(-project Cue.xcodeproj -scheme Cue -derivedDataPath "$WORK/DerivedData" -allowProvisioningUpdates -quiet)

# A release is never published with a failing test.
xcodebuild test "${PROJECT[@]}" -destination 'platform=macOS'
xcodebuild archive "${PROJECT[@]}" -configuration Release -archivePath "$WORK/Cue.xcarchive"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$WORK/Cue.xcarchive" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" -allowProvisioningUpdates -quiet

# The disk image holds the app next to a link to Applications, so installing is one drag.
mkdir -p "$WORK/image/.background"
ditto "$WORK/export/Cue.app" "$WORK/image/Cue.app"
ln -s /Applications "$WORK/image/Applications"
cp scripts/dmg/background.tiff "$WORK/image/.background/background.tiff"
hdiutil create -quiet -volname Cue -srcfolder "$WORK/image" -fs HFS+ -format UDRW -ov "$WORK/Cue-rw.dmg"

# Finder stores the window layout in the image's .DS_Store, so the image is styled while mounted.
[ ! -e /Volumes/Cue ] || { echo "eject the volume named Cue first" >&2; exit 1; }
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/Cue-rw.dmg"
osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Cue"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set bounds of container window to {200, 120, 840, 548}
    set options to icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 112
    set text size of options to 13
    set background picture of options to file ".background:background.tiff"
    set position of item "Cue.app" of container window to {170, 200}
    set position of item "Applications" of container window to {470, 200}
    set extension hidden of item "Cue.app" to true
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
rm -rf /Volumes/Cue/.fseventsd
# Copied after the Finder pass, which drops it; the custom icon flag makes Finder show it for the mounted image.
cp "$WORK/export/Cue.app/Contents/Resources/AppIcon.icns" /Volumes/Cue/.VolumeIcon.icns
SetFile -a C /Volumes/Cue
sync
hdiutil detach -quiet /Volumes/Cue
hdiutil convert -quiet "$WORK/Cue-rw.dmg" -format UDZO -o "$WORK/Cue.dmg"
# Notarizing the disk image also covers the app inside it.
codesign --sign "$IDENTITY" --timestamp "$WORK/Cue.dmg"
xcrun notarytool submit "$WORK/Cue.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$WORK/Cue.dmg"
mv -f "$WORK/Cue.dmg" Cue.dmg
echo "released: Cue.dmg"
