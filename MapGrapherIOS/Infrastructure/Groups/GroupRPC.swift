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
        try await rpcVoid(name, parameters: parameters)
    }
}

enum GroupRPCError: Error, Equatable {
    case invalidVoidResponse
}
