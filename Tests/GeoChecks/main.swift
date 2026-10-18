import Foundation

struct Fixture: Decodable {
    let point: GeoPoint
    let bearing: Double
    let meters: Double
    let expected: GeoPoint
}
let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
for fixture in fixtures {
    let result = try GeoMotion.move(fixture.point, bearing: fixture.bearing, meters: fixture.meters)
    precondition(abs(result.latitude - fixture.expected.latitude) < 1e-7, "WGS84 latitude mismatch")
    let lonError = abs(result.longitude - fixture.expected.longitude)
    precondition(min(lonError, abs(360 - lonError)) < 1e-6, "WGS84 longitude mismatch")
    if fixture.meters > 0 {
        let measured = try GeoMotion.leg(fixture.point, result).meters
        precondition(abs(measured - fixture.meters) < 0.002, "WGS84 distance mismatch")
    }
}
let start = GeoPoint(latitude: 41.9, longitude: 12.5)
let corner = try GeoMotion.move(start, bearing: 90, meters: 10)
let end = try GeoMotion.move(corner, bearing: 0, meters: 10)
var route = try RouteMotion(points: [start, corner, end], targetMeters: 50)
try route.advance(meters: 100)
precondition(route.position == corner, "Never cut a corner")
while !route.finished { try route.advance(meters: 7) }
precondition(abs(route.traveled - 50) < 1e-7)
let endDistance = try GeoMotion.leg(route.position, corner).meters
precondition(endDistance < 0.002, "Bounce at endpoints")
do { _ = try RouteMotion(points: [start, start]); fatalError("Duplicate-only route accepted") } catch {}
do { _ = try GeoMotion.move(.init(latitude: .nan, longitude: 0), bearing: 0, meters: 1); fatalError("NaN accepted") } catch {}
do { _ = try GeoMotion.leg(.init(latitude: 0, longitude: 0), .init(latitude: 0, longitude: 180)); fatalError("Antipodal route accepted") } catch {}
print("PASS: \(fixtures.count) GeographicLib reference cases; corners, bounce, distance target and invalid inputs")
