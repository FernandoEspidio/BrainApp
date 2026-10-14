// Wi-Fi Aware transport (iOS 26+). Only compiled in the `SinNombreWiFiAware` target,
// which defines WIFI_AWARE_ENABLED, includes the entitlement and declares the service in Info.plist.
//
// ⚠️ DRAFT: based on Apple's official "Building peer-to-peer apps" sample. Not compiled or tested
// on devices: it needs Xcode 26, two iPhone 12 or later on iOS 26, and Apple approving the managed
// Wi-Fi Aware capability for your team. The main target does NOT depend on this file.

#if WIFI_AWARE_ENABLED && canImport(WiFiAware)
import Foundation
import Network
import SwiftUI
import WiFiAware
import DeviceDiscoveryUI

enum BrainShareService {
    /// Must match the `WiFiAwareServices` key in Info.plist EXACTLY.
    /// Rules: name ≤ 15 characters (a–z, 0–9, hyphen), "_" prefix and "._tcp" or "._udp" suffix.
    static let name = "_brain-share._tcp"
}

@available(iOS 26.0, *)
extension WAPublishableService {
    static var brainShare: WAPublishableService { allServices[BrainShareService.name]! }
}

@available(iOS 26.0, *)
extension WASubscribableService {
    static var brainShare: WASubscribableService { allServices[BrainShareService.name]! }
}

/// Card exchange over Wi-Fi Aware + Network framework.
/// - Pairing: required, once per pair of devices, with a 6-digit PIN (system UI).
/// - Transport: TCP with JSON coding (`WireMessage`), `.bulk` performance mode (recommended and more efficient).
@available(iOS 26.0, *)
@MainActor
final class WiFiAwareTransport: NearbyTransport {
    let kind: TransportKind = .wifiAware
    let requirementsNote = "Direct connection between nearby iPhones, no Internet. The first time, the two devices must be paired with a PIN."

    /// Publishes the service and waits for the first connection from a paired device.
    func host(sending card: ShareableBrainCard) async throws -> ShareableBrainCard {
        let (stream, continuation) = AsyncThrowingStream<ShareableBrainCard, Error>.makeStream()

        let listenerTask = Task {
            do {
                try await NetworkListener(
                    for: .wifiAware(.connecting(to: .brainShare, from: .allPairedDevices)),
                    using: .parameters {
                        Coder(receiving: WireMessage.self, sending: WireMessage.self, using: NetworkJSONCoder()) {
                            TCP()
                        }
                    }
                    .wifiAware { $0.performanceMode = .bulk }
                )
                .run { connection in
                    for try await (message, _) in connection.messages {
                        guard case .hello(let theirCard) = message else { continue }
                        try await connection.send(WireMessage.hello(card))
                        continuation.yield(theirCard)
                        continuation.finish()
                        return
                    }
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
        defer { listenerTask.cancel() }

        for try await received in stream {
            return received
        }
        throw NearbyError.connectionClosed
    }

    /// Finds a paired device publishing the service, connects and exchanges cards.
    func join(sending card: ShareableBrainCard) async throws -> ShareableBrainCard {
        let browser = NetworkBrowser(for: .wifiAware(.connecting(to: .allPairedDevices, from: .brainShare)))
        let endpoint = try await browser.run { endpoints in
            if let first = endpoints.first { return .finish(first) }
            return .continue
        }

        let connection = NetworkConnection(
            to: endpoint,
            using: .parameters {
                Coder(receiving: WireMessage.self, sending: WireMessage.self, using: NetworkJSONCoder()) {
                    TCP()
                }
            }
            .wifiAware { $0.performanceMode = .bulk }
        )

        try await connection.send(WireMessage.hello(card))
        for try await (message, _) in connection.messages {
            switch message {
            case .hello(let theirCard): return theirCard
            case .decline(let reason): throw NearbyError.declined(reason)
            }
        }
        throw NearbyError.connectionClosed
    }
}

/// Pairing with the system UI (DeviceDiscoveryUI). One side lets itself be found, the other picks.
@available(iOS 26.0, *)
struct WiFiAwarePairingRows: View {
    @State private var pairedCount = 0

    var body: some View {
        DevicePairingView(.wifiAware(.connecting(to: .brainShare, from: .userSpecifiedDevices))) {
            Label("Let a friend pair with me", systemImage: "person.badge.key")
        } fallback: {
            Label("Wi-Fi Aware isn't available on this device", systemImage: "xmark.circle")
        }

        DevicePicker(.wifiAware(.connecting(to: .userSpecifiedDevices, from: .brainShare))) { _ in
            // The system completes pairing; the device shows up in WAPairedDevice.allDevices.
        } label: {
            Label("Pair with a nearby friend", systemImage: "plus.circle")
        } fallback: {
            Label("Wi-Fi Aware isn't available on this device", systemImage: "xmark.circle")
        }

        Text(pairedCount == 0
             ? "No paired devices yet. Pairing happens once, with a PIN."
             : "\(countLabel(pairedCount, "paired device", "paired devices")).")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .task {
                do {
                    for try await devices in WAPairedDevice.allDevices {
                        pairedCount = devices.count
                    }
                } catch {
                    pairedCount = 0
                }
            }
    }
}
#endif
