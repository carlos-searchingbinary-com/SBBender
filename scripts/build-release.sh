#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
APP_NAME="SBBender"
BUNDLE_ID="com.searchingbinary.SBBender"
EXECUTABLE="SBBenderApp"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD_NUMBER:-1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

ENTITLEMENTS="$PROJECT_DIR/Sources/SBBenderApp/SBBenderApp.entitlements"
INFO_PLIST="$PROJECT_DIR/Sources/SBBenderApp/Info.plist"
PRIVACY_MANIFEST="$PROJECT_DIR/Sources/SBBenderApp/PrivacyInfo.xcprivacy"

DEVELOPER_ID="${DEVELOPER_ID:-${1:-}}"

# ─── Helpers ─────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
step()  { bold "→ $*"; }
err()   { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

# ─── Validate ────────────────────────────────────────────────────────────────
[[ -f "$ENTITLEMENTS" ]] || err "Entitlements not found: $ENTITLEMENTS"
[[ -f "$INFO_PLIST" ]]   || err "Info.plist not found: $INFO_PLIST"

if [[ -z "$DEVELOPER_ID" ]]; then
    echo "Usage: $0 <Developer ID identity>"
    echo "   or: DEVELOPER_ID='Developer ID Application: ...' $0"
    echo ""
    echo "Available identities:"
    security find-identity -v -p codesigning | grep "Developer ID" || true
    exit 1
fi

# ─── Step 1: Build ───────────────────────────────────────────────────────────
step "Building $EXECUTABLE (release)..."
cd "$PROJECT_DIR"
swift build -c release --product "$EXECUTABLE" 2>&1

BINARY="$BUILD_DIR/$EXECUTABLE"
[[ -f "$BINARY" ]] || err "Binary not found at $BINARY"

# ─── Step 2: Create .app bundle ─────────────────────────────────────────────
step "Creating $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$PRIVACY_MANIFEST" "$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"

# Update version numbers in the bundle's Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP_BUNDLE/Contents/Info.plist"

# ─── Step 2b: Generate and embed app icon ──────────────────────────────────
step "Generating app icon..."
"$SCRIPT_DIR/generate-icns.sh"
if [[ -f "$DIST_DIR/SBBender.icns" ]]; then
    cp "$DIST_DIR/SBBender.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_BUNDLE/Contents/Info.plist"
fi

# ─── Step 3: Codesign ───────────────────────────────────────────────────────
step "Signing with: $DEVELOPER_ID"
codesign --force --sign "$DEVELOPER_ID" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "$APP_BUNDLE"

step "Verifying signature..."
codesign --verify --verbose=2 "$APP_BUNDLE"

# ─── Step 4: Create DMG ─────────────────────────────────────────────────────
step "Creating DMG..."
rm -f "$DMG_PATH"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 660 400 \
        --icon-size 128 \
        --icon "$APP_NAME.app" 160 200 \
        --app-drop-link 500 200 \
        "$DMG_PATH" "$APP_BUNDLE"
else
    step "(create-dmg not found, using hdiutil — install with: brew install create-dmg)"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP_BUNDLE" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

codesign --force --sign "$DEVELOPER_ID" \
    --timestamp \
    "$DMG_PATH"

# ─── Step 5: Notarize ───────────────────────────────────────────────────────
step "Submitting for notarization..."
echo "  (This may take a few minutes)"

xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "notarytool" \
    --wait

# ─── Step 6: Staple ─────────────────────────────────────────────────────────
step "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# ─── Step 7: Generate Sparkle Appcast ───────────────────────────────────────
if command -v generate_appcast &>/dev/null; then
    step "Generating Sparkle appcast..."
    generate_appcast "$DIST_DIR"
    if [[ -f "$DIST_DIR/appcast.xml" ]]; then
        cp "$DIST_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"
        bold "  Appcast updated at $PROJECT_DIR/appcast.xml"
    fi
else
    step "(Sparkle generate_appcast not found — install Sparkle tools to auto-generate appcast)"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
bold ""
bold "Build complete!"
bold "  App:  $APP_BUNDLE"
bold "  DMG:  $DMG_PATH"
bold ""
bold "Verify with:"
bold "  spctl --assess --type execute -vv '$APP_BUNDLE'"
bold "  spctl --assess --type open -vv '$DMG_PATH'"
