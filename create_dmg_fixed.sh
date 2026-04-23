#!/bin/bash
set -e

APP_NAME="CloudMounter"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
APP_PATH=".build_output/${APP_NAME}.app"
TEMP_DMG="/tmp/${DMG_NAME}"
MOUNT_POINT="/tmp/mnt_${APP_NAME}"

echo "🔨 Preparando DMG..."

# Verificar app
if [ ! -d "$APP_PATH" ]; then
    echo "❌ App no encontrada en $APP_PATH"
    exit 1
fi

# Limpiar previos
rm -f "$TEMP_DMG"
rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

# Crear DMG base (500MB)
echo "📦 Creando imagen de disco..."
hdiutil create -size 500m -fs HFS+ -volname "$APP_NAME" "$TEMP_DMG" > /dev/null

# Montar
echo "🔗 Montando..."
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_POINT" > /dev/null

# Copiar app
echo "📋 Copiando app..."
cp -r "$APP_PATH" "$MOUNT_POINT/"

# Crear symlink a /Applications
ln -s /Applications "$MOUNT_POINT/Applications"

# Desmontar
echo "🔓 Desmontando..."
hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1 || true

# Comprimir DMG
echo "🗜️  Comprimiendo..."
hdiutil convert "$TEMP_DMG" -format UDZO -o ".build_output/${DMG_NAME}" > /dev/null
rm -f "$TEMP_DMG"

echo "✅ DMG creado: .build_output/${DMG_NAME}"
ls -lh ".build_output/${DMG_NAME}"
echo ""
echo "📦 Para instalar:"
echo "   1. Abre .build_output/${DMG_NAME}"
echo "   2. Arrastra CloudMounter.app a Applications"
echo "   3. Abre desde Launchpad o Aplicaciones"
