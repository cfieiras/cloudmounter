# 🚀 CloudMounter - Inicio Rápido

## La Forma Más Fácil

```bash
bash setup.sh
```

Esto va a:
1. ✅ Compilar la app
2. ✅ Instalarla en `/Applications`
3. ✅ Descargar e instalar rclone (si no lo tenés)
4. ✅ Instalar FUSE-T (opcional, para mejor rendimiento)
5. ✅ Abrir la app automáticamente

---

## Alternativas Rápidas

### Si ya compilaste y solo querés instalar:
```bash
bash install.sh
```

### Si querés crear un DMG para distribuir:
```bash
bash create_dmg.sh
```

### Si querés compilar sin instalar:
```bash
bash build.sh
# Luego abre: open .build_output/CloudMounter.app
```

---

## ⚠️ Requisitos Antes de Empezar

- **macOS 13+** (Sonoma o posterior recomendado)
- **Xcode Command Line Tools**:
  ```bash
  xcode-select --install
  ```
- **rclone** (se instala automáticamente con `setup.sh`):
  ```bash
  # Descargalo manualmente desde:
  https://rclone.org/downloads
  # O via Homebrew (PERO verificá que sea la versión oficial):
  brew install rclone
  ```

---

## 📋 Primeros Pasos en la App

1. **Abre CloudMounter**
   - Spotlight: `Cmd+Space` → escribe "CloudMounter"
   - O directamente desde `/Applications`

2. **Verifica el estado** (esquina inferior izquierda)
   - 🟢 Verde = Todo está bien
   - 🔴 Rojo = Instala rclone

3. **Haz click en "Agregar cuenta"**
   - Elige tu servicio en la nube (OneDrive, Google Drive, etc.)
   - Sigue el asistente
   - ¡Automáticamente se monta en `~/CloudMounts/nombre`!

4. **Abre en Finder**
   - Verás tu cuenta como un disco más
   - Acceso total a todos tus archivos

---

## 🆘 Si Algo Falla

### "rclone no encontrado"
```bash
# Opción 1: Descargar manual
cd /tmp
wget https://downloads.rclone.org/v1.67.0/rclone-v1.67.0-osx-arm64.zip
unzip rclone-v1.67.0-osx-arm64.zip
sudo cp rclone-v*/rclone /usr/local/bin/
rclone --version
```

### "FUSE no disponible"
- ✅ La app automáticamente usa **WebDAV como fallback**
- Funciona bien, igual de seguro, un poco más lento
- Opcional: Instala FUSE-T para mejor rendimiento
  ```bash
  brew install --cask fuse-t
  ```

### "No puedo ejecutar la app"
```bash
# Permite que macOS ejecute la app
xattr -d com.apple.quarantine /Applications/CloudMounter.app
```

---

## 📚 Más Información

- **README.md** - Documentación completa
- **rclone.org** - Documentación de rclone
- Pestaña **Log** en la app - Ver detalles de errores

---

## 🎯 Atajos Útiles

- **Agregar cuenta rápido**: Click "Agregar cuenta"
- **Montar todo**: Click "Montar todo" en la pestaña Cuentas
- **Ver detalles**: Double-click en una cuenta
- **Limpiar caché**: En detalles de cuenta, click "Limpiar caché"

---

## 💡 Tips

1. **Automontar**: Activa el toggle "auto" para montar al iniciar
2. **Organiza**: Usa carpetas personalizadas en "Opciones de montaje"
3. **Notas**: Agrega descripciones a tus cuentas para identificarlas fácil
4. **Espacio**: Mira cuánto espacio libre tiene tu nube en los detalles
5. **Seguridad**: Las contraseñas se encriptan con `rclone obscure`

---

**¡Eso es todo! Ahora tenés todas tus cuentas en la nube accesibles como discos locales. 🎉**
