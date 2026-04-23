#!/bin/bash

# Crear iconset directory
mkdir -p icon.iconset

# Copiar y redimensionar un icono base
BASE_ICON="/System/Library/CoreServices/Finder.app/Contents/Resources/FinderIcon.icns"

if [ -f "$BASE_ICON" ]; then
    for size in 16 32 64 128 256 512 1024; do
        sips -z $size $size "$BASE_ICON" --out "icon.iconset/icon_${size}x${size}.png" 2>/dev/null
    done
    
    # Crear .icns
    iconutil -c icns icon.iconset -o AppIcon.icns
    echo "✅ AppIcon.icns creado"
else
    echo "Icono base no encontrado"
fi
