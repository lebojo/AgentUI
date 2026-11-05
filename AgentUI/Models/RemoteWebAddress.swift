import Foundation

struct RemoteWebAddress: Codable, Equatable, Sendable {
    private static let webSchemes = ["https", "http"]
    private static let gitSchemes = ["ssh", "git", "git+ssh", "ssh+git"]
    private static let queryCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")

    let scheme: String
    let host: String
    let port: Int?
    let path: String

    var hosting: GitHosting? { GitHosting(host: host) }
    private var segments: [Substring] { path.split(separator: "/") }

    init?(remoteURL: String) {
        let value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("://") {
            guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
                  let host = components.host else { return nil }
            if Self.webSchemes.contains(scheme) {
                self.init(scheme: scheme, host: host, port: components.port, rawPath: components.path)
            } else if Self.gitSchemes.contains(scheme) {
                self.init(scheme: "https", host: host, port: nil, rawPath: components.path)
            } else {
                return nil
            }
        } else {
            guard let colon = value.firstIndex(of: ":") else { return nil }
            let address = value[..<colon]
            guard !address.contains("/"), let host = address.split(separator: "@").last else { return nil }
            self.init(scheme: "https", host: String(host), port: nil, rawPath: String(value[value.index(after: colon)...]))
        }
    }

    private init?(scheme: String, host: String, port: Int?, rawPath: String) {
        var path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        guard !host.isEmpty, path.split(separator: "/").count >= 2 else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
    }

    func newChangeRequestURL(branch: String, base: String, from head: RemoteWebAddress? = nil) -> URL? {
        let head = head ?? self
        switch hosting {
        case .github:
            var components = self.components
            components.path = "/\(path)/compare/\(base)...\(source(of: branch, from: head))"
            components.percentEncodedQuery = "expand=1"
            return components.url
        case .gitlab:
            var components = head.components
            components.path = "/\(head.path)/-/merge_requests/new"
            components.percentEncodedQuery = "merge_request%5Bsource_branch%5D=\(Self.queryValue(branch))"
                + "&merge_request%5Btarget_branch%5D=\(Self.queryValue(base))"
            return components.url
        case nil:
            return nil
        }
    }

    private var components: URLComponents {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components
    }

    private func source(of branch: String, from head: RemoteWebAddress) -> String {
        guard head.host == host, head.path != path, let owner = head.segments.first, let name = head.segments.last else { return branch }
        return name == segments.last ? "\(owner):\(branch)" : "\(owner):\(name):\(branch)"
    }

    private static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryCharacters) ?? value
    }
}
