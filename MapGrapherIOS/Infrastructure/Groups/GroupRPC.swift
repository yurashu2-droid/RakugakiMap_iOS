import Foundation
import Supabase

@MainActor
protocol GroupRPCCalling {
    func call<Parameters: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, parameters: Parameters, as type: Result.Type
    ) async throws -> Result
    func callVoid<Parameters: Encodable & Sendable>(
        _ name: String, parameters: Parameters
    ) async throws
}

extension SupabaseGateway: GroupRPCCalling {
    func call<Parameters: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, parameters: Parameters, as type: Result.Type
    ) async throws -> Result {
        try await rpc(name, parameters: parameters, as: type)
    }

    func callVoid<Parameters: Encodable & Sendable>(
        _ name: String, parameters: Parameters
    ) async throws {
        let response = try await client.rpc(name, params: parameters).execute()
        let body = String(data: response.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (200...299).contains(response.status),
              response.data.isEmpty || body == "null" else {
            throw GroupRPCError.invalidVoidResponse
        }
    }
}

enum GroupRPCError: Error, Equatable {
    case invalidVoidResponse
}
