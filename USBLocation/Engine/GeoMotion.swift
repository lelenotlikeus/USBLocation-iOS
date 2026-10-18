import Foundation

struct GeoPoint: Equatable, Codable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

enum GeoError: Error, LocalizedError {
    case invalidPoint, invalidDistance, ambiguousRoute
    var errorDescription: String? {
        switch self {
        case .invalidPoint: return "Il percorso contiene coordinate non valide."
        case .invalidDistance: return "Distanza non valida o percorso senza spostamento."
        case .ambiguousRoute: return "Segmento quasi antipodale: aggiungi una tappa intermedia."
        }
    }
}

enum GeoMotion {
    private static let a = 6378137.0
    private static let f = 1 / 298.257223563
    private static let b = a * (1 - f)
    private static let rad = Double.pi / 180

    // Vincenty's WGS84 direct solution. Short joystick steps also work across poles/dateline.
    static func move(_ point: GeoPoint, bearing: Double, meters: Double) throws -> GeoPoint {
        guard point.isValid, bearing.isFinite else { throw GeoError.invalidPoint }
        guard meters.isFinite, meters >= 0 else { throw GeoError.invalidDistance }
        if meters == 0 { return point }
        let alpha = bearing * rad
        let u = atan((1 - f) * tan(point.latitude * rad))
        let sinU = sin(u), cosU = cos(u)
        let sigma1 = atan2(tan(u), cos(alpha))
        let sinAlpha = cosU * sin(alpha)
        let cos2Alpha = max(0, 1 - sinAlpha * sinAlpha)
        let u2 = cos2Alpha * (a * a - b * b) / (b * b)
        let aa = 1 + u2 / 16384 * (4096 + u2 * (-768 + u2 * (320 - 175 * u2)))
        let bb = u2 / 1024 * (256 + u2 * (-128 + u2 * (74 - 47 * u2)))
        var sigma = meters / (b * aa)
        for _ in 0..<100 {
            let cm = cos(2 * sigma1 + sigma), ss = sin(sigma), cs = cos(sigma)
            let delta = bb * ss * (cm + bb / 4 * (cs * (-1 + 2 * cm * cm) - bb / 6 * cm * (-3 + 4 * ss * ss) * (-3 + 4 * cm * cm)))
            let next = meters / (b * aa) + delta
            if abs(next - sigma) < 1e-13 { sigma = next; break }
            sigma = next
        }
        let ss = sin(sigma), cs = cos(sigma), cm = cos(2 * sigma1 + sigma)
        let temp = sinU * ss - cosU * cs * cos(alpha)
        let latitude = atan2(sinU * cs + cosU * ss * cos(alpha), (1 - f) * hypot(sinAlpha, temp)) / rad
        let lambda = atan2(ss * sin(alpha), cosU * cs - sinU * ss * cos(alpha))
        let c = f / 16 * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha))
        let l = lambda - (1 - c) * f * sinAlpha * (sigma + c * ss * (cm + c * cs * (-1 + 2 * cm * cm)))
        var longitude = (point.longitude + l / rad + 180).truncatingRemainder(dividingBy: 360)
        if longitude < 0 { longitude += 360 }
        return GeoPoint(latitude: max(-90, min(90, latitude)), longitude: longitude - 180)
    }

    static func leg(_ from: GeoPoint, _ to: GeoPoint) throws -> (meters: Double, bearing: Double) {
        guard from.isValid, to.isValid else { throw GeoError.invalidPoint }
        if from == to { return (0, 0) }
        let u1 = atan((1 - f) * tan(from.latitude * rad)), u2 = atan((1 - f) * tan(to.latitude * rad))
        let su1 = sin(u1), cu1 = cos(u1), su2 = sin(u2), cu2 = cos(u2)
        var l = (to.longitude - from.longitude) * rad
        if l > .pi { l -= 2 * .pi }; if l < -.pi { l += 2 * .pi }
        var lambda = l
        var sigma = 0.0, ss = 0.0, cs = 0.0, sinAlpha = 0.0, ca2 = 0.0, cm = 0.0
        var converged = false
        for _ in 0..<200 {
            let sl = sin(lambda), cl = cos(lambda)
            ss = hypot(cu2 * sl, cu1 * su2 - su1 * cu2 * cl)
            if ss < 1e-15 { if cu1 * cu2 * cl + su1 * su2 > 0 { return (0, 0) }; throw GeoError.ambiguousRoute }
            cs = su1 * su2 + cu1 * cu2 * cl
            sigma = atan2(ss, cs)
            sinAlpha = cu1 * cu2 * sl / ss
            ca2 = max(0, 1 - sinAlpha * sinAlpha)
            cm = ca2 > 1e-15 ? cs - 2 * su1 * su2 / ca2 : 0
            let c = f / 16 * ca2 * (4 + f * (4 - 3 * ca2))
            let next = l + (1 - c) * f * sinAlpha * (sigma + c * ss * (cm + c * cs * (-1 + 2 * cm * cm)))
            if abs(next - lambda) < 1e-12 { lambda = next; converged = true; break }
            lambda = next
        }
        guard converged else { throw GeoError.ambiguousRoute }
        let u = ca2 * (a * a - b * b) / (b * b)
        let aa = 1 + u / 16384 * (4096 + u * (-768 + u * (320 - 175 * u)))
        let bb = u / 1024 * (256 + u * (-128 + u * (74 - 47 * u)))
        let delta = bb * ss * (cm + bb / 4 * (cs * (-1 + 2 * cm * cm) - bb / 6 * cm * (-3 + 4 * ss * ss) * (-3 + 4 * cm * cm)))
        return (b * aa * (sigma - delta), atan2(cu2 * sin(lambda), cu1 * su2 - su1 * cu2 * cos(lambda)) / rad)
    }
}

struct RouteMotion {
    let points: [GeoPoint]
    let targetMeters: Double
    private(set) var position: GeoPoint
    private(set) var traveled = 0.0
    private var nextIndex = 1
    private var direction = 1
    var finished: Bool { traveled >= targetMeters - 1e-7 }

    init(points: [GeoPoint], targetMeters: Double? = nil) throws {
        guard points.count >= 2, points.count <= 2000, points.allSatisfy(\.isValid) else { throw GeoError.invalidPoint }
        var cleaned = [points[0]]
        for point in points.dropFirst() {
            if try GeoMotion.leg(cleaned.last!, point).meters > 0.001 { cleaned.append(point) }
        }
        guard cleaned.count >= 2 else { throw GeoError.invalidDistance }
        var length = 0.0
        for (a, b) in zip(cleaned, cleaned.dropFirst()) { length += try GeoMotion.leg(a, b).meters }
        let goal = targetMeters ?? length
        guard goal.isFinite, goal > 0, goal <= 10_000_000 else { throw GeoError.invalidDistance }
        self.points = cleaned
        self.targetMeters = goal
        self.position = cleaned[0]
    }

    mutating func advance(meters: Double) throws {
        guard meters.isFinite, meters >= 0 else { throw GeoError.invalidDistance }
        if finished || meters == 0 { return }
        let target = points[nextIndex]
        let leg = try GeoMotion.leg(position, target)
        let step = min(meters, leg.meters, targetMeters - traveled)
        if step >= leg.meters - 1e-7 {
            position = target
            if nextIndex == points.count - 1 { direction = -1 }
            if nextIndex == 0 { direction = 1 }
            nextIndex += direction
        } else {
            position = try GeoMotion.move(position, bearing: leg.bearing, meters: step)
        }
        traveled = min(targetMeters, traveled + step)
    }
}
