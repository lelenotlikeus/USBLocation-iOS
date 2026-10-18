import CoreLocation
import Foundation

@MainActor final class PairingStore {
    var hasPairingFile = true
    var pairingPath = "/test-only/no-device.plist"
}

final class BackgroundKeepAlive {
    var lastKnownCoordinate: CLLocationCoordinate2D?
    func start() {}
    func stop() {}
}

enum LocationEngineError: LocalizedError {
    case service(String)
    var errorDescription: String? { switch self { case .service(let text): return text } }
}

@MainActor enum LocationEngine {
    static var sets: [GeoPoint] = []
    static var clears = 0
    static var hold = false
    static var fail = false
    static var pending: CheckedContinuation<Result<Void, LocationEngineError>, Never>?

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        sets.append(GeoPoint(latitude: latitude, longitude: longitude))
        if hold { return await withCheckedContinuation { pending = $0 } }
        return fail ? .failure(.service("Mock DVT failure")) : .success(())
    }
    static func clear(pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        clears += 1
        return .success(())
    }
    static func finishSet() { let value = pending; pending = nil; value?.resume(returning: .success(())) }
    static func reset() { finishSet(); sets = []; clears = 0; hold = false; fail = false }
}
