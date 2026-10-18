import CoreLocation
import Foundation
import MapKit

enum RouteBuilder {
    static func roadRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = mode.mkTransportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "USBLocation", code: 1, userInfo: [NSLocalizedDescriptionKey: "No route found"])
        }
        return try sample(polyline: route.polyline, every: 12)
    }

    static func sample(polyline: MKPolyline, every meters: CLLocationDistance) throws -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return try sample(coordinates: coords, every: meters)
    }

    static func sample(coordinates: [CLLocationCoordinate2D], every meters: CLLocationDistance) throws -> [CLLocationCoordinate2D] {
        guard coordinates.count <= 2000, meters.isFinite, meters > 0,
              coordinates.allSatisfy({ CLLocationCoordinate2DIsValid($0) && $0.latitude.isFinite && $0.longitude.isFinite })
        else { throw RouteDataError.invalidPoints }
        guard coordinates.count > 1 else { return coordinates }
        var sampled = [coordinates[0]]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let dist = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let requested = ceil(dist / meters)
            guard requested.isFinite, requested <= Double(2000 - sampled.count) else { throw RouteDataError.tooManyPoints }
            let steps = max(1, Int(requested))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                if i == steps { sampled.append(b) }
                else {
                    let origin = GeoPoint(latitude: a.latitude, longitude: a.longitude)
                    let leg = try GeoMotion.leg(origin, GeoPoint(latitude: b.latitude, longitude: b.longitude))
                    let point = try GeoMotion.move(origin, bearing: leg.bearing, meters: leg.meters * t)
                    sampled.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                }
            }
        }
        return sampled
    }
}

enum RouteDataError: Error, LocalizedError {
    case tooLarge, invalidPoints, tooManyPoints, invalidXML
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "GPX troppo grande: massimo 5 MB."
        case .invalidPoints: return "Coordinate GPX non valide o nessun punto utilizzabile."
        case .tooManyPoints: return "Tracciato troppo denso: massimo 2.000 punti. Scegli un percorso più breve."
        case .invalidXML: return "GPX/XML non valido. DTD ed entità non sono consentiti."
        }
    }
}

enum GPXCodec {
    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 5 * 1024 * 1024 { throw RouteDataError.tooLarge }
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> [CLLocationCoordinate2D] {
        guard data.count <= 5 * 1024 * 1024 else { throw RouteDataError.tooLarge }
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .utf32] {
            if let text = String(data: data, encoding: encoding)?.uppercased(),
               text.contains("<!DOCTYPE") || text.contains("<!ENTITY") { throw RouteDataError.invalidXML }
        }
        let delegate = GPXReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        let valid = parser.parse()
        if let error = delegate.error { throw error }
        guard valid else { throw RouteDataError.invalidXML }
        guard !delegate.points.isEmpty else { throw RouteDataError.invalidPoints }
        return delegate.points
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "USBLocation Route") -> String {
        let escaped = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let points = coordinates.map { String(format: "<trkpt lat=\"%.8f\" lon=\"%.8f\"/>", locale: Locale(identifier: "en_US_POSIX"), $0.latitude, $0.longitude) }.joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"USBLocation\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>\(escaped)</name><trkseg>\(points)</trkseg></trk></gpx>"
    }
}

private final class GPXReader: NSObject, XMLParserDelegate {
    var points: [CLLocationCoordinate2D] = []
    var error: RouteDataError?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard ["trkpt", "rtept", "wpt"].contains(name) else { return }
        guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init),
              GeoPoint(latitude: lat, longitude: lon).isValid else {
            error = .invalidPoints; parser.abortParsing(); return
        }
        guard points.count < 2000 else { error = .tooManyPoints; parser.abortParsing(); return }
        points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        error = .invalidXML; parser.abortParsing()
    }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        error = .invalidXML; parser.abortParsing()
    }
}
