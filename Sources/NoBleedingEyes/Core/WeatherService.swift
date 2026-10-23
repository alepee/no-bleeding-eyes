import CoreLocation
import Foundation

struct WeatherReport {
    struct Hour {
        let time: Date
        let cloudCover: Double
        let weatherCode: Int
    }

    let temperature: Double // °C
    let cloudCover: Double // %
    let precipitation: Double // mm
    let uvIndex: Double
    let weatherCode: Int // WMO code
    let hourly: [Hour]
    let coordinate: CLLocationCoordinate2D
    let fetchedAt: Date

    /// True when the daytime part of the forecast is overcast enough, or stormy.
    func isDarkDay(from start: Date, to end: Date, cloudThreshold: Double) -> Bool {
        let daytime = hourly.filter { $0.time >= start && $0.time < end }
        guard !daytime.isEmpty else { return false }
        let meanCloudCover = daytime.map(\.cloudCover).reduce(0, +) / Double(daytime.count)
        return meanCloudCover >= cloudThreshold || daytime.contains { WeatherCode.isStorm($0.weatherCode) }
    }
}

/// Forecast from Open-Meteo (no API key, no account). Coordinates are rounded to ~1 km before leaving the Mac.
struct WeatherService {
    func fetch(at coordinate: CLLocationCoordinate2D) async throws -> WeatherReport {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,cloud_cover,precipitation,uv_index,weather_code"),
            URLQueryItem(name: "hourly", value: "cloud_cover,weather_code"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let payload = try JSONDecoder().decode(Payload.self, from: data)

        let hours = zip(payload.hourly.time, zip(payload.hourly.cloud_cover, payload.hourly.weather_code)).map {
            WeatherReport.Hour(time: Date(timeIntervalSince1970: $0), cloudCover: $1.0 ?? 0, weatherCode: $1.1 ?? 0)
        }
        return WeatherReport(
            temperature: payload.current.temperature_2m,
            cloudCover: payload.current.cloud_cover,
            precipitation: payload.current.precipitation,
            uvIndex: payload.current.uv_index ?? 0,
            weatherCode: payload.current.weather_code,
            hourly: hours,
            coordinate: coordinate,
            fetchedAt: Date()
        )
    }

    private struct Payload: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let cloud_cover: Double
            let precipitation: Double
            let uv_index: Double?
            let weather_code: Int
        }

        struct Hourly: Decodable {
            let time: [TimeInterval]
            let cloud_cover: [Double?]
            let weather_code: [Int?]
        }

        let current: Current
        let hourly: Hourly
    }
}

/// WMO weather interpretation codes.
enum WeatherCode {
    static func isStorm(_ code: Int) -> Bool { code >= 95 }

    /// SF Symbol name, meant for multicolor rendering.
    static func systemImage(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }

    static func label(_ code: Int) -> String {
        switch code {
        case 0: return "Dégagé"
        case 1: return "Plutôt dégagé"
        case 2: return "Partiellement nuageux"
        case 3: return "Couvert"
        case 45, 48: return "Brouillard"
        case 51...57: return "Bruine"
        case 61...67: return "Pluie"
        case 71...77: return "Neige"
        case 80...82: return "Averses"
        case 85, 86: return "Averses de neige"
        case 95...99: return "Orage"
        default: return "Inconnu"
        }
    }
}
