import XCTest
@testable import NoBleedingEyes

/// Answers `URLSession.shared` requests from a table, so the client runs without a server.
final class StubProtocol: URLProtocol {
    static var responses: [String: (status: Int, body: String)] = [:]
    static var lastAuthorization: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        let stub = Self.responses[request.url!.path] ?? (404, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class HomeAssistantClientTests: XCTestCase {
    override func setUp() {
        URLProtocol.registerClass(StubProtocol.self)
        StubProtocol.responses = [
            "/api/config": (200, #"{"location_name":"Maison","version":"2026.10.2"}"#),
            "/api/states": (200, """
                [{"entity_id":"sensor.salon","state":"42.5","attributes":{"friendly_name":"Salon","device_class":"illuminance"}},
                 {"entity_id":"sensor.temp","state":"20","attributes":{"friendly_name":"Température","unit_of_measurement":"°C"}},
                 {"entity_id":"sensor.bureau","state":"unavailable","attributes":{"friendly_name":"Bureau","unit_of_measurement":"lx"}}]
                """),
            "/api/states/sensor.salon": (200, #"{"entity_id":"sensor.salon","state":"42.5","attributes":{}}"#),
            "/api/states/sensor.bureau": (200, #"{"entity_id":"sensor.bureau","state":"unavailable","attributes":{}}"#),
        ]
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubProtocol.self)
    }

    private func client() throws -> HomeAssistantClient {
        try HomeAssistantClient(baseURL: " https://ha.example.org/ ", token: " secret ")
    }

    func testRejectsURLWithoutScheme() {
        XCTAssertThrowsError(try HomeAssistantClient(baseURL: "homeassistant.local", token: "secret")) { error in
            guard case HomeAssistantClient.Failure.invalidURL = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsBlankToken() {
        XCTAssertThrowsError(try HomeAssistantClient(baseURL: "https://ha.example.org", token: "  ")) { error in
            guard case HomeAssistantClient.Failure.missingToken = error else { return XCTFail("\(error)") }
        }
    }

    func testServerInfoSendsTrimmedBearerToken() async throws {
        let info = try await client().serverInfo()
        XCTAssertEqual(info.name, "Maison")
        XCTAssertEqual(info.version, "2026.10.2")
        XCTAssertEqual(StubProtocol.lastAuthorization, "Bearer secret")
    }

    func testUnauthorized() async throws {
        StubProtocol.responses["/api/config"] = (401, "")
        do {
            _ = try await client().serverInfo()
            XCTFail("expected an error")
        } catch HomeAssistantClient.Failure.unauthorized {}
    }

    func testListsOnlyIlluminanceSensors() async throws {
        let sensors = try await client().illuminanceSensors()
        XCTAssertEqual(sensors.map(\.id), ["sensor.bureau", "sensor.salon"])
        XCTAssertNil(sensors[0].lux)
        XCTAssertEqual(sensors[1].lux, 42.5)
    }

    func testReadsIlluminance() async throws {
        let lux = try await client().illuminance(of: "sensor.salon")
        XCTAssertEqual(lux, 42.5)
    }

    func testUnavailableSensor() async throws {
        do {
            _ = try await client().illuminance(of: "sensor.bureau")
            XCTFail("expected an error")
        } catch HomeAssistantClient.Failure.unavailable(let state) {
            XCTAssertEqual(state, "unavailable")
        }
    }

    func testUnknownEntity() async throws {
        do {
            _ = try await client().illuminance(of: "sensor.absent")
            XCTFail("expected an error")
        } catch HomeAssistantClient.Failure.notFound(let entity) {
            XCTAssertEqual(entity, "sensor.absent")
        }
    }
}
