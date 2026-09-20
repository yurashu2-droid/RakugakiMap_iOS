import Foundation
import Supabase
import MapGrapherCore

struct SupabaseGateway {
    let client: SupabaseClient

    init(bundle: Bundle = .main) throws {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: rawURL), url.scheme == "https", let projectHost = url.host,
              let key = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
              Self.isClientKey(key),
              let bundleID = bundle.bundleIdentifier else {
            throw AppFailure.serviceUnavailable
        }
        let storage = KeychainSessionStorage.make(bundleID: bundleID, projectHost: projectHost)
        let options = SupabaseClientOptions(db: .init(encoder: SupabaseContract.encoder,
                                                      decoder: SupabaseContract.decoder),
                                            auth: .init(storage: storage,
                                                        redirectToURL: URL(string: "rakugakimap-dev://auth/callback"),
                                                        storageKey: "\(bundleID).\(projectHost).session"))
        client = SupabaseClient(supabaseURL: url, supabaseKey: key, options: options)
    }

    static func isClientKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_publishable_") { return key.count > "sb_publishable_".count }
        guard key.hasPrefix("eyJ") else { return false }
        let components = key.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return false }
        let payload = String(components[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = payload.padding(toLength: ((payload.count + 3) / 4) * 4,
                                     withPad: "=", startingAt: 0)
        guard let bytes = Data(base64Encoded: padded),
              let values = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
            return false
        }
        return values["role"] as? String == "anon"
    }

    func rpc<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, parameters: Request, as type: Response.Type = Response.self
    ) async throws -> Response {
        try await client.rpc(name, params: parameters).execute().value
    }

    func rpcVoid<Request: Encodable & Sendable>(
        _ name: String, parameters: Request
    ) async throws {
        let response = try await client.rpc(name, params: parameters).execute()
        let body = String(data: response.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (200...299).contains(response.status),
              response.data.isEmpty || body == "null" else {
            throw AppFailure.serviceUnavailable
        }
    }
}
