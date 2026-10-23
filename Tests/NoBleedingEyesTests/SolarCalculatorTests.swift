import CoreLocation
import XCTest
@testable import NoBleedingEyes

final class SolarCalculatorTests: XCTestCase {
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        paris.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func assertTime(_ date: Date, _ hour: Int, _ minute: Int, file: StaticString = #filePath, line: UInt = #line) {
        let expected = paris.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
        XCTAssertEqual(date.timeIntervalSince(expected), 0, accuracy: 3 * 60, file: file, line: line)
    }

    func testParisAutumnMatchesEphemeris() throws {
        let sun = try XCTUnwrap(SolarCalculator.sunTimes(on: day(2026, 10, 23), coordinate: .init(latitude: 48.8566, longitude: 2.3522), calendar: paris))
        assertTime(sun.sunrise, 8, 22)
        assertTime(sun.sunset, 18, 47)
    }

    func testParisSummerSolstice() throws {
        let sun = try XCTUnwrap(SolarCalculator.sunTimes(on: day(2026, 6, 21), coordinate: .init(latitude: 48.8566, longitude: 2.3522), calendar: paris))
        assertTime(sun.sunrise, 5, 47)
        assertTime(sun.sunset, 21, 58)
    }

    func testPolarNightHasNoSunTimes() {
        XCTAssertNil(SolarCalculator.sunTimes(on: day(2026, 12, 21), coordinate: .init(latitude: 78.22, longitude: 15.65), calendar: paris))
    }

    func testDateOnMinutes() {
        let date = paris.date(on: day(2026, 3, 1), minutes: 19 * 60 + 5)
        XCTAssertEqual(paris.component(.hour, from: date), 19)
        XCTAssertEqual(paris.component(.minute, from: date), 5)
    }
}
