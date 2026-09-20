import Foundation

public protocol SessionProviding: Sendable {
    func currentContext() async -> SessionContext?
    func isCurrent(_ context: SessionContext) async -> Bool
}
