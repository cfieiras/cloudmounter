import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @State private var selectedAccount: Account? = nil
    @State private var showAddSheet = false
    @State private var showDepsAlert = false
    // rclone present, rclone official (mount-capable), fuse active, webdav available
    @State private var depsOk: (rclone: Bool, rcloneOk: Bool, fuse: Bool, webdav: Bool) = (false, false, false, false)
    @State private var selectedTab: Tab = .accounts
    @State private var refreshTimer: Timer? = nil
    @State private var showAbout = false

    enum Tab: String, CaseIterable {
        case accounts = "Cuentas"
        case log      = "Log"
        case settings = "Ajustes"

        var icon: String {
            switch self {
            case .accounts: return "externaldrive.fill.badge.wifi"
            case .log:      return "terminal.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch selectedTab {
            case .accounts: accountsView
            case .log:      LogView()
            case .settings: SettingsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            checkDeps()
            Task { await store.loadRemotes() }
            startRefreshTimer()
        }
        .onDisappear { refreshTimer?.invalidate() }
        .sheet(isPresented: $showAddSheet) {
            AddAccountSheet(isPresented: $showAddSheet)
                .environmentObject(store)
        }
        .sheet(isPresented: $showAbout) {
            AboutView(isPresented: $showAbout)
        }
        .alert("Faltan dependencias", isPresented: $showDepsAlert) {
            Button("Cerrar") {}
        } message: {
            VStack(alignment: .leading) {
                if !depsOk.rclone {
                    Text("• rclone no encontrado. Descargá el binario oficial desde rclone.org/downloads")
                } else if !depsOk.rcloneOk {
                    Text("• El rclone instalado es de Homebrew y no soporta mount en macOS.\nDescargá el binario oficial desde rclone.org/downloads (arm64) y copialo a /usr/local/bin/rclone")
                }
            }
        }
    }

    // MARK: - Sidebar
    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CloudMounter").font(.headline)
                    Text("\(store.mountedCount) de \(store.accounts.count) montados")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            VStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    SidebarTabButton(tab: tab, selected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)

            Spacer()
            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(systemReady ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !systemReady {
                        Button("?") { showDepsAlert = true }
                            .buttonStyle(.borderless)
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 12)

                Button { showAddSheet = true } label: {
                    Label("Agregar cuenta", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)

                Button { showAbout = true } label: {
                    Label("Acerca de", systemImage: "info.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 200, idealWidth: 220)
        .background(.ultraThinMaterial)
    }

    // MARK: - Accounts View
    var accountsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cuentas").font(.title2.bold())
                Spacer()
                Button(action: mountAll) {
                    Label("Montar todo", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)

                Button(action: unmountAll) {
                    Label("Desmontar todo", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button { Task { await store.loadRemotes() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)

            Divider()

            if store.accounts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.accounts) { account in
                            AccountCard(account: account, isSelected: selectedAccount?.id == account.id)
                                .onTapGesture { selectedAccount = account }
                                .contextMenu { accountContextMenu(account: account) }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cloud.slash.fill")
                .font(.system(size: 64)).foregroundStyle(.quaternary)
            Text("Sin cuentas").font(.title2.bold()).foregroundStyle(.secondary)
            Text("Agregá una cuenta de OneDrive, Google Drive\no cualquier remote de rclone.")
                .multilineTextAlignment(.center).foregroundStyle(.tertiary).frame(maxWidth: 300)
            Button { showAddSheet = true } label: {
                Label("Agregar primera cuenta", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    @ViewBuilder
    func accountContextMenu(account: Account) -> some View {
        if account.isMounted {
            Button("Abrir en Finder") { RcloneService.shared.openInFinder(account: account) }
            Button("Desmontar") { Task { await RcloneService.shared.unmount(account: account) } }
        } else {
            Button("Montar") { Task { await RcloneService.shared.mount(account: account) } }
        }
        Divider()
        Button("Eliminar", role: .destructive) { store.remove(account: account) }
    }

    // MARK: - Actions
    func mountAll() {
        for account in store.accounts where !account.isMounted {
            Task { await RcloneService.shared.mount(account: account) }
        }
    }

    func unmountAll() {
        for account in store.accounts where account.isMounted {
            Task { await RcloneService.shared.unmount(account: account) }
        }
    }

    // System is ready if rclone (official) is present + any mount method works
    var systemReady: Bool { depsOk.rclone && depsOk.rcloneOk && (depsOk.fuse || depsOk.webdav) }

    var statusLabel: String {
        if !depsOk.rclone        { return "rclone no instalado" }
        if !depsOk.rcloneOk      { return "rclone Homebrew (no soporta mount)" }
        if depsOk.fuse           { return "Sistema listo · FUSE" }
        if depsOk.webdav         { return "Sistema listo · WebDAV" }
        return "Faltan dependencias"
    }

    func checkDeps() {
        Task {
            let deps = RcloneService.shared.checkDependencies()
            await MainActor.run {
                depsOk = (deps.rclone, deps.rcloneOfficialOk, deps.fuse, deps.webdav)
                // Solo mostrar alerta si rclone falta o es el de Homebrew
                if !deps.rclone || !deps.rcloneOfficialOk { showDepsAlert = true }
            }
        }
    }

    func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { await RcloneService.shared.refreshAllStatuses(accounts: store.accounts) }
        }
    }
}

// MARK: - Sidebar Tab Button
struct SidebarTabButton: View {
    let tab: ContentView.Tab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon).frame(width: 18)
                Text(tab.rawValue)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor.opacity(0.15) : .clear)
            .cornerRadius(8)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
