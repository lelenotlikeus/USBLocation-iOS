import CoreLocation
import XCTest

@MainActor final class SessionTests: XCTestCase {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for controller state")
    }

    func testNoActiveStateBeforeBackendReplyAndNoRequestBacklog() async throws {
        LocationEngine.reset()
        let session = SpoofSession(), pairing = PairingStore()
        LocationEngine.hold = true
        session.teleport(to: .init(latitude: 41.9, longitude: 12.5), pairing: pairing)
        try await waitUntil { LocationEngine.pending != nil }
        XCTAssertFalse(session.isSpoofing)
        XCTAssertNil(session.simulated)
        for _ in 0..<20 { session.teleport(to: .init(latitude: 42, longitude: 13), pairing: pairing) }
        XCTAssertEqual(LocationEngine.sets.count, 1)
        LocationEngine.finishSet()
        try await waitUntil { session.isSpoofing }
        XCTAssertEqual(session.simulated?.latitude, 41.9)
        session.stop(pairing: pairing)
        try await waitUntil { !session.isBusy }
    }

    func testResetPreventsLateSetFromReactivatingSimulation() async throws {
        LocationEngine.reset()
        let session = SpoofSession(), pairing = PairingStore()
        LocationEngine.hold = true
        session.teleport(to: .init(latitude: 41.9, longitude: 12.5), pairing: pairing)
        try await waitUntil { LocationEngine.pending != nil }
        session.stop(pairing: pairing)
        try await waitUntil { LocationEngine.clears == 1 && !session.isBusy }
        LocationEngine.finishSet()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(session.status, .idle)
        XCTAssertNil(session.simulated)
        XCTAssertTrue(session.lastNotice?.contains("Reset inviato") == true)
    }

    func testFailedInitialRouteDoesNotAdvanceOrClaimActive() async throws {
        LocationEngine.reset()
        LocationEngine.fail = true
        let session = SpoofSession(), pairing = PairingStore()
        session.followRoute([.init(latitude: 41.9, longitude: 12.5), .init(latitude: 41.901, longitude: 12.5)], pairing: pairing)
        try await waitUntil { !session.routeActive }
        XCTAssertEqual(session.routeMeters, 0)
        XCTAssertFalse(session.isSpoofing)
        XCTAssertNil(session.simulated)
        XCTAssertNotNil(session.lastError)
    }

    func testCustomDistanceWaitsForAckAndStopsAtTarget() async throws {
        LocationEngine.reset()
        let session = SpoofSession(), pairing = PairingStore()
        session.speedKmh = 300
        session.entireRoute = false
        session.routeDistanceKm = 0.001
        LocationEngine.hold = true
        session.followRoute([.init(latitude: 41.9, longitude: 12.5), .init(latitude: 41.901, longitude: 12.5)], pairing: pairing)
        try await waitUntil { LocationEngine.pending != nil }
        XCTAssertEqual(session.routeMeters, 0)
        LocationEngine.hold = false
        LocationEngine.finishSet()
        try await waitUntil { !session.routeActive }
        XCTAssertEqual(session.routeMeters, 1, accuracy: 1e-7)
        XCTAssertTrue(session.isSpoofing)
        session.stop(pairing: pairing)
        try await waitUntil { !session.isBusy }
    }

    func testInvalidCoordinatesNeverReachBackend() async throws {
        LocationEngine.reset()
        let session = SpoofSession(), pairing = PairingStore()
        session.teleport(to: .init(latitude: .nan, longitude: 12), pairing: pairing)
        try await waitUntil { session.lastError != nil }
        XCTAssertTrue(LocationEngine.sets.isEmpty)
    }

    func testJoystickStopsAfterRelease() async throws {
        LocationEngine.reset()
        let session = SpoofSession(), pairing = PairingStore()
        session.pin = .init(latitude: 41.9, longitude: 12.5)
        session.startJoystick(pairing: pairing)
        try await waitUntil { session.joystickActive }
        session.updateJoystick(vector: .init(dx: 1, dy: 0))
        try await waitUntil { LocationEngine.sets.count >= 2 }
        session.updateJoystick(vector: .zero)
        session.stopJoystick()
        let count = LocationEngine.sets.count
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(LocationEngine.sets.count, count)
        session.stop(pairing: pairing)
        try await waitUntil { !session.isBusy }
    }

    func testGPXAttributeOrderNamespacesAndEscaping() throws {
        let xml = "<g:gpx xmlns:g='http://www.topografix.com/GPX/1/1'><g:trkpt lon='12.5' lat='41.9'/></g:gpx>"
        let points = try GPXCodec.parse(data: Data(xml.utf8))
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].longitude, 12.5)
        XCTAssertTrue(GPXCodec.export(points, name: "A&B <test>").contains("A&amp;B &lt;test&gt;"))
    }

    func testGPXRejectsEntitiesBadCoordinatesAndOversize() {
        let bad = ["<!DOCTYPE gpx [<!ENTITY x 'data'>]><gpx/>", "<gpx><trkpt lat='nan' lon='0'/></gpx>", "<gpx><trkpt lat='91' lon='0'/></gpx>"]
        for xml in bad { XCTAssertThrowsError(try GPXCodec.parse(data: Data(xml.utf8))) }
        XCTAssertThrowsError(try GPXCodec.parse(data: bad[0].data(using: .utf16)!))
        XCTAssertThrowsError(try GPXCodec.parse(data: Data(repeating: 0, count: 5 * 1024 * 1024 + 1)))
    }
}
