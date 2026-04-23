#!/bin/bash

# CloudMounter Installation Script
# Instala CloudMounter en /Applications

set -e

APP_NAME="CloudMounter"
BUILD_PATH=".build_output"
APP_PATH="$BUILD_PATH/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"

echo ""
echo "🚀 === Instalador de $APP_NAME ==="
echo ""

# 1. Verificar que existe la app compilada
if [ ! -d "$APP_PATH" ]; then
    echo "❌ No encontré la app compilada."
    echo "   Compilando primero..."
    bash build.sh
    echo ""
fi

# 2. Verificar si ya está instalada
if [ -d "$INSTALL_PATH" ]; then
    echo "⚠️  $APP_NAME ya está instalado en /Applications"
    read -p "¿Deseas actualizarlo? (s/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Cancelado."
        exit 0
    fi
    echo "Removiendo versión anterior..."
    rm -rf "$INSTALL_PATH"
fi

# 3. Copiar a Applications
echo "📦 Instalando $APP_NAME en /Applications..."
cp -r "$APP_PATH" "/Applications/"

# 4. Quitar quarantine attribute
echo "🔓 Configurando permisos..."
xattr -d com.apple.quarantine "/Applications/${APP_NAME}.app" 2>/dev/null || true

# 5. Verificar dependencias
echo ""
echo "🔍 Verificando dependencias..."
echo ""

# Verificar rclone
if command -v rclone &> /dev/null; then
    RCLONE_PATH=$(which rclone)
    echo "✅ rclone encontrado: $RCLONE_PATH"
else
    echo "⚠️  rclone no encontrado"
    echo "   Descargá desde: https://rclone.org/downloads"
    echo "   Y copialo a: /usr/local/bin/rclone"
fi

echo ""
echo "✅ === Instalación completada ==="
echo ""
echo "📱 Puedes abrir $APP_NAME desde:"
echo "   • Launchpad"
echo "   • Spotlight Search (Cmd+Space, escribe '$APP_NAME')"
echo "   • /Applications/$APP_NAME.app"
echo ""
echo "🎯 Próximos pasos:"
echo "   1. Abre la app"
echo "   2. Verifica que tengas rclone instalado (debe aparecer en verde)"
echo "   3. Haz click en 'Agregar cuenta' para comenzar"
echo ""
