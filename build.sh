#!/bin/bash
set -e

# ── Config ──────────────────────────────────────────────────────────────────
APP_NAME="CloudMounter"
BUNDLE_ID="com.cloudmounter.app"
BUILD_DIR=".build_output"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET="arm64-apple-macos13.0"

# ── Collect sources ──────────────────────────────────────────────────────────
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Sources/CloudMounter -name "*.swift" -o -name "*.swift" | sort)
if [ ${#SOURCES[@]} -eq 0 ]; then
    echo "❌ No Swift sources found under Sources/CloudMounter/"
    exit 1
fi
echo "🔨 Compiling ${#SOURCES[@]} Swift files..."

# ── Compile ──────────────────────────────────────────────────────────────────
mkdir -p "$BUILD_DIR"
swiftc \
    -sdk "$SDK" \
    -target "$TARGET" \
    -O \
    -parse-as-library \
    -module-name CloudMounter \
    -framework SwiftUI \
    -framework AppKit \
    -framework UserNotifications \
    -framework Foundation \
    -o "$BUILD_DIR/$APP_NAME" \
    "${SOURCES[@]}"

echo "✅ Compiled: $BUILD_DIR/$APP_NAME"

# ── Build .app bundle ────────────────────────────────────────────────────────
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$BINARY"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/CloudMounter.icns "$APP_BUNDLE/Contents/Resources/CloudMounter.icns"

# ── Code sign (ad-hoc) ───────────────────────────────────────────────────────
codesign --sign - --force --deep "$APP_BUNDLE"
echo "✅ Signed: $APP_BUNDLE"

# ── Optional: copy to /Applications ─────────────────────────────────────────
if [[ "$1" == "--install" ]]; then
    echo "📦 Installing to /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -r "$APP_BUNDLE" "/Applications/"
    echo "✅ Installed: /Applications/$APP_NAME.app"
fi

echo ""
echo "🚀 Done! Run with:"
echo "   open $APP_BUNDLE"
echo "   # or: $BINARY"
