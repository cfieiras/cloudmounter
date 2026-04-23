import Foundation
import Combine

@MainActor
class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published var accounts: [Account] = []
    @Published var availableRemotes: [RemoteInfo] = []
    @Published var isLoadingRemotes = false
    @Published var globalLog: [LogEntry] = []

    private let saveKey = "com.cloudmounter.accounts"

    struct RemoteInfo: Identifiable {
        let id = UUID()
        let name: String
        let type: String
        var provider: CloudProvider { CloudProvider.detect(from: name, rcloneType: type) }
        var isAlreadyAdded: Bool = false
    }

    private init() { load() }

    // MARK: - Persistence
    func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([Account].self, from: data) else { return }
        accounts = saved
    }

    // MARK: - Account Management
    func add(account: Account) {
        accounts.append(account)
        save()
        log("Cuenta '\(account.label)' agregada", level: .success)
    }

    func remove(account: Account) {
        accounts.removeAll { $0.id == account.id }
        save()
        log("Cuenta '\(account.label)' eliminada", level: .warning)
    }

    func update() { save() }

    func moveAccounts(from offsets: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    // MARK: - Remotes
    func loadRemotes() async {
        isLoadingRemotes = true
        defer { isLoadingRemotes = false }
        let remotes = await RcloneService.shared.listRemotes()
        let addedNames = Set(accounts.map { $0.remoteName })
        availableRemotes = remotes.map { r in
            var info = r
            info.isAlreadyAdded = addedNames.contains(r.name)
            return info
        }
    }

    // MARK: - Logging
    func log(_ message: String, level: LogEntry.Level = .info) {
        let entry = LogEntry(message: message, level: level)
        globalLog.insert(entry, at: 0)
        if globalLog.count > 200 { globalLog = Array(globalLog.prefix(200)) }
    }

    func clearLog() { globalLog.removeAll() }

    // MARK: - Computed
    var mountedCount: Int { accounts.filter { $0.isMounted }.count }
}
