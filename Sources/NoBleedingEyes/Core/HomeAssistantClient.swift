import Foundation

/// Reads illuminance sensors through the Home Assistant REST API.
struct HomeAssistantClient {
    struct Sensor: Identifiable, Hashable {
        let id: String
        let name: String
        let lux: Double?
    }

    struct ServerInfo {
        let name: String
        let version: String
    }

    enum Failure: LocalizedError {
        case invalidURL
        case missingToken
        case unauthorized
        case notFound(String)
        case unavailable(String)
        case http(Int)
        case network(URLError)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL invalide : elle doit commencer par http:// ou https://."
            case .missingToken: return "Jeton d'accès manquant."
            case .unauthorized: return "Jeton refusé par Home Assistant (révoqué ou mal copié)."
            case .notFound(let entity): return "L'entité « \(entity) » n'existe pas sur ce serveur."
            case .unavailable(let state): return "Le capteur ne renvoie pas de valeur (état « \(state) »)."
            case .http(let code): return "Le serveur a répondu avec une erreur HTTP \(code)."
            case .network(let error): return Self.describe(error)
            }
        }

        private static func describe(_ error: URLError) -> String {
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed: return "Serveur introuvable : vérifiez le nom de domaine."
            case .cannotConnectToHost: return "Connexion refusée : le serveur ne répond pas sur ce port."
            case .timedOut: return "Le serveur n'a pas répondu dans les 10 secondes."
            case .notConnectedToInternet, .networkConnectionLost: return "Pas de connexion réseau."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "Connexion HTTPS refusée : certificat invalide ou non reconnu."
            case .appTransportSecurityRequiresSecureConnection:
                return "HTTP non chiffré refusé par macOS pour cette adresse : utilisez https://."
            default: return error.localizedDescription
            }
        }
    }

    private let baseURL: URL
    private let token: String

    init(baseURL: String, token: String) throws {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https", url.host != nil else {
            throw Failure.invalidURL
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw Failure.missingToken }
        self.baseURL = url
        self.token = token
    }

    /// Checks URL and token without involving any entity.
    func serverInfo() async throws -> ServerInfo {
        let config = try JSONDecoder().decode(Config.self, from: await get("api/config"))
        return ServerInfo(name: config.location_name ?? "Home Assistant", version: config.version ?? "?")
    }

    func illuminance(of entityID: String) async throws -> Double {
        let state = try JSONDecoder().decode(EntityState.self, from: await get("api/states/\(entityID)", entity: entityID))
        guard let lux = Double(state.state) else { throw Failure.unavailable(state.state) }
        return lux
    }

    func illuminanceSensors() async throws -> [Sensor] {
        let states = try JSONDecoder().decode([EntityState].self, from: await get("api/states"))
        return states
            .filter { $0.attributes.device_class == "illuminance" || $0.attributes.unit_of_measurement == "lx" }
            .map { Sensor(id: $0.entity_id, name: $0.attributes.friendly_name ?? $0.entity_id, lux: Double($0.state)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func get(_ path: String, entity: String? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw Failure.network(error)
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return data
        case 401, 403: throw Failure.unauthorized
        case 404: throw Failure.notFound(entity ?? path)
        case let code: throw Failure.http(code)
        }
    }

    private struct Config: Decodable {
        let location_name: String?
        let version: String?
    }

    private struct EntityState: Decodable {
        struct Attributes: Decodable {
            let friendly_name: String?
            let device_class: String?
            let unit_of_measurement: String?
        }

        let entity_id: String
        let state: String
        let attributes: Attributes
    }
}

/// Generic-password storage for secrets that must not live in `UserDefaults`.
enum Keychain {
    private static let service = "com.alepee.NoBleedingEyes"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
