import Foundation

actor ARCameraLease {
    static let shared = ARCameraLease()
    private var holder: UUID?

    func acquire(_ id: UUID) -> Bool {
        guard holder == nil || holder == id else { return false }
        holder = id
        return true
    }

    func release(_ id: UUID) {
        if holder == id { holder = nil }
    }
}
