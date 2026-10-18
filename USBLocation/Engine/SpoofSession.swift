import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .drive: return "Drive"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return "Non attiva"
        case .connecting: return "Starting…"
        case .active: return "Posizione inviata"
        case .reconnecting: return "Reconnecting…"
        case .dropped: return "Interrupted"
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex: Int = 0
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false
    @Published var speedKmh = 5.0
    @Published var entireRoute = true
    @Published var routeDistanceKm = 1.0
    @Published private(set) var routeActive = false
    @Published var routePaused = false
    @Published private(set) var routeMeters = 0.0
    @Published private(set) var routeTargetMeters = 0.0
    @Published var lastNotice: String?
    private var stateEpoch = 0
    private var movementID = UUID()
    private var joystickID = UUID()
    private var resetPending = false

    private var speed: Double {
        speedKmh.isFinite ? min(300, max(0.1, speedKmh)) / 3.6 : 5 / 3.6
    }

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []

    private var resendTimer: Timer?
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()

    private let favoritesKey = "usblocation.favorites"
    private let recentsKey = "usblocation.recents"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
    }

    var isSpoofing: Bool {
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard !isBusy else { return }
        stopMovement()
        Task { _ = await apply(coordinate, pairing: pairing, markRecent: true) }
    }

    func stopMovement() {
        movementID = UUID()
        routeTask?.cancel()
        routeTask = nil
        routeActive = false
        routePaused = false
        stopJoystick()
    }

    func stop(pairing: PairingStore) {
        guard !resetPending else { return }
        stateEpoch &+= 1
        resetPending = true
        stopMovement()
        stopResend()
        isBusy = true
        lastNotice = "Invio del reset in corso…"
        Task {
            let result = await LocationEngine.clear(pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP)
            resetPending = false
            isBusy = false
            switch result {
            case .success:
                simulated = nil
                status = .idle
                lastError = nil
                lastNotice = "Reset inviato. Verifica il ritorno alla posizione reale sul telefono."
                endBackground()
                locationKeeper.start()
            case .failure(let error):
                lastNotice = nil
                lastError = error.localizedDescription
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            }
        }
    }

    /// Last CoreLocation reading; it can itself be simulated while spoofing.
    var realCoordinate: CLLocationCoordinate2D? {
        locationKeeper.lastKnownCoordinate
    }

    /// Start lightweight GPS updates for the map puck / locate button.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard !isBusy else { return }
        guard pairing.hasPairingFile else { lastError = "Completa il pairing nelle impostazioni."; return }
        guard let start = simulated ?? pin ?? locationKeeper.lastKnownCoordinate else {
            lastError = "Seleziona e applica una posizione prima del joystick."
            return
        }
        stopMovement()
        let id = joystickID
        Task {
            guard joystickID == id else { return }
            if simulated == nil, !(await apply(start, pairing: pairing, markRecent: false)) { return }
            guard joystickID == id, !resetPending else { return }
            joystickActive = true
            joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.tickJoystick(pairing: pairing) }
            }
        }
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopJoystick() {
        joystickID = UUID()
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard !isBusy, pairing.hasPairingFile else { return }
        do {
            var motion = try RouteMotion(points: coordinates.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) },
                                         targetMeters: entireRoute ? nil : routeDistanceKm * 1000)
            stopMovement()
            routeMeters = 0
            routeTargetMeters = motion.targetMeters
            routeActive = true
            let id = movementID
            routeTask = Task { [weak self] in
                guard let self, self.movementID == id, !Task.isCancelled else { return }
                defer { if self.movementID == id { self.routeActive = false } }
                guard await self.apply(motion.position.coordinate, pairing: pairing, markRecent: true) else { return }
                while !Task.isCancelled, self.movementID == id, !motion.finished {
                    do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                    guard !Task.isCancelled, self.movementID == id else { return }
                    if self.routePaused || self.isBusy { continue }
                    do {
                        var next = motion
                        try next.advance(meters: self.speed * 0.25)
                        guard await self.apply(next.position.coordinate, pairing: pairing, markRecent: false) else { return }
                        guard self.movementID == id else { return }
                        motion = next
                        self.routeMeters = motion.traveled
                    } catch {
                        self.lastError = error.localizedDescription
                        return
                    }
                }
                if motion.finished { self.lastNotice = "Distanza raggiunta. La posizione resta simulata fino a Reset." }
            }
        } catch { lastError = error.localizedDescription }
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    @discardableResult
    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool) async -> Bool {
        guard !isBusy, !resetPending else { return false }
        guard pairing.hasPairingFile else { lastError = "Completa il pairing nelle impostazioni."; return false }
        guard CLLocationCoordinate2DIsValid(coordinate), coordinate.latitude.isFinite, coordinate.longitude.isFinite else {
            lastError = "Coordinate non valide."
            return false
        }
        if status == .idle || status.isDropped { status = .connecting }
        let epoch = stateEpoch
        isBusy = true
        let result = await LocationEngine.set(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                              pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP)
        // A reset owns the state once requested, even if this set finishes afterward.
        guard epoch == stateEpoch else { return false }
        isBusy = false
        switch result {
        case .success:
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            lastNotice = nil
            beginBackground()
            locationKeeper.start()
            startResend(pairing: pairing)
            if markRecent { pushRecent(coordinate) }
            return true
        case .failure(let error):
            stopMovement()
            stopResend()
            lastError = error.localizedDescription
            lastNotice = nil
            status = .dropped(error.localizedDescription)
            postDropNotification(error.localizedDescription)
            return false
        }
    }

    private func tickJoystick(pairing: PairingStore) async {
        guard joystickActive, !isBusy, let current = simulated else { return }
        let magnitude = hypot(joystickVector.dx, joystickVector.dy)
        guard magnitude > 0.08 else { return }
        do {
            let point = GeoPoint(latitude: current.latitude, longitude: current.longitude)
            let bearing = atan2(joystickVector.dx, -joystickVector.dy) * 180 / .pi
            let next = try GeoMotion.move(point, bearing: bearing, meters: speed * min(1, magnitude) * 0.25)
            await apply(next.coordinate, pairing: pairing, markRecent: false)
        } catch { lastError = error.localizedDescription; stopJoystick() }
    }

    private func startResend(pairing: PairingStore) {
        guard resendTimer == nil else { return }
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isBusy, let sim = self.simulated, self.isSpoofing else { return }
                await self.apply(sim, pairing: pairing, markRecent: false)
            }
        }
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }



    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "USBLocation spoof dropped"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

}

private extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
