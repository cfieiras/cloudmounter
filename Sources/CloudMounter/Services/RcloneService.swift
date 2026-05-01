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
    // stdin is always /dev/null to prevent hanging on interactive prompts
    // (OAuth handled separately via Terminal for better UX)
    @discardableResult
    nonisolated func runProcess(executable: String, arguments: [String]) -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Suppress stdin to prevent hanging on interactive prompts
        process.standardInput = FileHandle.nullDevice
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

    // MARK: - Validate Remote Configuration
    /// Check if a remote is fully configured. OneDrive requires drive_id and drive_type.
    nonisolated func isRemoteConfigured(name: String, type: String) -> (ok: Bool, reason: String) {
        guard let rp = rclonePath() else { return (false, "rclone no encontrado") }

        // For OneDrive: require drive_id and drive_type
        if type == "onedrive" {
            let checkResult = shell("\"\(rp)\" config show \(name) 2>/dev/null | grep -E 'drive_id|drive_type'")
            let lines = checkResult.output.components(separatedBy: "\n").filter { !$0.isEmpty }
            let hasDriveId = lines.contains { $0.contains("drive_id") }
            let hasDriveType = lines.contains { $0.contains("drive_type") }
            if !hasDriveId || !hasDriveType {
                return (false, "Este remote de OneDrive necesita reconfiguración. " +
                              "Elimínalo y crea uno nuevo, o ejecutá: rclone config reconnect \"\(name):\"")
            }
        }
        return (true, "")
    }

    // MARK: - Mount (auto-selects FUSE or WebDAV)
    func mount(account: Account) async {
        await MainActor.run { account.status = .mounting }

        guard let rp = rclonePath() else {
            await setError(account: account, msg: "rclone no encontrado en el sistema")
            return
        }

        // Validate the remote is fully configured (OneDrive needs drive_id and drive_type)
        let (isConfigured, reason) = isRemoteConfigured(name: account.remoteName, type: account.provider.rawValue)
        guard isConfigured else {
            await setError(account: account, msg: reason)
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
            "--vfs-cache-mode", "writes",
            "--daemon",
            "--daemon-wait", "60s",
            "--log-level", "INFO",
            "--log-file", logFile,
        ]

        switch account.provider {
        case .onedrive:    args += ["--onedrive-chunk-size", "10M"]
        case .googledrive: args += ["--drive-chunk-size", "8M"]
        case .sftp:        args += ["--sftp-idle-timeout", "60s"]
        default: break
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

        process.arguments = [
            "serve", "webdav",
            "\(account.remoteName):",
            "--addr", "127.0.0.1:\(port)",
            "--vfs-cache-mode", "writes",
            "--log-level", "ERROR",
            "--log-file", logFile,
        ]
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
            // Wait briefly so rclone can flush its log before we read it
            try? await Task.sleep(nanoseconds: 500_000_000)
            let logContent = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
            let errMsg = buildErrorMessage(stdout: r.output, stderr: r.error, log: logContent)
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

    /// Creates a new rclone remote config entry.
    /// For OneDrive, runs the full interactive config (answering stdin) so rclone
    /// v1.73+ gets drive_id and drive_type without needing Terminal.
    func createRemote(name: String, type: String, extras: [String] = []) async -> (ok: Bool, error: String) {
        guard let rp = rclonePath() else { return (false, "rclone no encontrado") }
        if type == "onedrive" {
            return await createOneDriveRemote(name: name, rclonePath: rp)
        }
        var args = ["config", "create", name, type, "--non-interactive"]
        args += extras
        let r = runProcess(executable: rp, arguments: args)
        return (r.exitCode == 0, r.error.isEmpty ? r.output : r.error)
    }

    /// Full OneDrive setup replicating what `rclone config` does interactively.
    /// Feeds answers to stdin as rclone asks questions:
    ///   1. "Use web browser?" → y   (opens browser for OAuth)
    ///   2. "config_type>"    → 1   (OneDrive Personal or Business)
    ///   3. "config_driveid>" → N   (the number matching "OneDrive (personal)")
    ///   4. "Drive OK? y/n>"  → y   (confirm)
    /// This gives rclone v1.73+ the drive_id and drive_type it requires.
    private func createOneDriveRemote(name: String, rclonePath rp: String) async -> (ok: Bool, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: rp)
        process.arguments = ["config", "create", name, "onedrive"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe  = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe
        process.standardInput  = inPipe

        do { try process.run() } catch { return (false, error.localizedDescription) }

        let inHandle = inPipe.fileHandleForWriting
        DispatchQueue.global().async {
            func send(_ s: String) {
                NSLog("🔑 → stdin: [%@]", s.trimmingCharacters(in: .newlines))
                inHandle.write(s.data(using: .utf8)!)
            }

            // Short delay then answer Q1: use web browser for OAuth
            Thread.sleep(forTimeInterval: 0.5)
            send("y\n")
            NSLog("🔑 Sent 'y' — browser will open for OAuth")

            // Accumulate ALL output from both stdout and stderr so we can
            // match prompts even if they arrive in separate read() chunks.
            var accumulated = ""
            var answeredConfigType = false
            var answeredDriveId   = false
            var answeredDriveOk   = false

            let deadline = Date().addingTimeInterval(300)  // 5-min total

            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.3)

                let outStr = String(data: outPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
                let errStr = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
                if !outStr.isEmpty { NSLog("🔑 stdout: %@", outStr) }
                if !errStr.isEmpty { NSLog("🔑 stderr: %@", errStr) }
                accumulated += outStr + errStr

                // Q2: drive type — appears after OAuth "Got code"
                // Actual prompt rclone prints: "config_type> "
                if !answeredConfigType && accumulated.contains("config_type>") {
                    Thread.sleep(forTimeInterval: 0.3)
                    send("1\n")   // 1 = Microsoft OneDrive Personal or Business
                    answeredConfigType = true
                    NSLog("🔑 Sent '1' for config_type (personal/business)")
                }

                // Q3: drive ID — rclone lists available drives then shows "config_driveid> "
                // Find the line containing "OneDrive (personal)" and use its index number.
                if answeredConfigType && !answeredDriveId && accumulated.contains("config_driveid>") {
                    var driveNumber = "0"  // fallback: first entry
                    let lines = accumulated.components(separatedBy: "\n")
                    for line in lines {
                        let lower = line.lowercased()
                        // Match lines like: " 5 / OneDrive (personal) id=59D47BD0E893439F"
                        if lower.contains("onedrive") && lower.contains("personal") && !lower.contains("sharepoint") {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            // First token is the option number
                            if let first = trimmed.components(separatedBy: .whitespaces).first,
                               Int(first) != nil {
                                driveNumber = first
                            }
                            break
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.3)
                    NSLog("🔑 Selecting drive number: %@", driveNumber)
                    send("\(driveNumber)\n")
                    answeredDriveId = true
                }

                // Q4: "Drive OK? … y/n> " — confirm the selected drive
                if answeredDriveId && !answeredDriveOk &&
                   (accumulated.contains("Drive OK?") ||
                    (accumulated.contains("Found drive") && accumulated.contains("y/n>"))) {
                    Thread.sleep(forTimeInterval: 0.3)
                    send("y\n")
                    answeredDriveOk = true
                    NSLog("🔑 Sent 'y' for Drive OK")
                    Thread.sleep(forTimeInterval: 2)  // let rclone finalize
                }

                if !process.isRunning { break }
            }

            inHandle.closeFile()
        }

        // Wait up to 5 minutes total for process to complete
        let deadline = Date().addingTimeInterval(300)
        while process.isRunning && Date() < deadline {
            usleep(500_000)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()

        // Verify drive_id was written (rclone v1.73+ requires it)
        let check = shell("\"\(rp)\" config show \(name) 2>/dev/null | grep drive_id")
        let ok = !check.output.isEmpty
        NSLog("🔑 createOneDriveRemote '%@': ok=%d drive_id_line=%@", name, ok ? 1 : 0, check.output)
        return (ok, ok ? "" : "No se pudo crear el remote de OneDrive (falta drive_id)")
    }

    /// Runs the OAuth reconnect flow — opens the default browser, blocks until auth completes.
    /// Only called for non-OneDrive OAuth providers (Google Drive, Dropbox, Box).
    func reconnectRemote(name: String) async -> (ok: Bool, error: String) {
        guard let rp = rclonePath() else { return (false, "rclone no encontrado") }
        let r = runProcess(executable: rp,
                           arguments: ["config", "reconnect", "\(name):", "--auto-confirm"])
        return (r.exitCode == 0, r.error.isEmpty ? r.output : r.error)
    }

    /// Reconfigure an existing remote: delete and recreate it with full OAuth flow.
    /// Used when a remote has auth errors and needs to be re-authenticated.
    func reconfigureRemote(name: String, type: String) async -> (ok: Bool, error: String) {
        NSLog("🔄 Reconfiguring remote: %@", name)

        // Delete the broken remote
        deleteRemote(name: name)

        // Recreate with full OAuth flow
        return await createRemote(name: name, type: type)
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
        if combined.contains("no such host") || combined.contains("dial tcp") ||
           combined.contains("connection refused") || combined.contains("network is unreachable") {
            return "Sin conexión a internet o DNS no resuelve. " +
                   "Verificá tu red (si usás Tailscale, revisá su configuración de DNS)."
        }
        if combined.contains("couldn't connect") || combined.contains("failed to authorize") ||
           combined.contains("token expired") || combined.contains("401") {
            return "Error de autenticación — el token expiró. Eliminá y volvé a agregar la cuenta."
        }
        if combined.contains("unable to get drive_id") {
            return "Configuración de OneDrive incompleta (falta drive_id). " +
                   "Eliminá la cuenta y volvé a agregarla."
        }
        if combined.contains("didn't find section") {
            return "Remote no encontrado en la configuración de rclone. " +
                   "Eliminá la cuenta y volvé a agregarla."
        }
        if !combined.isEmpty {
            // Return the last non-empty line (most recent rclone log entry)
            return combined.components(separatedBy: "\n").last(where: { !$0.isEmpty }) ?? combined
        }
        // If all outputs are empty, try a quick connectivity probe for a better message
        let dnsCheck = shell("host graph.microsoft.com 2>&1")
        if dnsCheck.output.contains("no such host") || dnsCheck.output.contains("timed out") ||
           dnsCheck.exitCode != 0 {
            return "Sin conexión a internet o DNS no resuelve. " +
                   "Verificá tu red (si usás Tailscale, revisá su configuración de DNS)."
        }
        return "Error al montar. Intentá desmontar, esperá unos segundos y volvé a montar."
    }

    private nonisolated func shortError(_ msg: String) -> String {
        let first = msg.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? msg
        return first.count > 120 ? String(first.prefix(120)) + "…" : first
    }
}
