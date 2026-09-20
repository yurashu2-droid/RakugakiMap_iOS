import Foundation
import Supabase

enum KeychainSessionStorage {
    static func make(bundleID: String, projectHost: String) -> KeychainLocalStorage {
        KeychainLocalStorage(service: "\(bundleID).supabase.\(projectHost)")
    }
}
