import CoreLocation
import Foundation

struct SunTimes: Equatable {
    let sunrise: Date
    let sunset: Date
}

/// Sunrise equation (NOAA approximation), accurate to about a minute.
enum SolarCalculator {
    /// Sun times for the local calendar day containing `day`, or nil during polar day or night.
    static func sunTimes(on day: Date, coordinate: CLLocationCoordinate2D, calendar: Calendar = .current) -> SunTimes? {
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { return nil }

        let julianDate = noon.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let n = (julianDate - 2_451_545.0 + 0.0008).rounded()
        let meanSolarNoon = n - coordinate.longitude / 360

        let meanAnomaly = (357.5291 + 0.98560028 * meanSolarNoon).truncatingRemainder(dividingBy: 360)
        let m = radians(meanAnomaly)
        let center = 1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m)
        let eclipticLongitude = radians((meanAnomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360))
        let transit = 2_451_545.0 + meanSolarNoon + 0.0053 * sin(m) - 0.0069 * sin(2 * eclipticLongitude)

        let declination = asin(sin(eclipticLongitude) * sin(radians(23.4397)))
        let latitude = radians(coordinate.latitude)
        let cosHourAngle = (sin(radians(-0.833)) - sin(latitude) * sin(declination)) / (cos(latitude) * cos(declination))
        guard abs(cosHourAngle) <= 1 else { return nil }
        let hourAngle = acos(cosHourAngle) * 180 / .pi

        return SunTimes(
            sunrise: date(fromJulian: transit - hourAngle / 360),
            sunset: date(fromJulian: transit + hourAngle / 360)
        )
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    private static func date(fromJulian julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86_400)
    }
}

extension Calendar {
    /// `minutes` after midnight on the day containing `day`.
    func date(on day: Date, minutes: Int) -> Date {
        date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }
}
