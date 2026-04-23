#!/bin/bash
set -e

APP_NAME="CloudMounter"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
APP_PATH=".build_output/${APP_NAME}.app"
TEMP_DMG="/tmp/${DMG_NAME}"
MOUNT_POINT="/tmp/mnt_${APP_NAME}"

echo "🔨 Compilando y preparando DMG..."

# Compilar si es necesario
if [ ! -d "$APP_PATH" ]; then
    bash build.sh || exit 1
fi

# Limpiar previos
rm -f "$TEMP_DMG"
rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

# Crear DMG base (500MB)
hdiutil create -size 500m -fs HFS+ -volname "$APP_NAME" "$TEMP_DMG" > /dev/null

# Montar
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_POINT" > /dev/null

# Copiar app
cp -r "$APP_PATH" "$MOUNT_POINT/"

# Crear symlink a /Applications
ln -s /Applications "$MOUNT_POINT/Applications"

# Crear background (opcional)
mkdir -p "$MOUNT_POINT/.background"
cat > "$MOUNT_POINT/.background/bg.txt" << 'EOF'
CloudMounter v1.0.0
Arrastra la app a la carpeta Applications
EOF

# Set DMG appearance
osascript << EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 920, 440}
        set position of item "$APP_NAME.app" of container window to {150, 150}
        set position of item "Applications" of container window to {450, 150}
        set label size of icon view options of container window to 80
        set text size of icon view options of container window to 12
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Desmontar
hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1 || true

# Comprimir DMG
hdiutil convert "$TEMP_DMG" -format UDZO -o ".build_output/${DMG_NAME}" > /dev/null
rm -f "$TEMP_DMG"

echo "✅ DMG creado: .build_output/${DMG_NAME}"
echo ""
echo "📦 Para instalar:"
echo "   1. Abre .build_output/${DMG_NAME}"
echo "   2. Arrastra CloudMounter.app a la carpeta Applications"
echo "   3. Abre desde Launchpad o Aplicaciones"
