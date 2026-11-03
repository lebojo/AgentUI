import SwiftUI
import Vision
import VisionKit

struct MobileQRScanner: UIViewControllerRepresentable {
    static var isSupported: Bool { DataScannerViewController.isSupported }

    let scanned: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.scanned = scanned
        guard !scanner.isScanning else { return }
        do { try scanner.startScanning() } catch { scanned(.failure(error)) }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(scanned: scanned) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private static let repeatDelay: Duration = .seconds(2)

        var scanned: (Result<String, Error>) -> Void
        private var lastPayload: (value: String, time: ContinuousClock.Instant)?

        init(scanned: @escaping (Result<String, Error>) -> Void) {
            self.scanned = scanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(updatedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            scanned(.failure(error))
        }

        private func report(_ items: [RecognizedItem]) {
            for case .barcode(let barcode) in items {
                guard let payload = barcode.payloadStringValue, isNew(payload) else { continue }
                lastPayload = (payload, .now)
                scanned(.success(payload))
                return
            }
        }

        private func isNew(_ payload: String) -> Bool {
            guard let lastPayload, lastPayload.value == payload else { return true }
            return ContinuousClock.now - lastPayload.time >= Self.repeatDelay
        }
    }
}
