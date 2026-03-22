#!/usr/bin/env bash
set -euo pipefail

# Murmur notarization script
# Prerequisites:
#   - Developer ID Application certificate installed in Keychain
#   - APPLE_ID, APPLE_APP_PASSWORD (app-specific), APPLE_TEAM_ID env vars set
#   - create-dmg installed: brew install create-dmg

APP_NAME="Murmur"
SCHEME="Murmur"
CONFIGURATION="Release"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
DMG_PATH="build/${APP_NAME}.dmg"

echo "==> Building archive..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    CODE_SIGN_STYLE=Manual

echo "==> Exporting app..."
# Create export options plist
cat > build/ExportOptions.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist build/ExportOptions.plist \
    -exportPath "$EXPORT_PATH"

echo "==> Creating DMG..."
rm -f "$DMG_PATH"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "$APP_NAME" \
        --volicon "${EXPORT_PATH}/${APP_NAME}.app/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 175 190 \
        --app-drop-link 425 190 \
        --hide-extension "${APP_NAME}.app" \
        "$DMG_PATH" \
        "${EXPORT_PATH}/${APP_NAME}.app"
else
    # Fallback: simple DMG creation
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "${EXPORT_PATH}/${APP_NAME}.app" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo "==> Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "${APPLE_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --team-id "${APPLE_TEAM_ID}" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying..."
spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

echo "==> Done! DMG ready at: $DMG_PATH"
