# Guía de Diagnóstico - Problema con Transferencias

## ¿Qué hacer si el botón "Iniciar" no funciona?

### Paso 1: Verificar que todo está configurado correctamente

```bash
# 1. Verifica que rclone está instalado
which rclone
rclone --version

# 2. Verifica que hay remotes configurados
rclone listremotes

# 3. Verifica la configuración de rclone
cat ~/.config/rclone/rclone.conf
```

### Paso 2: Ejecutar la app y capturar logs

```bash
# Abre la app en terminal para ver los logs
.build_output/CloudMounter.app/Contents/MacOS/CloudMounter 2>&1 | tee transfer.log

# En otra terminal, presiona el botón "Iniciar" en la app
# Observa lo que aparece en la terminal - los logs te dirán exactamente qué está pasando
```

### Paso 3: Qué buscar en los logs

Deberías ver algo como esto:

```
📋 TransferView: Button tapped
  Source: googledrive, Dir: (root)
  Dest: onedrive, Dir: (root)
  Type: copy
📋 TransferView: Starting transfer [UUID]
🔄 TransferView: Transfer task started
🚀 RcloneService.startTransfer called
  Job ID: [UUID]
  Source: googledrive/(root)
  Dest: onedrive/(root)
  Type: copy
✅ rclone found at: /usr/local/bin/rclone
  Source spec: googledrive:
  Dest spec: onedrive:
📋 Command: rclone copy googledrive: onedrive: --stats 1s --stats-json --verbose --progress --transfers 4 --checkers 8 --timeout 60m --retries 10
🔄 Starting rclone process...
✅ Process started with PID: 12345
⏳ Waiting for process to complete...
✅ Process completed with exit code: 0
📊 Transferred: 1234567 bytes, 5 files
✅ TransferView: Transfer completed, success: true
```

### Paso 4: Si ves errores

#### Error: "rclone not found!"
```
❌ rclone not found!
```
**Solución**: 
```bash
# Asegúrate que rclone está en /usr/local/bin/
ls -la /usr/local/bin/rclone

# Si no existe, instálalo:
brew install rclone
# O descárgalo manualmente de rclone.org
```

#### Error: "exit code: 1" o superior
Busca en los logs: `⚠️ rclone stderr:`

Esto muestra el error real de rclone. Común:
- **"config file not found"**: El archivo de configuración de rclone no existe
- **"remote not configured"**: El remote "googledrive" no existe en rclone.conf
- **"permission denied"**: Problemas de permisos en las rutas

#### Error: "Error starting process"
```
❌ Error starting process: ...
```
Muestra el error específico de macOS. Generalmente:
- rclone no está en la ruta esperada
- Problemas de permisos

### Paso 5: Verificar configuración de rclone

```bash
# Ver todos los remotes configurados
rclone listremotes

# Ver la configuración completa
rclone config show

# Probar que un remote funciona
rclone ls googledrive:

# Ver el tipo de remote
rclone config get googledrive type
```

### Paso 6: Prueba manual con rclone

Si quieres probar la transferencia manualmente:

```bash
# Copiar desde googledrive a onedrive
rclone copy googledrive: onedrive: --progress

# Mover (copy + delete)
rclone copy googledrive: onedrive: --progress
rclone delete googledrive:

# Ver estadísticas en tiempo real
rclone copy googledrive: onedrive: --stats 1s --stats-json --progress
```

---

## Checklist de Diagnóstico

- [ ] rclone está instalado y en PATH
- [ ] `rclone listremotes` muestra mis remotes
- [ ] Los nombres de remotes en la app coinciden con `rclone listremotes`
- [ ] `rclone config show` muestra la configuración
- [ ] `rclone ls remoteName:` funciona (prueba de conectividad)
- [ ] Los remotes están montados (verde en la app)
- [ ] El botón "Iniciar" no está deshabilitado
- [ ] Los logs muestran que rclone se ejecuta

---

## Información que necesito

Si aún no funciona, copia la salida de estos comandos:

```bash
# 1. Logs de la app (si presionas Iniciar)
.build_output/CloudMounter.app/Contents/MacOS/CloudMounter 2>&1 | head -50

# 2. Lista de remotes
rclone listremotes

# 3. Verificación de rclone
which rclone
rclone --version

# 4. Estado de archivos de configuración
ls -la ~/.config/rclone/
```

Comparte esta información y podré diagnosticar exactamente cuál es el problema.

---

## Problemas Comunes

### "El botón está gris (deshabilitado)"
- ✅ Solución: Selecciona un remote en "Origen" y otro en "Destino"

### "Presiono pero no aparece la barra de progreso"
- Podría ser que:
  1. rclone no está en la ruta esperada
  2. Los remotes no existen
  3. Hay un error silencioso (checa los logs)

### "Se inicia pero falla después"
- Mira el error en los logs: `⚠️ rclone stderr:`
- Problemas típicos:
  - Permisos insuficientes
  - Remote no autenticado
  - Ruta destino no existe

### "Muy lento"
- ✅ Normal para archivos grandes
- Ve a Settings → Transferencias Avanzadas → Mover a "Rápido"
- Esto aumenta transferencias concurrentes

---

## Próximo Paso

1. Ejecuta la app en terminal para capturar logs
2. Presiona "Iniciar" en una transferencia de prueba
3. Copia los logs que ves en la terminal
4. Comparte los logs conmigo

¡Así podré identificar exactamente cuál es el problema!
