import SwiftUI

struct AboutView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Acerca de CloudMounter")
                    .font(.title2.bold())
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .center, spacing: 24) {
                    // App icon
                    VStack(spacing: 12) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.blue)
                        Text("CloudMounter")
                            .font(.title.bold())
                        Text("v1.0.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider().padding(.horizontal, 40)

                    // Description
                    VStack(alignment: .leading, spacing: 16) {
                        descriptionItem(
                            icon: "cloud.fill",
                            title: "¿Qué es CloudMounter?",
                            text: "Una aplicación nativa de macOS que te permite montar tus cuentas en la nube (OneDrive, Google Drive, Dropbox, etc.) como discos locales en Finder, de forma sencilla y sin entrar a la terminal."
                        )

                        descriptionItem(
                            icon: "gearshape.fill",
                            title: "Características",
                            text: "✓ Soporte para 10+ servicios en la nube\n✓ Autenticación OAuth desde la app\n✓ Vista de espacio disponible\n✓ Montaje automático\n✓ Control de caché local"
                        )

                        descriptionItem(
                            icon: "building.2.fill",
                            title: "Tecnología",
                            text: "Construido con SwiftUI y rclone. Funciona con FUSE (macFUSE/FUSE-T) o WebDAV como fallback, sin requerir sudo ni acceso root."
                        )

                        descriptionItem(
                            icon: "link.fill",
                            title: "Enlaces",
                            text: "rclone.org - Backend de sincronización\nmacfuse.io - FUSE para macOS\nswift.org - Lenguaje de programación"
                        )
                    }
                    .padding(.horizontal, 20)

                    Divider().padding(.horizontal, 40)

                    // Footer
                    VStack(spacing: 8) {
                        Text("Hecho con ❤️ para macOS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("© 2026 CloudMounter")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 24)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cerrar") { isPresented = false }
                    .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .frame(width: 520, height: 640)
    }

    func descriptionItem(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
