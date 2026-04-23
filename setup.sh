#!/bin/bash

# CloudMounter Setup Script
# Instala y configura CloudMounter completamente

set -e

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         🚀 CloudMounter Setup v1.0.0                       ║"
echo "║                                                            ║"
echo "║  Guía de instalación interactiva para macOS               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Check requirements
echo "${BLUE}📋 Paso 1: Verificando requisitos...${NC}"
echo ""

# Check Swift
if ! command -v swiftc &> /dev/null; then
    echo "${RED}❌ Swift no encontrado${NC}"
    echo "   Instala Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi
echo "${GREEN}✓ Swift detectado${NC}"

# Check git (optional but helpful)
if command -v git &> /dev/null; then
    echo "${GREEN}✓ Git detectado${NC}"
fi

# Check macOS version
MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MACOS_VERSION" -ge 13 ]; then
    echo "${GREEN}✓ macOS 13+ detectado${NC}"
else
    echo "${YELLOW}⚠️  Se recomienda macOS 13 o superior${NC}"
fi

echo ""
echo "${BLUE}🔨 Paso 2: Compilando CloudMounter...${NC}"
echo ""

if [ -d ".build_output/CloudMounter.app" ]; then
    echo "ℹ️  App ya compilada. ¿Recompilar?"
    read -p "   (s/n) [n]: " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        rm -rf .build_output
        bash build.sh
    fi
else
    bash build.sh
fi

echo ""
echo "${BLUE}📦 Paso 3: Instalación${NC}"
echo ""

APP_PATH="/Applications/CloudMounter.app"

if [ -d "$APP_PATH" ]; then
    echo "${YELLOW}⚠️  CloudMounter ya está en /Applications${NC}"
    read -p "   ¿Actualizar? (s/n) [s]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        rm -rf "$APP_PATH"
        cp -r ".build_output/CloudMounter.app" "/Applications/"
        echo "${GREEN}✓ App actualizada${NC}"
    fi
else
    cp -r ".build_output/CloudMounter.app" "/Applications/"
    echo "${GREEN}✓ App instalada en /Applications${NC}"
fi

# Remove quarantine
xattr -d com.apple.quarantine "/Applications/CloudMounter.app" 2>/dev/null || true

echo ""
echo "${BLUE}🔧 Paso 4: Verificando dependencias de rclone...${NC}"
echo ""

RCLONE_PATH=""
if command -v rclone &> /dev/null; then
    RCLONE_PATH=$(which rclone)
    RCLONE_VER=$(rclone --version | head -1)

    # Check if it's official (not Homebrew)
    if [[ "$RCLONE_PATH" == "/usr/local/bin/rclone" ]]; then
        echo "${GREEN}✓ rclone oficial encontrado${NC}"
        echo "   $RCLONE_VER"
    else
        echo "${YELLOW}⚠️  rclone encontrado pero no es la versión oficial${NC}"
        echo "   Ubicación: $RCLONE_PATH"
        echo ""
        echo "   CloudMounter necesita el rclone oficial porque Homebrew"
        echo "   desactiva la función 'mount' en macOS."
        echo ""
        read -p "   ¿Descargar e instalar rclone oficial? (s/n) [s]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            # Download official rclone
            ARCH=$(uname -m)
            if [ "$ARCH" = "arm64" ]; then
                RCLONE_URL="https://downloads.rclone.org/v1.67.0/rclone-v1.67.0-osx-arm64.zip"
            else
                RCLONE_URL="https://downloads.rclone.org/v1.67.0/rclone-v1.67.0-osx-amd64.zip"
            fi

            echo "Descargando rclone..."
            cd /tmp
            wget -q "$RCLONE_URL" -O rclone.zip
            unzip -q rclone.zip
            RCLONE_BIN=$(find . -name "rclone" -type f | head -1)
            sudo cp "$RCLONE_BIN" /usr/local/bin/rclone
            sudo chmod +x /usr/local/bin/rclone
            rm -f rclone.zip
            cd - > /dev/null

            RCLONE_PATH="/usr/local/bin/rclone"
            echo "${GREEN}✓ rclone oficial instalado${NC}"
            $RCLONE_PATH --version | head -1
        fi
    fi
else
    echo "${YELLOW}⚠️  rclone no encontrado${NC}"
    echo ""
    read -p "   ¿Descargar e instalar rclone? (s/n) [s]: " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        ARCH=$(uname -m)
        if [ "$ARCH" = "arm64" ]; then
            RCLONE_URL="https://downloads.rclone.org/v1.67.0/rclone-v1.67.0-osx-arm64.zip"
        else
            RCLONE_URL="https://downloads.rclone.org/v1.67.0/rclone-v1.67.0-osx-amd64.zip"
        fi

        echo "Descargando rclone..."
        cd /tmp
        wget -q "$RCLONE_URL" -O rclone.zip
        unzip -q rclone.zip
        RCLONE_BIN=$(find . -name "rclone" -type f | head -1)
        sudo cp "$RCLONE_BIN" /usr/local/bin/rclone
        sudo chmod +x /usr/local/bin/rclone
        rm -f rclone.zip
        cd - > /dev/null

        echo "${GREEN}✓ rclone instalado${NC}"
    else
        echo "${YELLOW}⚠️  Nota: CloudMounter necesita rclone para funcionar${NC}"
    fi
fi

echo ""
echo "${BLUE}📚 Paso 5: Dependencias opcionales (FUSE)${NC}"
echo ""

echo "CloudMounter puede usar FUSE para mejor rendimiento."
echo "Sin FUSE, automáticamente usa WebDAV (igual de funcional)."
echo ""

FUSE_INSTALLED=0
if command -v brew &> /dev/null; then
    if brew list macfuse &> /dev/null 2>&1 || brew list fuse-t &> /dev/null 2>&1; then
        echo "${GREEN}✓ FUSE ya instalado${NC}"
        FUSE_INSTALLED=1
    else
        echo "Opciones de FUSE disponibles vía Homebrew:"
        echo "  • macFUSE (más compatible pero requiere Recovery Mode)"
        echo "  • FUSE-T (moderno, recomendado)"
        echo ""
        read -p "   ¿Instalar FUSE-T? (s/n) [n]: " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Ss]$ ]]; then
            echo "Instalando FUSE-T..."
            brew install --cask fuse-t
            echo "${GREEN}✓ FUSE-T instalado${NC}"
            FUSE_INSTALLED=1
        fi
    fi
else
    echo "${YELLOW}⚠️  Homebrew no encontrado${NC}"
    echo "   Si deseas FUSE, instala desde: https://github.com/macos-fuse-t/fuse-t"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║              ✅ ¡Setup completado!                         ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "${GREEN}🎯 Próximos pasos:${NC}"
echo ""
echo "1. Abre CloudMounter:"
echo "   • Spotlight: Cmd+Space, escribe 'CloudMounter'"
echo "   • O: /Applications/CloudMounter.app"
echo ""
echo "2. Verifica el estado en la esquina inferior"
echo "   Verde  = Todo listo ✓"
echo "   Rojo   = Revisar dependencias"
echo ""
echo "3. Haz click en 'Agregar cuenta'"
echo "   • Elige tu servicio en la nube"
echo "   • Sigue el asistente de autenticación"
echo "   • ¡Listo!"
echo ""

if [ $FUSE_INSTALLED -eq 0 ]; then
    echo "${YELLOW}ℹ️  Sin FUSE instalado:${NC}"
    echo "   • La app usará WebDAV automáticamente"
    echo "   • Funciona bien, pero un poco más lento"
    echo "   • Instala FUSE-T después si deseas mejor rendimiento"
    echo ""
fi

echo "${BLUE}📖 Para más información:${NC}"
echo "   cat README.md"
echo ""
echo "¿Abrir CloudMounter ahora?"
read -p "(s/n) [s]: " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    open /Applications/CloudMounter.app
fi

echo "¡Gracias por usar CloudMounter! ❤️"
echo ""
