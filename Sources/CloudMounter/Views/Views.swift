import SwiftUI

// MARK: - AccountCard
struct AccountCard: View {
    @ObservedObject var account: Account
    let isSelected: Bool
    @State private var isHovered = false
    @State private var showDetails = false
    @State private var showReconfigureSheet = false
    @EnvironmentObject var store: AccountStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                providerIcon
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(account.label).font(.headline)
                        statusBadge
                    }
                    Text(account.remoteName + ":").font(.caption).foregroundStyle(.secondary).monospaced()
                    if !account.notes.isEmpty {
                        Text(account.notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                    }
                    Text(account.resolvedMountPath)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if account.isMounted {
                    spaceDisplayView
                }
                actionButtons
            }
            .padding(16)

            if account.isMounted {
                VStack(spacing: 8) {
                    Divider().padding(.horizontal, 16)

                    // Cloud space bar
                    if let free = account.cloudFree, let total = account.cloudTotal, total > 0 {
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.1))
                                        .frame(height: 8)

                                    let usedPercent = Double(total - free) / Double(total)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(barColor(percent: usedPercent))
                                        .frame(width: geo.size.width * usedPercent, height: 8)
                                        .animation(.easeInOut, value: usedPercent)
                                }
                            }
                            .frame(height: 8)

                            HStack {
                                Text("Nube")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.0f%% disponible", (Double(free) / Double(total)) * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .bold()
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Local space bar
                    if let info = account.driveInfo {
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.1))
                                        .frame(height: 8)

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(barColor(percent: info.usedPercent))
                                        .frame(width: geo.size.width * info.usedPercent, height: 8)
                                        .animation(.easeInOut, value: info.usedPercent)
                                }
                            }
                            .frame(height: 8)

                            HStack {
                                Text("Local")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.0f%% disponible", (Double(info.free) / Double(info.total)) * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .bold()
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer().frame(height: 4)
                }
            }

            if let err = account.lastError, case .error = account.status {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(err).font(.caption).foregroundStyle(.orange)
                        Button(action: {
                            // Save provider info before deleting
                            let provider = account.provider
                            let remoteName = account.remoteName

                            // Delete broken account
                            AccountStore.shared.remove(account: account)

                            // Show login sheet with provider preselected
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showReconfigureSheet = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Reconfigurar")
                            }
                            .font(.caption2).bold()
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.002 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onTapGesture(count: 2) { showDetails = true }
        .sheet(isPresented: $showDetails) {
            AccountDetailsSheet(account: account, isPresented: $showDetails)
        }
        .sheet(isPresented: $showReconfigureSheet) {
            ReconfigureAccountSheet(
                provider: account.provider,
                remoteName: account.remoteName,
                isPresented: $showReconfigureSheet
            )
        }
    }

    var providerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(account.provider.color.opacity(0.12))
                .frame(width: 48, height: 48)
            Image(systemName: account.provider.icon)
                .font(.title3)
                .foregroundStyle(account.provider.color)
            if account.isMounted {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: 18, y: 18)
            }
        }
    }

    var statusBadge: some View {
        HStack(spacing: 4) {
            if account.status.isBusy {
                ProgressView().scaleEffect(0.6).frame(width: 10, height: 10)
            } else {
                Circle().fill(account.status.color).frame(width: 6, height: 6)
            }
            Text(account.status.label).font(.caption).foregroundStyle(account.status.color)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(account.status.color.opacity(0.1))
        .clipShape(Capsule())
    }

    var spaceDisplayView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Just the label/title line
            HStack(spacing: 8) {
                if let free = account.cloudFree {
                    Image(systemName: "cloud.fill").font(.caption).foregroundStyle(.blue)
                    Text(DriveInfo.format(free) + " libres")
                        .font(.caption).bold()
                        .foregroundStyle(.blue)
                }
                if let info = account.driveInfo {
                    Spacer()
                    Image(systemName: "internaldrive.fill").font(.caption).foregroundStyle(.orange)
                    Text(DriveInfo.format(info.free) + " libres")
                        .font(.caption).bold()
                        .foregroundStyle(.orange)
                }
            }
            .padding(.bottom, 8)
        }
    }

    func driveInfoView(info: DriveInfo) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(DriveInfo.format(info.free) + " libres").font(.caption.bold())
            Text("de " + DriveInfo.format(info.total)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    func storageBar(info: DriveInfo) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(percent: info.usedPercent))
                        .frame(width: geo.size.width * info.usedPercent, height: 4)
                        .animation(.easeInOut, value: info.usedPercent)
                }
            }
            .frame(height: 4)
            HStack {
                Text(DriveInfo.format(info.used) + " usados").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", info.usedPercent * 100))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    func barColor(percent: Double) -> Color {
        if percent > 0.9 { return .red }
        if percent > 0.75 { return .orange }
        return .blue
    }

    var actionButtons: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Toggle("", isOn: Binding(
                    get: { account.autoMount },
                    set: { val in
                        account.autoMount = val
                        AccountStore.shared.save()
                        Task { await RcloneService.shared.updateLaunchAgent(accounts: AccountStore.shared.accounts) }
                    }
                ))
                .toggleStyle(.switch).controlSize(.mini)
                Text("auto").font(.caption2).foregroundStyle(.secondary)
            }
            Divider().frame(height: 32)
            if account.isMounted {
                Button { RcloneService.shared.openInFinder(account: account) } label: {
                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                }
                .buttonStyle(.borderless).help("Abrir en Finder")
            }
            mountButton
            Button { showDetails = true } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless).help("Detalles y opciones")
        }
    }

    var mountButton: some View {
        Group {
            if account.status.isBusy {
                ProgressView().scaleEffect(0.8).frame(width: 70)
            } else if account.isMounted {
                Button("Desmontar") { Task { await RcloneService.shared.unmount(account: account) } }
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button("Montar") { Task { await RcloneService.shared.mount(account: account) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .frame(width: 80)
    }

    var cardBackground: some ShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.accentColor.opacity(0.06))
            : AnyShapeStyle(Color(NSColor.controlBackgroundColor))
    }

    var borderColor: Color {
        if case .error = account.status { return .red.opacity(0.4) }
        if account.isMounted { return .green.opacity(0.3) }
        if isSelected { return .accentColor.opacity(0.4) }
        return Color(NSColor.separatorColor)
    }
}

// MARK: - AccountDetailsSheet
struct AccountDetailsSheet: View {
    @ObservedObject var account: Account
    @Binding var isPresented: Bool
    @State private var isLoadingSpace = false
    @State private var isClearing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(account.label).font(.title2.bold())
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Info
                    infoSection

                    // Space info
                    if account.isMounted {
                        spaceSection
                    }

                    // Actions
                    actionsSection
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cerrar") { isPresented = false }.buttonStyle(.bordered)
            }
            .padding(16)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            if account.isMounted && account.cloudFree == nil {
                loadSpaceInfo()
            }
        }
    }

    var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Información", systemImage: "info.circle").font(.headline)

            if !account.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nota").font(.caption).foregroundStyle(.secondary)
                    Text(account.notes).font(.body)
                }
                .padding(12).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Remote").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(account.remoteName).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: account.provider.icon).foregroundStyle(account.provider.color)
                }
            }
            .padding(12).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Carpeta de montaje").font(.caption).foregroundStyle(.secondary)
                Text(account.resolvedMountPath).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(12).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
        }
    }

    var spaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Espacio", systemImage: "externaldrive.fill").font(.headline)
                Spacer()
                if isLoadingSpace {
                    ProgressView().scaleEffect(0.8)
                }
            }

            if let free = account.cloudFree, let total = account.cloudTotal {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("En la nube").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(DriveInfo.format(free) + " libres").font(.body).bold().foregroundStyle(.blue)
                    }
                    HStack {
                        Text("Total").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(DriveInfo.format(total)).font(.caption).foregroundStyle(.secondary)
                    }
                    // Cloud space bar
                    if total > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                                let usedPercent = Double(total - free) / Double(total)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(usedPercent > 0.9 ? Color.red : usedPercent > 0.75 ? Color.orange : Color.blue)
                                    .frame(width: geo.size.width * usedPercent)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(12).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
            }

            if let localSize = account.localSize {
                HStack {
                    Text("En local (caché)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(DriveInfo.format(localSize)).font(.body.bold())
                }
                .padding(12).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
            }

            if isLoadingSpace && account.cloudFree == nil {
                Text("Calculando espacio...").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(12)
            }
        }
    }

    var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Acciones", systemImage: "slider.horizontal.3").font(.headline)

            if account.isMounted && (account.localSize ?? 0) > 0 {
                Button(role: .destructive) {
                    isClearing = true
                    Task {
                        await RcloneService.shared.clearWebDAVCache(account: account)
                        await MainActor.run {
                            account.localSize = nil
                            isClearing = false
                            loadSpaceInfo()
                        }
                    }
                } label: {
                    if isClearing {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Limpiando cache...")
                        }
                    } else {
                        Label("Limpiar caché local", systemImage: "trash.fill")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(isClearing)
            }

            Button {
                AccountStore.shared.remove(account: account)
                isPresented = false
            } label: {
                Label("Eliminar cuenta", systemImage: "xmark.circle.fill")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func loadSpaceInfo() {
        isLoadingSpace = true
        Task {
            let cloudAbout = await RcloneService.shared.getCloudAbout(remoteName: account.remoteName)
            let localSize = RcloneService.shared.getLocalFolderSize(path: account.resolvedMountPath)

            await MainActor.run {
                if let about = cloudAbout {
                    account.cloudFree = about.free
                    account.cloudTotal = about.total
                }
                account.localSize = localSize
                isLoadingSpace = false
            }
        }
    }
}

// MARK: - AddAccountSheet
struct AddAccountSheet: View {
    @EnvironmentObject var store: AccountStore
    @Binding var isPresented: Bool

    enum Mode { case new, existing }
    enum Step { case provider, credentials, mountOptions, connecting }

    @State private var mode: Mode = .new
    @State private var step: Step = .provider
    @State private var selectedProvider: CloudProvider = .onedrive
    @State private var remoteName = ""
    @State private var label = ""
    @State private var notes = ""
    @State private var mountPath = ""
    @State private var autoMount = false
    @State private var useCustomPath = false
    @State private var connectError = ""
    @State private var isConnecting = false

    // Credentials
    @State private var sftpHost = ""
    @State private var sftpPort = "22"
    @State private var sftpUser = ""
    @State private var sftpPassword = ""
    @State private var s3AccessKey = ""
    @State private var s3SecretKey = ""
    @State private var s3Region = "us-east-1"
    @State private var s3Endpoint = ""
    @State private var b2AccountId = ""
    @State private var b2AppKey = ""
    @State private var megaEmail = ""
    @State private var megaPassword = ""
    @State private var genericType = ""

    // Existing remote mode
    @State private var selectedRemote: AccountStore.RemoteInfo? = nil
    @State private var existingLabel = ""
    @State private var existingNotes = ""
    @State private var existingMountPath = ""
    @State private var existingAutoMount = false
    @State private var existingCustomPath = false

    let oauthProviders: [CloudProvider] = [.onedrive, .googledrive, .dropbox, .box]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $mode) {
                Text("Nueva conexión").tag(Mode.new)
                Text("Remote existente").tag(Mode.existing)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()

            if mode == .new {
                newConnectionContent
            } else {
                existingRemoteContent
            }
        }
        .frame(width: 580, height: 680)
        .animation(.easeInOut(duration: 0.2), value: mode)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    var header: some View {
        HStack {
            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.blue)
            Text("Agregar cuenta").font(.title2.bold())
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
    }

    @ViewBuilder
    var newConnectionContent: some View {
        switch step {
        case .provider:
            providerPickerView
        case .credentials:
            credentialsView
        case .mountOptions:
            mountOptionsView
        case .connecting:
            connectingView
        }
    }

    var providerPickerView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("¿Qué tipo de cuenta querés agregar?").font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 12) {
                        ForEach(CloudProvider.allCases, id: \.self) { provider in
                            ProviderButton(provider: provider, isSelected: selectedProvider == provider) {
                                selectedProvider = provider
                            }
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancelar") { isPresented = false }.buttonStyle(.bordered)
                Button("Siguiente") {
                    if remoteName.isEmpty { remoteName = defaultRemoteName(for: selectedProvider) }
                    step = .credentials
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(16)
        }
    }

    var credentialsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(selectedProvider.color.opacity(0.12)).frame(width: 40, height: 40)
                            Image(systemName: selectedProvider.icon).foregroundStyle(selectedProvider.color).font(.system(size: 18))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedProvider.displayName).font(.headline)
                            Text(oauthProviders.contains(selectedProvider) ? "Autenticación via web" : "Credenciales")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nombre del remote").font(.caption).foregroundStyle(.secondary)
                        TextField("ej: mi-onedrive", text: $remoteName).textFieldStyle(.roundedBorder)
                        Text("Identificador único en rclone (sin espacios).").font(.caption2).foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nombre visible").font(.caption).foregroundStyle(.secondary)
                        TextField("ej: Trabajo, Personal...", text: $label).textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nota (opcional)").font(.caption).foregroundStyle(.secondary)
                        TextField("Descripción, ubicación, etc...", text: $notes).textFieldStyle(.roundedBorder)
                    }

                    if !oauthProviders.contains(selectedProvider) {
                        Divider()
                        credentialFields
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "safari.fill").foregroundStyle(.blue)
                            Text("Se abrirá el navegador para autorizar. Seguí los pasos y volvé a la app.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12).background(Color.blue.opacity(0.05)).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.2)))
                    }

                    if !connectError.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            Text(connectError).font(.caption).foregroundStyle(.red)
                        }
                        .padding(10).background(Color.red.opacity(0.05)).cornerRadius(8)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("Atrás") { step = .provider; connectError = "" }.buttonStyle(.bordered)
                Spacer()
                Button("Cancelar") { isPresented = false }.buttonStyle(.bordered)
                Button(oauthProviders.contains(selectedProvider) ? "Conectar con navegador" : "Continuar") {
                    connectError = ""
                    if oauthProviders.contains(selectedProvider) {
                        step = .connecting
                        Task { await performOAuth() }
                    } else {
                        Task { await performCredentialSetup() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(remoteName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    var credentialFields: some View {
        switch selectedProvider {
        case .sftp:
            sftpFields
        case .s3:
            s3Fields
        case .backblaze:
            b2Fields
        case .mega:
            megaFields
        case .generic:
            genericFields
        default:
            EmptyView()
        }
    }

    var sftpFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuración SFTP").font(.subheadline.bold())
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host").font(.caption).foregroundStyle(.secondary)
                    TextField("servidor.ejemplo.com", text: $sftpHost).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Puerto").font(.caption).foregroundStyle(.secondary)
                    TextField("22", text: $sftpPort).textFieldStyle(.roundedBorder).frame(width: 70)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Usuario").font(.caption).foregroundStyle(.secondary)
                TextField("usuario", text: $sftpUser).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Contraseña (opcional)").font(.caption).foregroundStyle(.secondary)
                SecureField("••••••••", text: $sftpPassword).textFieldStyle(.roundedBorder)
            }
        }
    }

    var s3Fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuración Amazon S3").font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("Access Key ID").font(.caption).foregroundStyle(.secondary)
                TextField("AKIAIOSFODNN7EXAMPLE", text: $s3AccessKey).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Secret Access Key").font(.caption).foregroundStyle(.secondary)
                SecureField("••••••••", text: $s3SecretKey).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Región").font(.caption).foregroundStyle(.secondary)
                    TextField("us-east-1", text: $s3Region).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Endpoint (S3-compatible)").font(.caption).foregroundStyle(.secondary)
                    TextField("Dejar vacío para AWS", text: $s3Endpoint).textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    var b2Fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuración Backblaze B2").font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("Account ID").font(.caption).foregroundStyle(.secondary)
                TextField("ID de cuenta", text: $b2AccountId).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Application Key").font(.caption).foregroundStyle(.secondary)
                SecureField("••••••••", text: $b2AppKey).textFieldStyle(.roundedBorder)
            }
        }
    }

    var megaFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuración MEGA").font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("Email").font(.caption).foregroundStyle(.secondary)
                TextField("usuario@ejemplo.com", text: $megaEmail).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Contraseña").font(.caption).foregroundStyle(.secondary)
                SecureField("••••••••", text: $megaPassword).textFieldStyle(.roundedBorder)
            }
        }
    }

    var genericFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remote personalizado").font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("Tipo rclone").font(.caption).foregroundStyle(.secondary)
                TextField("ej: ftp, webdav, azureblob...", text: $genericType).textFieldStyle(.roundedBorder)
                Text("Ver rclone.org/docs para tipos disponibles.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    var mountOptionsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Opciones de montaje").font(.headline)
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Usar carpeta personalizada", isOn: $useCustomPath).toggleStyle(.switch)
                        if useCustomPath {
                            HStack {
                                TextField("~/CloudMounts/\(remoteName)", text: $mountPath).textFieldStyle(.roundedBorder)
                                Button("Elegir...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.canCreateDirectories = true
                                    if panel.runModal() == .OK, let url = panel.url {
                                        mountPath = url.path
                                    }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        } else {
                            Text("~/CloudMounts/\(remoteName)").font(.caption).foregroundStyle(.secondary).monospaced()
                        }
                        Toggle("Montar automáticamente al iniciar", isOn: $autoMount).toggleStyle(.switch)
                    }
                    .padding(16).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("Atrás") { step = .credentials }.buttonStyle(.bordered)
                Spacer()
                Button("Cancelar") { isPresented = false }.buttonStyle(.bordered)
                Button("Agregar cuenta") { finalizeNewAccount() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(16)
        }
    }

    var connectingView: some View {
        VStack(spacing: 24) {
            Spacer()
            if isConnecting {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text("Autenticando con \(selectedProvider.displayName)...").font(.headline)
                    Text("Se abrió el navegador. Completá la autorización y volvé a la app.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
                }
            } else if !connectError.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.red)
                    Text("Error al conectar").font(.headline)
                    Text(connectError).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                    Button("Reintentar") {
                        connectError = ""
                        step = .connecting
                        Task { await performOAuth() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Atrás") { step = .credentials; connectError = "" }.buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity).padding(32)
    }

    var existingRemoteContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.isLoadingRemotes {
                        HStack {
                            ProgressView()
                            Text("Cargando remotes...").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .center).padding()
                    } else if store.availableRemotes.isEmpty {
                        existingNoRemotesView
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(store.availableRemotes) { remote in
                                RemoteRow(
                                    remote: remote,
                                    isSelected: selectedRemote?.name == remote.name,
                                    onSelect: {
                                        guard !remote.isAlreadyAdded else { return }
                                        selectedRemote = remote
                                        if existingLabel.isEmpty { existingLabel = remote.name }
                                    }
                                )
                            }
                        }
                        .padding(4).background(Color(NSColor.controlBackgroundColor)).cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor)))

                        if selectedRemote != nil {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Configuración", systemImage: "slider.horizontal.3").font(.headline)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Nombre visible").font(.caption).foregroundStyle(.secondary)
                                    TextField("ej: Trabajo, Personal...", text: $existingLabel).textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Nota (opcional)").font(.caption).foregroundStyle(.secondary)
                                    TextField("Descripción...", text: $existingNotes).textFieldStyle(.roundedBorder)
                                }
                                Toggle("Carpeta personalizada", isOn: $existingCustomPath).toggleStyle(.switch)
                                if existingCustomPath {
                                    HStack {
                                        TextField("~/CloudMounts/\(selectedRemote?.name ?? "")", text: $existingMountPath).textFieldStyle(.roundedBorder)
                                        Button("Elegir...") {
                                            let panel = NSOpenPanel()
                                            panel.canChooseFiles = false
                                            panel.canChooseDirectories = true
                                            panel.canCreateDirectories = true
                                            if panel.runModal() == .OK, let url = panel.url {
                                                existingMountPath = url.path
                                            }
                                        }
                                        .buttonStyle(.bordered).controlSize(.small)
                                    }
                                }
                                Toggle("Montar automáticamente al iniciar", isOn: $existingAutoMount).toggleStyle(.switch)
                            }
                            .padding(16).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button { Task { await store.loadRemotes() } } label: {
                    Label("Recargar", systemImage: "arrow.clockwise")
                }.buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button("Cancelar") { isPresented = false }.buttonStyle(.bordered)
                Button("Agregar cuenta") { addExistingAccount() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedRemote == nil || existingLabel.isEmpty)
                    .keyboardShortcut(.return)
            }
            .padding(16)
        }
    }

    var existingNoRemotesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.slash").font(.largeTitle).foregroundStyle(.tertiary)
            Text("Sin remotes configurados").font(.headline).foregroundStyle(.secondary)
            Text("Agregá una cuenta nueva con el asistente o usá rclone config en Terminal.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(32).background(Color(NSColor.controlBackgroundColor)).cornerRadius(12)
    }

    // MARK: - Helpers

    func defaultRemoteName(for provider: CloudProvider) -> String {
        let base: String
        switch provider {
        case .onedrive:    base = "onedrive"
        case .googledrive: base = "gdrive"
        case .dropbox:     base = "dropbox"
        case .box:         base = "box"
        case .mega:        base = "mega"
        case .s3:          base = "s3"
        case .sftp:        base = "sftp"
        case .backblaze:   base = "b2"
        case .azureblob:   base = "azure"
        case .generic:     base = "remote"
        }
        let existing = store.availableRemotes.map { $0.name }
        if !existing.contains(base) { return base }
        for i in 2...99 {
            let candidate = "\(base)-\(i)"
            if !existing.contains(candidate) { return candidate }
        }
        return base
    }

    func rcloneType(for provider: CloudProvider) -> String {
        switch provider {
        case .onedrive:    return "onedrive"
        case .googledrive: return "drive"
        case .dropbox:     return "dropbox"
        case .box:         return "box"
        case .mega:        return "mega"
        case .s3:          return "s3"
        case .sftp:        return "sftp"
        case .backblaze:   return "b2"
        case .azureblob:   return "azureblob"
        case .generic:     return genericType
        }
    }

    func performOAuth() async {
        isConnecting = true
        let name = remoteName.trimmingCharacters(in: .whitespaces)
        let type = rcloneType(for: selectedProvider)

        // createRemote for OneDrive handles the full interactive flow:
        // OAuth in browser + drive type + drive ID selection.
        // For other OAuth providers (Google Drive, Dropbox, Box) createRemote
        // only creates the config entry; reconnectRemote then opens the browser.
        let createResult = await RcloneService.shared.createRemote(name: name, type: type)
        if !createResult.ok {
            await MainActor.run {
                connectError = "Error creando remote: \(createResult.error)"
                isConnecting = false
            }
            return
        }

        var authOk    = true
        var authError = ""

        if selectedProvider != .onedrive {
            // Non-OneDrive OAuth providers need a separate reconnect step
            let authResult = await RcloneService.shared.reconnectRemote(name: name)
            authOk    = authResult.ok
            authError = authResult.error
            if !authOk {
                await RcloneService.shared.deleteRemote(name: name)
            }
        }

        await MainActor.run {
            isConnecting = false
            if authOk {
                if label.isEmpty { label = name }
                step = .mountOptions
            } else {
                connectError = authError.isEmpty ? "Error de autenticación" : authError
            }
        }
    }

    func performCredentialSetup() async {
        let name = remoteName.trimmingCharacters(in: .whitespaces)
        let type = rcloneType(for: selectedProvider)
        var extras: [String] = []

        switch selectedProvider {
        case .sftp:
            extras = ["host=\(sftpHost)", "port=\(sftpPort)", "user=\(sftpUser)"]
            if !sftpPassword.isEmpty {
                let obscured = await RcloneService.shared.obscurePassword(sftpPassword)
                extras.append("pass=\(obscured)")
            }
        case .s3:
            extras = ["provider=AWS", "access_key_id=\(s3AccessKey)", "secret_access_key=\(s3SecretKey)", "region=\(s3Region)"]
            if !s3Endpoint.isEmpty { extras.append("endpoint=\(s3Endpoint)") }
        case .backblaze:
            extras = ["account=\(b2AccountId)", "key=\(b2AppKey)"]
        case .mega:
            extras = ["user=\(megaEmail)"]
            if !megaPassword.isEmpty {
                let obscured = await RcloneService.shared.obscurePassword(megaPassword)
                extras.append("pass=\(obscured)")
            }
        default:
            break
        }

        let result = await RcloneService.shared.createRemote(name: name, type: type, extras: extras)
        await MainActor.run {
            if result.ok {
                if label.isEmpty { label = name }
                step = .mountOptions
            } else {
                connectError = result.error
            }
        }
    }

    func finalizeNewAccount() {
        let name = remoteName.trimmingCharacters(in: .whitespaces)
        let account = Account(
            remoteName: name,
            label: label.isEmpty ? name : label,
            provider: selectedProvider,
            autoMount: autoMount,
            mountPath: useCustomPath ? mountPath : "",
            notes: notes
        )
        store.add(account: account)
        if autoMount {
            Task { await RcloneService.shared.updateLaunchAgent(accounts: store.accounts) }
        }
        Task { await store.loadRemotes() }
        isPresented = false
    }

    func addExistingAccount() {
        guard let remote = selectedRemote else { return }
        let account = Account(
            remoteName: remote.name,
            label: existingLabel.isEmpty ? remote.name : existingLabel,
            provider: remote.provider,
            autoMount: existingAutoMount,
            mountPath: existingCustomPath ? existingMountPath : "",
            notes: existingNotes
        )
        store.add(account: account)
        if existingAutoMount {
            Task { await RcloneService.shared.updateLaunchAgent(accounts: store.accounts) }
        }
        isPresented = false
    }
}

// MARK: - ProviderButton
struct ProviderButton: View {
    let provider: CloudProvider
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(provider.color.opacity(isSelected ? 0.2 : 0.08))
                        .frame(width: 52, height: 52)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(provider.color, lineWidth: 2)
                            .frame(width: 52, height: 52)
                    }
                    Image(systemName: provider.icon)
                        .foregroundStyle(provider.color)
                        .font(.system(size: 22))
                }
                Text(provider.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? provider.color : Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 90, height: 88)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? provider.color.opacity(0.05) : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - RemoteRow
struct RemoteRow: View {
    let remote: AccountStore.RemoteInfo
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(remote.provider.color.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: remote.provider.icon)
                        .foregroundStyle(remote.provider.color)
                        .font(.system(size: 15))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(remote.name).font(.system(size: 13, weight: .medium))
                    Text(remote.provider.displayName + (remote.type.isEmpty ? "" : " · \(remote.type)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if remote.isAlreadyAdded {
                    Text("Ya agregado").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12)).clipShape(Capsule())
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) :
                isHovered  ? Color(NSColor.selectedContentBackgroundColor).opacity(0.06) : .clear
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(remote.isAlreadyAdded)
        .opacity(remote.isAlreadyAdded ? 0.5 : 1)
        .onHover { isHovered = $0 }
    }
}

// MARK: - MenuBarIcon
struct MenuBarIcon: View {
    @EnvironmentObject var store: AccountStore

    var body: some View {
        Image(systemName: store.mountedCount > 0 ? "cloud.fill" : "cloud")
            .symbolRenderingMode(.multicolor)
    }
}

// MARK: - MenuBarView
struct MenuBarView: View {
    @EnvironmentObject var store: AccountStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "cloud.fill").foregroundStyle(.blue)
                Text("CloudMounter").font(.headline)
                Spacer()
                Text("\(store.mountedCount)/\(store.accounts.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider()

            if store.accounts.isEmpty {
                Text("Sin cuentas configuradas")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.accounts) { MenuBarAccountRow(account: $0) }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 300)
            }

            Divider()

            VStack(spacing: 4) {
                MenuBarButton(title: "Montar todo", icon: "arrow.up.circle.fill") {
                    for acc in store.accounts where !acc.isMounted {
                        Task { await RcloneService.shared.mount(account: acc) }
                    }
                }
                MenuBarButton(title: "Desmontar todo", icon: "arrow.down.circle") {
                    for acc in store.accounts where acc.isMounted {
                        Task { await RcloneService.shared.unmount(account: acc) }
                    }
                }
                Divider().padding(.horizontal, 8)
                MenuBarButton(title: "Abrir CloudMounter", icon: "macwindow") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
                MenuBarButton(title: "Salir", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        .frame(width: 280)
    }
}

// MARK: - MenuBarAccountRow
struct MenuBarAccountRow: View {
    @ObservedObject var account: Account

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(account.provider.color.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: account.provider.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(account.provider.color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(account.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(account.status.label).font(.system(size: 10)).foregroundStyle(account.status.color)
            }
            Spacer()
            if account.status.isBusy {
                ProgressView().scaleEffect(0.6).frame(width: 20)
            } else if account.isMounted {
                HStack(spacing: 4) {
                    Button { RcloneService.shared.openInFinder(account: account) } label: {
                        Image(systemName: "folder.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.borderless).help("Abrir en Finder")

                    Button { Task { await RcloneService.shared.unmount(account: account) } } label: {
                        Image(systemName: "eject.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.borderless).help("Desmontar")
                }
            } else {
                Button { Task { await RcloneService.shared.mount(account: account) } } label: {
                    Image(systemName: "play.fill").font(.system(size: 11))
                }
                .buttonStyle(.borderless).help("Montar")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - MenuBarButton
struct MenuBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - LogView
struct LogView: View {
    @EnvironmentObject var store: AccountStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log de actividad").font(.title2.bold())
                Spacer()
                Button { store.clearLog() } label: {
                    Label("Limpiar", systemImage: "trash")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(.ultraThinMaterial)

            Divider()

            if store.globalLog.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "terminal").font(.largeTitle).foregroundStyle(.quaternary)
                    Text("Sin actividad registrada").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.globalLog) { entry in
                            LogRow(entry: entry)
                            Divider().padding(.leading, 52)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }
}

// MARK: - LogRow
struct LogRow: View {
    let entry: LogEntry

    var icon: String {
        switch entry.level {
        case .info:    return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch entry.level {
        case .info:    return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(iconColor).frame(width: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message).font(.system(size: 12)).textSelection(.enabled)
                Text(entry.timeString)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

// MARK: - SettingsView
struct SettingsView: View {
    @EnvironmentObject var store: AccountStore
    @AppStorage("refreshInterval") var refreshInterval: Double = 15
    @AppStorage("showInDock") var showInDock: Bool = true
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ajustes").font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    SettingsSection(title: "General", icon: "gearshape") {
                        SettingsRow(title: "Mostrar en el Dock",
                                    subtitle: "Además del ícono en la barra de menú") {
                            Toggle("", isOn: $showInDock)
                                .toggleStyle(.switch)
                                .onChange(of: showInDock) { val in
                                    NSApp.setActivationPolicy(val ? .regular : .accessory)
                                }
                        }
                        SettingsRow(title: "Actualizar estado cada",
                                    subtitle: "Frecuencia de verificación de montajes") {
                            Picker("", selection: $refreshInterval) {
                                Text("10s").tag(10.0)
                                Text("15s").tag(15.0)
                                Text("30s").tag(30.0)
                                Text("60s").tag(60.0)
                            }
                            .pickerStyle(.menu).frame(width: 80)
                        }
                    }

                    SettingsSection(title: "Notificaciones", icon: "bell") {
                        SettingsRow(title: "Notificaciones del sistema",
                                    subtitle: "Al montar/desmontar cuentas") {
                            Toggle("", isOn: $notificationsEnabled).toggleStyle(.switch)
                        }
                    }

                    SettingsSection(title: "Dependencias", icon: "wrench.and.screwdriver") {
                        DependenciesCheck()
                    }

                    SettingsSection(title: "Cuentas (\(store.accounts.count))", icon: "person.2") {
                        if store.accounts.isEmpty {
                            Text("Sin cuentas configuradas")
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        } else {
                            ForEach(store.accounts) { account in
                                HStack {
                                    Image(systemName: account.provider.icon)
                                        .foregroundStyle(account.provider.color)
                                    Text(account.label)
                                    Spacer()
                                    Text(account.remoteName + ":")
                                        .font(.caption).foregroundStyle(.secondary).monospaced()
                                    Button(role: .destructive) {
                                        store.remove(account: account)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless).foregroundStyle(.red)
                                }
                                .padding(.vertical, 4)
                                if account.id != store.accounts.last?.id { Divider() }
                            }
                        }
                    }

                    SettingsSection(title: "Acerca de", icon: "info.circle") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CloudMounter").font(.headline)
                                Text("Versión 1.0  •  Powered by rclone")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(24)
            }
        }
    }
}

// MARK: - DependenciesCheck
struct DependenciesCheck: View {
    @State private var deps: (rclone: Bool, rcloneOfficialOk: Bool, fuse: Bool, webdav: Bool, rclonePath: String)
        = (false, false, false, false, "")
    @State private var checked = false

    var mountMethod: String {
        if deps.fuse { return "FUSE (nativo)" }
        if deps.webdav { return "WebDAV (sin FUSE)" }
        return "—"
    }

    var body: some View {
        VStack(spacing: 10) {
            DepRow(
                name: "rclone",
                ok: deps.rclone && deps.rcloneOfficialOk,
                detail: deps.rclone
                    ? (deps.rcloneOfficialOk ? deps.rclonePath : "⚠︎ versión Homebrew (no soporta mount)")
                    : "No instalado",
                installCmd: "# Descargar el binario oficial desde rclone.org/downloads\ncurl -O https://downloads.rclone.org/rclone-current-osx-arm64.zip"
            )
            DepRow(
                name: "Método de montaje",
                ok: deps.fuse || deps.webdav,
                detail: mountMethod,
                installCmd: "brew install --cask fuse-t"
            )
            if !deps.fuse && deps.webdav {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.blue).font(.caption)
                    Text("Sin FUSE disponible, se usa WebDAV. Funciona correctamente pero el volumen no aparece como disco en Finder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
        .onAppear {
            guard !checked else { return }
            checked = true
            Task {
                let d = RcloneService.shared.checkDependencies()
                await MainActor.run { deps = d }
            }
        }
    }
}

// MARK: - DepRow
struct DepRow: View {
    let name: String
    let ok: Bool
    let detail: String
    let installCmd: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).monospaced()
            }
            Spacer()
            if !ok {
                Button(copied ? "Copiado ✓" : "Copiar comando") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(installCmd, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - SettingsSection
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            VStack(spacing: 8) { content }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))
        }
    }
}

// MARK: - SettingsRow
struct SettingsRow<Control: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }
}

// MARK: - ReconfigureAccountSheet
/// Quick re-auth sheet: jumps straight to login for a specific provider
struct ReconfigureAccountSheet: View {
    let provider: CloudProvider
    let remoteName: String
    @Binding var isPresented: Bool
    @EnvironmentObject var store: AccountStore

    @State private var label = ""
    @State private var notes = ""
    @State private var mountPath = ""
    @State private var autoMount = false
    @State private var useCustomPath = false
    @State private var connectError = ""
    @State private var isConnecting = false

    let oauthProviders: [CloudProvider] = [.onedrive, .googledrive, .dropbox, .box]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "arrow.clockwise").font(.title3).foregroundStyle(.blue)
                Text("Reconfigurar \(provider.displayName)").font(.title2.bold())
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            Divider()

            if isConnecting {
                VStack(spacing: 24) {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Autenticando...").font(.headline)
                        Text("Se abrió el navegador. Completá la autorización y volvé a la app.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity).padding(32)
            } else if !connectError.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.red)
                    Text("Error al conectar").font(.headline)
                    Text(connectError).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                    Button("Reintentar") {
                        connectError = ""
                        isConnecting = true
                        Task { await performOAuth() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancelar") { isPresented = false }.buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity).padding(32)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Se abrirá el navegador para autorizar \(provider.displayName) nuevamente.").font(.subheadline).foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nombre visible").font(.caption).foregroundStyle(.secondary)
                            TextField("ej: Trabajo, Personal...", text: $label).textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nota (opcional)").font(.caption).foregroundStyle(.secondary)
                            TextField("Descripción, ubicación, etc...", text: $notes).textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(24)
                }

                Divider()
                HStack {
                    Spacer()
                    Button("Cancelar") { isPresented = false }.buttonStyle(.bordered)
                    Button("Conectar con navegador") {
                        connectError = ""
                        isConnecting = true
                        Task { await performOAuth() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
        }
        .frame(width: 500, height: 480)
    }

    func performOAuth() async {
        let type = rcloneType(for: provider)

        let createResult = await RcloneService.shared.createRemote(name: remoteName, type: type)
        if !createResult.ok {
            await MainActor.run {
                connectError = "Error creando remote: \(createResult.error)"
                isConnecting = false
            }
            return
        }

        var authOk = true
        var authError = ""

        if provider != .onedrive {
            let authResult = await RcloneService.shared.reconnectRemote(name: remoteName)
            authOk = authResult.ok
            authError = authResult.error
            if !authOk {
                await RcloneService.shared.deleteRemote(name: remoteName)
            }
        }

        await MainActor.run {
            isConnecting = false
            if authOk {
                // Create the account
                let account = Account(
                    remoteName: remoteName,
                    label: label.isEmpty ? remoteName : label,
                    provider: provider,
                    autoMount: autoMount,
                    mountPath: useCustomPath ? mountPath : "",
                    notes: notes
                )
                store.add(account: account)
                if autoMount {
                    Task { await RcloneService.shared.updateLaunchAgent(accounts: store.accounts) }
                }
                isPresented = false
            } else {
                connectError = authError.isEmpty ? "Error de autenticación" : authError
            }
        }
    }

    func rcloneType(for provider: CloudProvider) -> String {
        switch provider {
        case .onedrive:    return "onedrive"
        case .googledrive: return "drive"
        case .dropbox:     return "dropbox"
        case .box:         return "box"
        default:           return provider.rawValue
        }
    }
}
