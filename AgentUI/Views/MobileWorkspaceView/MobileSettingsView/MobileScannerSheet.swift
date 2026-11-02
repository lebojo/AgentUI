import AVFoundation
import SwiftUI
import VisionKit

struct MobileScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(MobileWorkspaceStore.self) private var store

    @State private var access = CameraAccess.pending
    @State private var error: String?

    private var hint: String {
        error ?? String(localized: "Point the camera at the QR code shown on the Mac in Settings → Local Access.")
    }

    var body: some View {
        NavigationStack {
            Group {
                switch access {
                case .pending: ProgressView()
                case .granted:
                    MobileQRScanner(scanned: pair)
                        .ignoresSafeArea(edges: .bottom)
                        .safeAreaInset(edge: .bottom) {
                            Text(hint)
                                .font(Typography.body)
                                .foregroundStyle(error == nil ? Palette.textPrimary : Palette.danger)
                                .multilineTextAlignment(.center)
                                .padding(Spacing.l)
                                .frame(maxWidth: .infinity)
                                .background(Palette.bar)
                        }
                case .denied:
                    ContentUnavailableView {
                        Label("Camera Access Needed", systemImage: "camera")
                    } description: {
                        Text("Allow AgentUI to use the camera in the Settings app, or enter the IP address and pairing code by hand.")
                    } actions: {
                        Button("Open Settings", action: openSettings).buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .task { access = await requestCameraAccess() }
    }

    private func requestCameraAccess() async -> CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined: guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default: return .denied
        }
        return DataScannerViewController.isAvailable ? .granted : .denied
    }

    private func pair(_ scan: Result<String, Error>) {
        do {
            try store.pair(with: PairingInvitation(scanned: scan.get()))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    enum CameraAccess { case pending, granted, denied }
}
