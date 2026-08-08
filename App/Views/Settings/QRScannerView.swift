import AVFoundation
import ApexGaugeCore
import SwiftUI
import UIKit
import VisionKit

/// Camera surface used by provider onboarding. Only ApexGauge connect payloads
/// are delivered; unrelated QR codes are ignored so scanning can continue.
struct QRScannerView: UIViewControllerRepresentable {
    let onPayload: @MainActor (ConnectPayload) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator

        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable
        else {
            Task { @MainActor in
                onError("QR scanning is unavailable on this device. Use the paste fallback below.")
            }
            return scanner
        }

        do {
            try scanner.startScanning()
        } catch {
            Task { @MainActor in
                onError("The camera could not start: \(error.localizedDescription)")
            }
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onPayload: @MainActor (ConnectPayload) -> Void
        private var deliveredPayload = false

        init(onPayload: @escaping @MainActor (ConnectPayload) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !deliveredPayload else { return }

            for item in addedItems {
                guard case let .barcode(barcode) = item,
                      let value = barcode.payloadStringValue,
                      let payload = ConnectPayload.decode(value)
                else { continue }

                deliveredPayload = true
                dataScanner.stopScanning()
                onPayload(payload)
                return
            }
        }
    }
}

/// Shared primary onboarding section. Camera transfer is optical only; the
/// pasteboard remains an explicit fallback rather than the default path.
struct QRConnectSection: View {
    let providerName: String
    let command: String
    let clonedRepoCommand: String
    let onPayload: @MainActor (ConnectPayload) -> Void

    @Environment(\.openURL) private var openURL
    @State private var isPresentingScanner = false
    @State private var showCameraDeniedAlert = false
    @State private var scannerError: String?

    var body: some View {
        Section("Scan QR — recommended") {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(command)
                    .font(ApexTheme.Typography.mono)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .accessibilityLabel(command)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text("If you have the repo cloned: \(clonedRepoCommand)")
                    .font(ApexTheme.Typography.caption)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
                    .textSelection(.enabled)
            }

            Button {
                Task { await openScanner() }
            } label: {
                Label("Scan QR from your Mac", systemImage: "qrcode.viewfinder")
            }

            Text("The credential travels through the QR image only — not through iCloud or a network.")
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)

            if let scannerError {
                Text(scannerError)
                    .font(ApexTheme.Typography.caption)
                    .foregroundStyle(ApexTheme.Colors.danger)
            }
        }
        .apexListRow()
        .sheet(isPresented: $isPresentingScanner) {
            NavigationStack {
                QRScannerView(
                    onPayload: { payload in
                        isPresentingScanner = false
                        onPayload(payload)
                    },
                    onError: { message in
                        scannerError = message
                        isPresentingScanner = false
                    }
                )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan \(providerName) QR")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresentingScanner = false
                        }
                    }
                }
            }
            .tint(ApexTheme.Colors.accent)
        }
        .alert("Camera access required", isPresented: $showCameraDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access in Settings to scan the Apex Gauge connect QR code, or use the paste fallback.")
        }
    }

    @MainActor
    private func openScanner() async {
        scannerError = nil

        guard DataScannerViewController.isSupported else {
            scannerError = "QR scanning is not supported on this device. Use the paste fallback below."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isPresentingScanner = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                isPresentingScanner = true
            } else {
                showCameraDeniedAlert = true
            }
        case .denied, .restricted:
            showCameraDeniedAlert = true
        @unknown default:
            scannerError = "Camera access is unavailable. Use the paste fallback below."
        }
    }
}

struct CredentialSecurityNote: View {
    var body: some View {
        Label(
            "QR avoids the system pasteboard. Credentials stay in this device's Keychain — they are not synced or backed up.",
            systemImage: "lock.shield"
        )
        .font(ApexTheme.Typography.caption)
        .foregroundStyle(ApexTheme.Colors.inkSecondary)
    }
}
