import Foundation

extension String {
    private static let unreservedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    var percentEncodedQueryValue: String {
        addingPercentEncoding(withAllowedCharacters: Self.unreservedCharacters) ?? self
    }
}
