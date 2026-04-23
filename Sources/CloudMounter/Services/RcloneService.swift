import Foundation
import AppKit
import UserNotifications

actor RcloneService {
    static let shared = RcloneService()

    private let rclonePaths = [
        "/usr/local/bin/rclone",       // oficial rclone.org (preferido)
        "/opt/homebrew/bin/rclone",    // Homebrew (no soporta mount en macOS)
        "/usr/bin/rclone",
    ]

    // WebDAV processes per account (UUID → process)
    private var webdavProcesses: [UUID: Process] = [:]
    // Base port for WebDAV servers (one port per account)
    private let webdavBasePort = 18765

    // MARK: - Process runner — safe for arbitrary args (no shell quoting needed)
    // stdin is /dev/null by default to prevent hanging, except for auth commands
    @discardableResult
    nonisolated func runProcess(executable: String, arguments: [String]) -> (output: String, error: String, exitCode: Int32) {
        return runProcess(executable: executable, arguments: arguments, allowInteractiveInput: false)
    }

    @discardableResult
    nonisolated func runProcess(executable: String, arguments: [String], allowInteractiveInput: Bool) -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // For OAuth/auth commands, allow interaction with user terminal
        // For other commands, suppress stdin to avoid hanging
        if allowInteractiveInput {
            // Use inherited stdin (connected to current terminal for OAuth flow)
            process.standardInput = FileHandle.standardInput
        } else {
            // Suppress stdin to prevent hanging on interactive prompts
            process.standardInput = FileHandle.nullDevice
        }

        do { try process.run() } catch { return ("", error.localizedDescription, -1) }
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out.trimmingCharacters(in: .newlines),
                err.trimmingCharacters(in: .newlines),
                process.terminationStatus)
    }

    // Shell helper for simple one-liners
    @discardableResult
    nonisolated func shell(_ command: String) -> (output: String, error: String, exitCode: Int32) {
        return runProcess(executable: "/bin/bash", arguments: ["-c", command])
    }

    // MARK: - Find rclone (nonisolated: only reads let constants)
    nonisolated func rclonePath() -> String? {
        for path in rclonePaths {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        let result = shell("which rclone")
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Returns true only if rclone mount (FUSE) is confirmed to work on this system.
    // Conservative check: requires a kernel-level FUSE to be active.
    // FUSE-T without an approved system extension is NOT sufficient.
    nonisolated func isFuseAvailable() -> Bool {
        // macFUSE kext loaded and active?
        let kext = shell("kextstat 2>/dev/null | grep -i fuse | wc -l")
        if (Int(kext.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0 { return true }
        // FUSE-T via NFSv4 — requires go-nfsv4 daemon running (not just fuse-t.app)
        let goNFS = shell("pgrep -x go-nfsv4").exitCode == 0
        return goNFS
    }

    // MARK: - Dependency Checks
    nonisolated func checkDependencies() -> (rclone: Bool, rcloneOfficialOk: Bool, fuse: Bool, webdav: Bool, rclonePath: String) {
        let rp = rclonePath()
        let fuseAvail = isFuseAvailable()
        // rcloneOfficialOk: the binary supports mount (not the Homebrew-restricted one)
        var officialOk = false
        if let rp = rp {
            let test = shell("\"\(rp)\" mount --help 2>&1 | head -1")
            officialOk = test.output.lowercased().contains("rclone mount allows") ||
                         test.output.lowercased().contains("mount any of")
        }
        return (
            rclone: rp != nil,
            rcloneOfficialOk: officialOk,
            fuse: fuseAvail,
            webdav: rp != nil,   // WebDAV always available if rclone exists
            rclonePath: rp ?? ""
        )
    }

    // MARK: - List Remotes
    func listRemotes() async -> [AccountStore.RemoteInfo] {
        guard let rp = rclonePath() else { return [] }

        let nameResult = shell("\"\(rp)\" listremotes")
        let names = nameResult.output
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.hasSuffix(":") ? String(t.dropLast()) : nil
            }

        let configResult = shell("\"\(rp)\" config show --json 2>/dev/null")
        var typeMap: [String: String] = [:]
        if let data = configResult.output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, val) in json {
                if let dict = val as? [String: String], let t = dict["type"] { typeMap[key] = t }
            }
        }
        return names.map { AccountStore.RemoteInfo(name: $0, type: typeMap[$0] ?? "") }
    }

    // MARK: - Mount (auto-selects FUSE or WebDAV)
    func mount(account: Account) async {
        await MainActor.run { account.status = .mounting }

        guard let rp = rclonePath() else {
            await setError(account: account, msg: "rclone no encontrado en el sistema")
            return
        }

        // Validate rclone can mount (not the Homebrew-restricted binary)
        let helpCheck = shell("\"\(rp)\" mount --help 2>&1 | head -1")
        let canMount = helpCheck.output.lowercased().contains("rclone mount allows") ||
                       helpCheck.output.lowercased().contains("mount any of")
        guard canMount else {
            await setError(account: account,
                msg: "El rclone instalado no soporta mount. " +
                     "Descargá el binario oficial desde rclone.org/downloads " +
                     "y copialo a /usr/local/bin/rclone")
            return
        }

        if isFuseAvailable() {
            await mountFuse(account: account, rclonePath: rp)
        } else {
            await mountWebDAV(account: account, rclonePath: rp)
        }
    }

    // MARK: - FUSE Mount
    private func mountFuse(account: Account, rclonePath rp: String) async {
        let mountPoint = account.resolvedMountPath
        let logFile = "/tmp/cloudmounter-\(account.id.uuidString.prefix(8)).log"
        try? FileManager.default.removeItem(atPath: logFile) // clear stale log

        let home = NSHomeDirectory()
        let forbidden = [home, "/", "/Users", "/System", "/Library", "/Applications", "/usr", "/tmp"]
        if forbidden.contains(mountPoint) {
            await setError(account: account,
                msg: "Carpeta de montaje inválida: '\(mountPoint)'. " +
                     "Usá una subcarpeta, por ejemplo ~/CloudMounts/\(account.remoteName)")
            return
        }

        try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        var args: [String] = [
            "mount",
            "\(account.remoteName):",
            mountPoint,
            // ─── CACHE & PERFORMANCE ───
            "--vfs-cache-mode", "full",              // Full caching for better performance
            "--vfs-cache-max-age", "24h",            // Keep cache for 24 hours
            "--vfs-cache-max-size", "5G",            // Max cache size (adjust based on disk space)
            "--buffer-size", "32M",                  // Larger buffer for streaming

            // ─── CONCURRENCY & PARALLELISM ───
            "--transfers", "8",                      // 8 concurrent transfers (optimized for bandwidth)
            "--checkers", "16",                      // 16 parallel checkers (verify integrity)
            "--cache-read-retries", "5",             // Retry failed reads
            "--low-level-retries", "10",             // 10 retries for network issues

            // ─── TIMEOUTS (for large files) ───
            "--timeout", "30m",                      // 30 minute timeout for operations
            "--contimeout", "60s",                   // Connection timeout
            "--retries", "5",                        // Top-level retries
            "--retries-sleep", "100ms",              // Wait between retries

            // ─── STABILITY ───
            "--daemon",
            "--daemon-wait", "60s",
            "--log-level", "INFO",
            "--log-file", logFile,
            "--poll-interval", "1m",                 // Check for changes every minute
        ]

        // Provider-specific optimizations
        switch account.provider {
        case .onedrive:
            args += [
                "--onedrive-chunk-size", "50M",      // Larger chunks = faster transfers
                "--onedrive-drive-type", "business",  // Better for business accounts
                "--onedrive-no-auth-with-default", "false",
                "--onedrive-expiry-time", "60m",     // Token expiry handling
            ]
        case .googledrive:
            args += [
                "--drive-chunk-size", "32M",         // Larger chunks than before
                "--drive-service-account-file", "/path/to/sa.json",  // If using service account
                "--drive-use-trash", "true",
            ]
        case .sftp:
            args += [
                "--sftp-idle-timeout", "5m",         // Longer idle timeout for long transfers
                "--sftp-concurrency", "8",           // Concurrent SFTP operations
            ]
        default:
            // Generic cloud providers
            args += [
                "--multi-thread-streams", "4",       // Multi-threaded downloads
            ]
        }

        let result = runProcess(executable: rp, arguments: args)

        if result.exitCode == 0 {
            await mountSucceeded(account: account, mountPoint: mountPoint, method: "FUSE")
        } else {
            let logContent = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
            let errMsg = buildErrorMessage(stdout: result.output, stderr: result.error, log: logContent)
            await setError(account: account, msg: errMsg)
        }
    }

    // MARK: - WebDAV Mount (no FUSE required)
    private func mountWebDAV(account: Account, rclonePath rp: String) async {
        let port = webdavPort(for: account)
        let mountPoint = account.resolvedMountPath
        let logFile = "/tmp/cloudmounter-\(account.id.uuidString.prefix(8)).log"
        try? FileManager.default.removeItem(atPath: logFile) // clear stale log

        // Validate mount point — reject dangerous paths
        let home = NSHomeDirectory()
        let forbidden = [home, "/", "/Users", "/System", "/Library", "/Applications", "/usr", "/tmp"]
        if forbidden.contains(mountPoint) {
            await setError(account: account,
                msg: "Carpeta de montaje inválida: '\(mountPoint)'. " +
                     "Usá una subcarpeta, por ejemplo ~/CloudMounts/\(account.remoteName)")
            return
        }

        try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        // Kill any existing WebDAV process for this account
        stopWebDAVProcess(for: account.id)

        // Start rclone WebDAV server (non-blocking background process)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: rp)

        // WebDAV-optimized arguments for fast bulk transfers
        var webdavArgs: [String] = [
            "serve", "webdav",
            "\(account.remoteName):",
            "--addr", "127.0.0.1:\(port)",

            // ─── CACHE & PERFORMANCE ───
            "--vfs-cache-mode", "full",              // Full caching for WebDAV
            "--vfs-cache-max-age", "24h",
            "--vfs-cache-max-size", "5G",
            "--buffer-size", "32M",

            // ─── CONCURRENCY & PARALLELISM ───
            "--transfers", "8",                      // Concurrent WebDAV transfers
            "--checkers", "16",
            "--cache-read-retries", "5",
            "--low-level-retries", "10",

            // ─── TIMEOUTS ───
            "--timeout", "30m",                      // Long timeout for large files
            "--contimeout", "60s",
            "--retries", "5",
            "--retries-sleep", "100ms",

            // ─── WebDAV SPECIFIC ───
            "--webdav-bearer-token-cmd", "",        // If using bearer tokens
            "--poll-interval", "1m",
            "--log-level", "ERROR",                 // Avoid noise
            "--log-file", logFile,
        ]

        // Add provider-specific optimizations for WebDAV
        switch account.provider {
        case .onedrive:
            webdavArgs += [
                "--onedrive-chunk-size", "50M",
                "--onedrive-drive-type", "business",
            ]
        case .googledrive:
            webdavArgs += [
                "--drive-chunk-size", "32M",
            ]
        case .sftp:
            webdavArgs += [
                "--sftp-idle-timeout", "5m",
                "--sftp-concurrency", "8",
            ]
        default:
            webdavArgs += ["--multi-thread-streams", "4"]
        }

        process.arguments = webdavArgs
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            await setError(account: account, msg: "No se pudo iniciar servidor WebDAV: \(error.localizedDescription)")
            return
        }
        webdavProcesses[account.id] = process

        // Wait for the server to start listening (up to 10s)
        var serverReady = false
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s each
            // nc -z: TCP connect test — simpler and correct regardless of OS flags
            if shell("nc -z 127.0.0.1 \(port) 2>/dev/null").exitCode == 0 {
                serverReady = true
                break
            }
        }

        guard serverReady else {
            stopWebDAVProcess(for: account.id)
            let logContent = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
            await setError(account: account, msg: buildErrorMessage(stdout: "", stderr: "", log: logContent))
            return
        }

        // Mount via macOS native WebDAV
        let r = runProcess(executable: "/sbin/mount_webdav",
                           arguments: ["-s", "http://127.0.0.1:\(port)/", mountPoint])
        if r.exitCode == 0 {
            await mountSucceeded(account: account, mountPoint: mountPoint, method: "WebDAV")
        } else {
            stopWebDAVProcess(for: account.id)
            let logContent = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
            let errMsg = r.error.isEmpty ? buildErrorMessage(stdout: r.output, stderr: "", log: logContent) : r.error
            await setError(account: account, msg: errMsg)
        }
    }

    // MARK: - Unmount
    func unmount(account: Account) async {
        await MainActor.run { account.status = .unmounting }
        let mountPoint = account.resolvedMountPath

        // Unmount filesystem
        let r1 = shell("diskutil unmount force \"\(mountPoint)\" 2>/dev/null")
        if r1.exitCode != 0 {
            _ = shell("umount \"\(mountPoint)\" 2>/dev/null")
        }

        // Stop WebDAV server if it was a WebDAV mount
        stopWebDAVProcess(for: account.id)

        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            account.status = .unmounted
            account.driveInfo = nil
            AccountStore.shared.log("'\(account.label)' desmontado", level: .info)
        }
        sendNotification(title: "Desmontado", body: "\(account.label) fue desmontado")
    }

    // nonisolated version for app termination
    nonisolated func unmountSync(account: Account) {
        let mountPoint = account.resolvedMountPath
        _ = shell("diskutil unmount force \"\(mountPoint)\" 2>/dev/null || umount \"\(mountPoint)\" 2>/dev/null")
        // Kill matching rclone serve webdav process
        _ = shell("pkill -f \"rclone serve webdav.*\(account.remoteName)\" 2>/dev/null")
    }

    // MARK: - WebDAV helpers
    private func webdavPort(for account: Account) -> Int {
        // Stable port derived from the account UUID (range 18765–19764)
        let hash = abs(account.id.hashValue) % 1000
        return webdavBasePort + hash
    }

    private func stopWebDAVProcess(for id: UUID) {
        if let proc = webdavProcesses[id], proc.isRunning {
            proc.terminate()
        }
        webdavProcesses.removeValue(forKey: id)
    }

    // MARK: - Mount Status Check
    func checkMountStatus(account: Account) async -> Bool {
        let mountPoint = account.resolvedMountPath
        // Check via mount output (works for both FUSE and WebDAV)
        let byMount = shell("mount | grep \"\(mountPoint)\" 2>/dev/null | wc -l")
        if (Int(byMount.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0 { return true }
        // WebDAV fallback: check if the rclone server port is still open
        let port = webdavPort(for: account)
        return shell("nc -z 127.0.0.1 \(port) 2>/dev/null").exitCode == 0
    }

    func refreshAllStatuses(accounts: [Account]) async {
        for account in accounts {
            let mounted = await checkMountStatus(account: account)
            await MainActor.run {
                if mounted && account.status != .mounted {
                    account.status = .mounted
                } else if !mounted && account.status == .mounted {
                    account.status = .unmounted
                    account.driveInfo = nil
                }
            }
            if mounted {
                await refreshDriveInfo(account: account)
            }
        }
    }

    // MARK: - Drive Info
    func refreshDriveInfo(account: Account) async {
        guard account.isMounted else { return }
        let mountPoint = account.resolvedMountPath
        let result = shell("df -k \"\(mountPoint)\" 2>/dev/null | tail -1")
        let parts = result.output.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 4,
              let total = Int64(parts[1]),
              let used  = Int64(parts[2]),
              let avail = Int64(parts[3]) else { return }
        let info = DriveInfo(total: total * 1024, used: used * 1024, free: avail * 1024)
        await MainActor.run { account.driveInfo = info }
    }

    // MARK: - Open in Finder (nonisolated)
    nonisolated func openInFinder(account: Account) {
        NSWorkspace.shared.open(URL(fileURLWithPath: account.resolvedMountPath))
    }

    // MARK: - LaunchAgent (Auto-mount)
    func updateLaunchAgent(accounts: [Account]) {
        let agentID      = "com.cloudmounter.automount"
        let agentPath    = "\(NSHomeDirectory())/Library/LaunchAgents/\(agentID).plist"
        let wrapperPath  = "\(NSHomeDirectory())/.cloudmounter_autostart.sh"
        let fuseOk       = isFuseAvailable()

        _ = shell("launchctl unload \"\(agentPath)\" 2>/dev/null")
        try? FileManager.default.removeItem(atPath: agentPath)
        try? FileManager.default.removeItem(atPath: wrapperPath)

        let autoAccounts = accounts.filter { $0.autoMount }
        guard !autoAccounts.isEmpty, let rp = rclonePath() else { return }

        var script = "#!/bin/bash\nsleep 5\n"
        for acc in autoAccounts {
            let mp = acc.resolvedMountPath
            let port = webdavPort(for: acc)
            script += "mkdir -p \"\(mp)\"\n"
            if fuseOk {
                script += "\"\(rp)\" mount \"\(acc.remoteName):\" \"\(mp)\" --vfs-cache-mode writes --daemon --daemon-wait 60s\n"
            } else {
                // WebDAV approach
                script += "\"\(rp)\" serve webdav \"\(acc.remoteName):\" --addr 127.0.0.1:\(port) --vfs-cache-mode writes &\n"
                script += "sleep 3\n"
                script += "/sbin/mount_webdav -s http://127.0.0.1:\(port)/ \"\(mp)\"\n"
            }
        }
        try? script.write(toFile: wrapperPath, atomically: true, encoding: .utf8)
        _ = shell("chmod +x \"\(wrapperPath)\"")

        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>\(agentID)</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>\(wrapperPath)</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>StandardErrorPath</key><string>/tmp/cloudmounter.log</string>
    <key>StandardOutPath</key><string>/tmp/cloudmounter.log</string>
</dict>
</plist>
"""
        let agentDir = "\(NSHomeDirectory())/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: agentDir, withIntermediateDirectories: true)
        try? plist.write(toFile: agentPath, atomically: true, encoding: .utf8)
        _ = shell("launchctl load \"\(agentPath)\" 2>/dev/null")
    }

    // MARK: - Remote Management (no terminal needed)

    /// Creates a new rclone remote config entry non-interactively.
    /// For OAuth providers this only creates a skeleton — call reconnectRemote() after.
    /// extras: additional key=value pairs e.g. ["host=myhost", "user=admin"]
    func createRemote(name: String, type: String, extras: [String] = []) async -> (ok: Bool, error: String) {
        guard let rp = rclonePath() else { return (false, "rclone no encontrado") }
        var args = ["config", "create", name, type, "--non-interactive"]
        args += extras
        let r = runProcess(executable: rp, arguments: args)
        return (r.exitCode == 0, r.error.isEmpty ? r.output : r.error)
    }

    /// Runs the OAuth reconnect flow — opens the default browser, allows user to authenticate.
    /// This needs interactive terminal access for OAuth to work properly.
    func reconnectRemote(name: String) async -> (ok: Bool, error: String) {
        guard let rp = rclonePath() else { return (false, "rclone no encontrado") }

        // Use 'config reconnect' with interactive stdin for OAuth flow
        // This opens the browser and allows the user to complete authentication
        // CRITICAL: allowInteractiveInput must be true for OAuth to work
        let r = runProcess(executable: rp,
                           arguments: ["config", "reconnect", "\(name):"],
                           allowInteractiveInput: true)

        return (r.exitCode == 0, r.error.isEmpty ? r.output : r.error)
    }

    /// Removes a remote from rclone config.
    func deleteRemote(name: String) {
        guard let rp = rclonePath() else { return }
        _ = runProcess(executable: rp, arguments: ["config", "delete", name])
    }

    /// Returns rclone-obscured version of a plaintext password.
    func obscurePassword(_ password: String) -> String {
        guard let rp = rclonePath() else { return password }
        let r = runProcess(executable: rp, arguments: ["obscure", password])
        return r.exitCode == 0 ? r.output : password
    }

    // MARK: - Open rclone config in Terminal (nonisolated)
    nonisolated func openRcloneConfig() {
        guard let rp = rclonePath() else { return }
        let script = """
tell application "Terminal"
    activate
    do script "\(rp) config"
end tell
"""
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    // MARK: - Notifications (nonisolated)
    nonisolated func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Private helpers
    private func mountSucceeded(account: Account, mountPoint: String, method: String) async {
        await MainActor.run {
            account.status = .mounted
            account.lastError = nil
            AccountStore.shared.log("'\(account.label)' montado en \(mountPoint) (\(method))", level: .success)
        }
        sendNotification(title: "Montado ✓", body: "\(account.label) disponible en Finder")
        await refreshDriveInfo(account: account)

        // Load cloud space info in background
        Task {
            if let about = await getCloudAbout(remoteName: account.remoteName) {
                await MainActor.run {
                    account.cloudFree = about.free
                    account.cloudTotal = about.total
                }
            }
        }
    }

    private func setError(account: Account, msg: String) async {
        let short = shortError(msg)
        await MainActor.run {
            account.status = .error(short)
            account.lastError = msg
            AccountStore.shared.log("Error montando '\(account.label)': \(msg)", level: .error)
        }
        sendNotification(title: "Error al montar", body: "\(account.label): \(short)")
    }

    // MARK: - Space & Cache Management

    func getCloudAbout(remoteName: String) async -> (free: Int64, total: Int64)? {
        guard let rp = rclonePath() else { return nil }
        let r = runProcess(executable: rp, arguments: ["about", "\(remoteName):", "--json"])

        if r.exitCode == 0, let data = r.output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let free = (json["free"] as? Int64) ?? 0
            let total = (json["total"] as? Int64) ?? 0
            return (free, total)
        }
        return nil
    }

    nonisolated func getLocalFolderSize(path: String) -> Int64 {
        var totalSize: Int64 = 0
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }

        for case let file as String in enumerator {
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }

    func clearWebDAVCache(account: Account) async {
        let cacheDir = "\(NSHomeDirectory())/.cache/rclone"
        try? FileManager.default.removeItem(atPath: cacheDir)
    }

    private nonisolated func buildErrorMessage(stdout: String, stderr: String, log: String) -> String {
        let combined = [log, stderr, stdout].first(where: { !$0.isEmpty }) ?? ""

        if combined.contains("not supported on MacOS when rclone is installed via Homebrew") {
            return "El rclone de Homebrew no soporta mount. " +
                   "Descargá el binario oficial desde rclone.org/downloads (arm64) " +
                   "y copialo a /usr/local/bin/rclone."
        }
        if combined.contains("failed to mount FUSE fs") || combined.contains("fuse: device not found") ||
           combined.contains("the file system is not available") {
            return "FUSE no disponible. La app usará WebDAV automáticamente en el próximo intento."
        }
        if combined.contains("couldn't connect") || combined.contains("failed to authorize") ||
           combined.contains("oauth") || combined.contains("token") {
            return "Error de autenticación — el token puede haber expirado. " +
                   "Reconfigurá con: rclone config reconnect \"\(combined)\""
        }
        if !combined.isEmpty {
            return combined.components(separatedBy: "\n").last(where: { !$0.isEmpty }) ?? combined
        }
        return "Error desconocido (revisá /tmp/cloudmounter-*.log)"
    }

    private nonisolated func shortError(_ msg: String) -> String {
        let first = msg.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? msg
        return first.count > 120 ? String(first.prefix(120)) + "…" : first
    }
}
