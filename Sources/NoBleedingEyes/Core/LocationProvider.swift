import CoreLocation
import Foundation

/// Coarse device location, cached across launches. Only used on this Mac.
@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var placeName: String?
    @Published private(set) var authorization: CLAuthorizationStatus
    private(set) var lastUpdate: Date?

    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        if let lat = defaults.object(forKey: "cachedLatitude") as? Double,
           let lon = defaults.object(forKey: "cachedLongitude") as? Double {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        placeName = defaults.string(forKey: "cachedPlaceName")
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func refresh() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.requestLocation()
    }

    private func update(with location: CLLocation) {
        coordinate = location.coordinate
        lastUpdate = Date()
        defaults.set(location.coordinate.latitude, forKey: "cachedLatitude")
        defaults.set(location.coordinate.longitude, forKey: "cachedLongitude")

        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let name = placemarks?.first?.locality else { return }
            Task { @MainActor in
                self?.placeName = name
                self?.defaults.set(name, forKey: "cachedPlaceName")
            }
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.update(with: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if !self.isDenied, status != .notDetermined { self.manager.requestLocation() }
        }
    }
}
