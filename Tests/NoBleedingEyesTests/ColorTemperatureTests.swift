import XCTest
@testable import NoBleedingEyes

final class ColorTemperatureTests: XCTestCase {
    func testNeutralIsWhite() {
        let tint = ColorTemperature.multipliers(ColorTemperature.neutral)
        XCTAssertEqual(tint.red, 1, accuracy: 0.001)
        XCTAssertEqual(tint.green, 1, accuracy: 0.001)
        XCTAssertEqual(tint.blue, 1, accuracy: 0.001)
    }

    func testWarmerMeansLessBlueAndGreen() {
        let temperatures = stride(from: 6500.0, through: 1900, by: -400).map(ColorTemperature.multipliers)
        for (warmer, cooler) in zip(temperatures.dropFirst(), temperatures) {
            XCTAssertLessThanOrEqual(warmer.blue, cooler.blue)
            XCTAssertLessThanOrEqual(warmer.green, cooler.green)
            XCTAssertEqual(warmer.red, 1, accuracy: 0.001)
        }
    }

    func testCandlelightRemovesBlue() {
        XCTAssertEqual(ColorTemperature.multipliers(1900).blue, 0, accuracy: 0.001)
    }
}
