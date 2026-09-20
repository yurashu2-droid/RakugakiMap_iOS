import Foundation
import MapGrapherCore
import Supabase

@MainActor
final class SupabaseProfileBootstrapService: ProfileBootstrapServing {
    private let gateway: SupabaseGateway
    private let session: SessionController

    init(gateway: SupabaseGateway, session: SessionController) {
        self.gateway = gateway
        self.session = session
    }

    func profileExists(context: SessionContext) async throws -> Bool {
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        let rows = try await gateway.socialProfiles(id: context.userID)
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        guard rows.count <= 1 else { throw AppFailure.serviceUnavailable }
        return rows.count == 1
    }

    func createProfile(context: SessionContext, displayName: String, uniqueID: String) async throws {
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        let rows = try await gateway.createBootstrapProfile(
            ProfileUpsertDTO(id: context.userID, userUniqueId: uniqueID,
                             displayName: displayName, avatarPath: nil))
        guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
        guard rows.count == 1, rows[0].id == context.userID else {
            throw AppFailure.serviceUnavailable
        }
    }
}

extension SupabaseGateway {
    func createBootstrapProfile(_ value: ProfileUpsertDTO) async throws -> [ProfileDTO] {
        try await client.from("profiles")
            .insert(value, returning: .representation).execute().value
    }
}
