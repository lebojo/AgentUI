import SwiftUI
import AppKit

struct InstallationRow: View {
    @State private var installer: (any Installer)?
    @State private var status = InstallationStatus.notInstalled
    @State private var errorMessage: String?

    let title: String
    let load: @Sendable () async throws -> any Installer

    var body: some View {
        Group {
            LabeledContent {
                HStack {
                    if status.canUninstall {
                        Button("Désinstaller", role: .destructive) { perform { try $0.uninstall() } }
                    }
                    if status.canInstall {
                        Button(status.actionTitle) { perform { try $0.install() } }
                    }
                }
                .disabled(installer == nil)
            } label: {
                Text(title)
                Text(status.title)
            }
            if let errorMessage {
                Text(errorMessage).font(Typography.caption).foregroundStyle(Palette.danger)
            }
        }
        .task { await prepare() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func prepare() async {
        do {
            installer = try await load()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() {
        guard let installer else { return }
        status = installer.status
    }

    private func perform(_ action: (any Installer) throws -> Void) {
        guard let installer else { return }
        do {
            try action(installer)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        status = installer.status
    }
}
