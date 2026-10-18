import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidCoordinates
    case invalidIP
    case service(String)

    var errorDescription: String? {
        switch self {
        case .invalidCoordinates: return "Coordinate non valide: latitudine −90…90, longitudine −180…180."
        case .invalidIP: return "IP del tunnel non valido. Quello predefinito di LocalDevVPN è 10.7.0.1."
        case .service(let message): return message
        }
    }
}

/// The upstream idevice FFI is blocking. All handles belong to this serial queue.
enum LocationEngine {
    private static let queue = DispatchQueue(label: "io.github.lelenotlikeus.usblocation.location", qos: .userInitiated)
    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        guard GeoPoint(latitude: latitude, longitude: longitude).isValid else { return .failure(.invalidCoordinates) }
        return await withCheckedContinuation { continuation in
            queue.async {
                let prepared = prepare(pairingPath: pairingPath, deviceIP: deviceIP)
                guard case .success = prepared, let simulation = locationSimulation else {
                    continuation.resume(returning: prepared)
                    return
                }
                if let error = location_simulation_set(simulation, latitude, longitude) {
                    let failure = describe(error, context: "Posizione non confermata dal servizio iOS")
                    cleanup()
                    continuation.resume(returning: .failure(failure))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }
    }

    static func clear(pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        await withCheckedContinuation { continuation in
            queue.async {
                let prepared = prepare(pairingPath: pairingPath, deviceIP: deviceIP)
                guard case .success = prepared, let simulation = locationSimulation else {
                    continuation.resume(returning: prepared)
                    return
                }
                let error = location_simulation_clear(simulation)
                cleanup()
                if let error {
                    continuation.resume(returning: .failure(describe(error, context: "Reset non confermato")))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }
    }

    private static func describe(_ error: UnsafeMutablePointer<IdeviceFfiError>, context: String) -> LocationEngineError {
        defer { idevice_error_free(error) }
        let detail = error.pointee.message.map { String(cString: $0) } ?? "codice \(error.pointee.code)"
        return .service("\(context): \(detail). Verifica pairing, LocalDevVPN, Modalità sviluppatore e DDI.")
    }

    private static func prepare(pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        if locationSimulation != nil { return .success(()) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return .failure(.invalidIP) }
        var pairing: OpaquePointer?
        if let error = pairingPath.withCString({ rp_pairing_file_read($0, &pairing) }) {
            return .failure(describe(error, context: "File RPPairing non leggibile"))
        }
        guard let pairing else { return .failure(.service("Importa un file RPPairing valido nelle impostazioni.")) }
        defer { rp_pairing_file_free(pairing) }
        let tunnelError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.stride),
                                       "USBLocation", pairing, nil, nil, &adapter, &handshake)
            }
        }
        if let tunnelError {
            let failure = describe(tunnelError, context: "Tunnel developer non disponibile")
            cleanup()
            return .failure(failure)
        }
        if let error = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            let failure = describe(error, context: "Handshake DVT fallito")
            cleanup()
            return .failure(failure)
        }
        if let error = location_simulation_new(remoteServer, &locationSimulation) {
            let failure = describe(error, context: "Servizio simulazione non disponibile")
            cleanup()
            return .failure(failure)
        }
        // The simulation borrows RemoteServerHandle: retain it until simulation_free.
        guard locationSimulation != nil else {
            cleanup()
            return .failure(.service("Il servizio non ha restituito un canale di simulazione."))
        }
        return .success(())
    }

    private static func cleanup() {
        if let locationSimulation { location_simulation_free(locationSimulation); self.locationSimulation = nil }
        if let remoteServer { remote_server_free(remoteServer); self.remoteServer = nil }
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
    }
}
