import CoreLocation
import XCTest
@testable import NoBleedingEyes

final class WeatherReportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(_ hours: [(cloud: Double, code: Int)]) -> WeatherReport {
        WeatherReport(
            temperature: 12, cloudCover: 0, precipitation: 0, uvIndex: 0, weatherCode: 0,
            hourly: hours.enumerated().map { index, hour in
                WeatherReport.Hour(time: start.addingTimeInterval(Double(index) * 3600), cloudCover: hour.cloud, weatherCode: hour.code)
            },
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            fetchedAt: start
        )
    }

    func testOvercastDayAboveThresholdIsDark() {
        let forecast = report([(90, 3), (100, 3), (80, 3)])
        XCTAssertTrue(forecast.isDarkDay(from: start, to: start.addingTimeInterval(3 * 3600), cloudThreshold: 85))
    }

    func testMeanBelowThresholdStaysLight() {
        let forecast = report([(100, 3), (40, 2), (60, 2)])
        XCTAssertFalse(forecast.isDarkDay(from: start, to: start.addingTimeInterval(3 * 3600), cloudThreshold: 85))
    }

    func testStormDarkensRegardlessOfClouds() {
        let forecast = report([(20, 1), (30, 95), (20, 1)])
        XCTAssertTrue(forecast.isDarkDay(from: start, to: start.addingTimeInterval(3 * 3600), cloudThreshold: 85))
    }

    func testHoursOutsideDaytimeAreIgnored() {
        let forecast = report([(100, 95), (10, 0), (10, 0)])
        XCTAssertFalse(forecast.isDarkDay(from: start.addingTimeInterval(3600), to: start.addingTimeInterval(3 * 3600), cloudThreshold: 85))
    }

    func testNoDaytimeDataStaysLight() {
        XCTAssertFalse(report([]).isDarkDay(from: start, to: start.addingTimeInterval(3600), cloudThreshold: 0))
    }
}
