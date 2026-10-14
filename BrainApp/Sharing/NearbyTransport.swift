import Foundation

enum NearbyError: LocalizedError {
    case connectionClosed
    case incompatibleVersion
    case declined(String)

    var errorDescription: String? {
        switch self {
        case .connectionClosed: return "The connection closed before the companion was received."
        case .incompatibleVersion: return "The other device is using an incompatible version of the app."
        case .declined(let reason): return "The other device declined the exchange: \(reason)"
        }
    }
}

/// Nearby exchange transport with NO Internet. The app depends only on this protocol:
/// Wi-Fi Aware is one implementation; Multipeer Connectivity or a QR code could be others.
///
/// Contract: both sides send their card and receive the other's. The "host" publishes the service
/// and waits; the "joiner" browses already-paired devices and connects.
@MainActor
protocol NearbyTransport: AnyObject {
    var kind: TransportKind { get }
    /// Explains in plain language what is needed to use this transport.
    var requirementsNote: String { get }
    func host(sending card: ShareableBrainCard) async throws -> ShareableBrainCard
    func join(sending card: ShareableBrainCard) async throws -> ShareableBrainCard
}

@MainActor
enum NearbyTransportFactory {
    static func make(isDemo: Bool) -> [any NearbyTransport] {
        if isDemo { return [DemoNearbyTransport()] }
        var transports: [any NearbyTransport] = []
        #if WIFI_AWARE_ENABLED && canImport(WiFiAware)
        if #available(iOS 26.0, *) {
            transports.append(WiFiAwareTransport())
        }
        #endif
        return transports
    }

    static let unavailableExplanation = "Nearby sharing uses Wi-Fi Aware (iOS 26 or later, iPhone 12 or later, physical devices only) and needs a capability Apple grants on request. This build doesn't include it yet. You can try the flow in Demo mode or share your card as an image."
}
