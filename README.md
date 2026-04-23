# CloudMounter 1.0.0

**CloudMounter** es una aplicación nativa de macOS que te permite montar tus cuentas en la nube como discos locales en Finder, de forma sencilla y sin necesidad de abrir la terminal.

## 🎯 Características

- ☁️ **Soporte Multi-Proveedor**: OneDrive, Google Drive, Dropbox, Box, MEGA, S3, SFTP, Backblaze B2, Azure Blob y más
- 🔐 **Autenticación Segura**: OAuth desde la app, sin contraseñas en texto plano
- 📁 **Montaje Automático**: Monta cuentas automáticamente al iniciar el Mac
- 💾 **Control de Espacio**: Ve el espacio disponible en la nube y el caché local
- 🧹 **Limpiar Caché**: Libera espacio local fácilmente
- 🔄 **Dos Modos**: FUSE (rápido) o WebDAV (compatible con todo macOS)
- 📝 **Notas**: Agrega descripciones a tus cuentas
- 🎨 **Interfaz Intuitiva**: Toda la configuración desde la app, sin terminal

## 📥 Instalación

### Opción 1: Script de Instalación (Recomendado)

```bash
bash install.sh
```

Esto va a:
1. Compilar la app si es necesario
2. Copiarla a `/Applications`
3. Verificar dependencias
4. Permitir que macOS la ejecute

### Opción 2: Manual

```bash
# Compilar
bash build.sh

# Copiar a Applications
cp -r .build_output/CloudMounter.app /Applications/

# Permitir ejecutar
xattr -d com.apple.quarantine /Applications/CloudMounter.app
```

### Opción 3: DMG (Distribución)

```bash
bash create_dmg.sh
# Abre el DMG y arrastra la app a Applications
```

## 🔧 Requisitos

- **macOS 13.0** o superior
- **Swift 5.8+** (incluido en Xcode CLI)
- **rclone** (descargalo desde [rclone.org](https://rclone.org/downloads))
  - Debe ser la versión **oficial** (no Homebrew)
  - Cópialo a `/usr/local/bin/rclone`

### Opcional: FUSE

Para mejor rendimiento, instala uno de estos:
- **macFUSE**: `brew install macfuse`
- **FUSE-T**: `brew install --cask fuse-t` (Recomendado para macOS moderno)

Si no instalas FUSE, la app automáticamente usa WebDAV (compatible con todo).

## 🚀 Uso

### Primera Vez

1. Abre **CloudMounter** desde Launchpad o `/Applications`
2. Verifica que **rclone** esté instalado (icono verde en la esquina inferior)
3. Haz click en **"Agregar cuenta"**
4. Elige tu proveedor de la nube
5. Sigue el asistente de autenticación
6. ¡Listo! Tu cuenta está montada en `~/CloudMounts/nombre`

### Agregar Cuentas

**Nueva Conexión** (Recomendado):
- Asistente paso-a-paso
- Autenticación automática
- Configuración desde la app

**Remote Existente**:
- Si ya configuraste algo en `rclone config`
- Búscalo en la lista

### Gestionar Cuentas

- **Montar/Desmontar**: Botón azul en cada tarjeta
- **Automontar**: Toggle "auto" para montar al iniciar
- **Abrir en Finder**: Click en el icono de carpeta
- **Detalles**: Click en "..." para ver espacio y limpiar caché
- **Eliminar**: En el sheet de detalles

## 📊 Pantallas

### Cuentas
- Grid de cuentas con estado
- Barra de espacio disponible
- Botones rápidos para montar/desmontar

### Agregar Cuenta
- Grid de proveedores
- Formularios específicos por tipo
- OAuth automático
- Preview de configuración

### Detalles
- Información de la cuenta
- Espacio en la nube
- Espacio en el caché local
- Botón para limpiar caché

### Logs
- Historial de eventos
- Errores y advertencias
- Filtrado por tipo

### Ajustes
- Verificación de dependencias
- Estado del sistema
- Información de rclone

## 🔍 Solución de Problemas

### "rclone no instalado"
```bash
# Descarga la versión oficial
cd /tmp
wget https://downloads.rclone.org/v1.67.0/rclone-v1.67.0-osx-arm64.zip
unzip rclone-v1.67.0-osx-arm64.zip
sudo cp rclone-v1.67.0-osx-arm64/rclone /usr/local/bin/
rclone --version
```

### "FUSE no instalado"
- Instala macFUSE o FUSE-T (ver arriba)
- O simplemente usa WebDAV (funciona sin FUSE)

### "Error de autenticación"
- El token expiró
- Haz click en "..." en la tarjeta
- Reabre los detalles para reconectar

### El mount no funciona
- Verifica que no hay otra app usando ese puerto (18765+)
- Intenta limpiar caché
- Revisa los logs en la pestaña "Log"

## 🏗️ Desarrollo

### Compilar

```bash
# Build básico
bash build.sh

# Build + instalar en /Applications
bash build.sh --install

# Build + crear DMG
bash create_dmg.sh
```

### Estructura

```
Sources/CloudMounter/
├── Models/
│   ├── Models.swift           # Account, CloudProvider, MountStatus
│   └── AccountStore.swift     # Estado global, persistencia
├── Services/
│   └── RcloneService.swift    # Actor, rclone wrapper
└── Views/
    ├── ContentView.swift      # App principal
    ├── Views.swift            # AccountCard, AddAccountSheet, etc.
    ├── AboutView.swift        # About dialog
    └── *View.swift            # LogView, SettingsView
```

### Compilación Manual

```bash
# Sin build.sh
swiftc \
  -sdk $(xcrun --sdk macosx --show-sdk-path) \
  -target arm64-apple-macos13.0 \
  -O -parse-as-library \
  -module-name CloudMounter \
  -framework SwiftUI \
  -framework AppKit \
  -framework UserNotifications \
  -framework Foundation \
  -o CloudMounter \
  Sources/CloudMounter/**/*.swift
```

## 📝 Licencia

© 2026 CloudMounter. All rights reserved.

## 🔗 Enlaces

- [rclone.org](https://rclone.org) - Backend de sincronización
- [macfuse.io](https://osxfuse.github.io) - FUSE para macOS
- [swift.org](https://swift.org) - Lenguaje de programación

## 🐛 Reportar Bugs

Si encontrás un problema:
1. Revisa los logs en la pestaña "Log"
2. Nota los pasos para reproducir
3. Verifica que rclone esté actualizado
4. Comparte los logs (sin credenciales)

---

**Hecho con ❤️ para macOS** | v1.0.0
