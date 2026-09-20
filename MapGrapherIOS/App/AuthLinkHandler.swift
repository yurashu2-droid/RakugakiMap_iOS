import Foundation

struct AuthLinkHandler: Sendable {
    enum Flow: Equatable, Sendable { case code, error }

    let redirectURL: URL

    func flow(for url: URL) -> Flow? {
        guard let expected = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false),
              let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == expected.scheme?.lowercased(),
              actual.host?.lowercased() == expected.host?.lowercased(),
              actual.path == expected.path,
              actual.user == nil, actual.password == nil, actual.port == nil,
              actual.fragment == nil else { return nil }
        let parameters = actual.queryItems ?? []
        let codes = parameters.filter { $0.name == "code" && $0.value?.isEmpty == false }
        let errors = parameters.filter { $0.name == "error" && $0.value?.isEmpty == false }
        if codes.count == 1, errors.isEmpty,
           !parameters.contains(where: { ["access_token", "refresh_token", "token"].contains($0.name) }) {
            return .code
        }
        if errors.count == 1, codes.isEmpty { return .error }
        return nil
    }
}
