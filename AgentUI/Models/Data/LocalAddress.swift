import Foundation

struct LocalAddress: Equatable, Sendable {
    let interface: String
    let value: String

    private var isNetworkInterface: Bool { interface.hasPrefix("en") }
    private var isLinkLocal: Bool { value.hasPrefix("169.254.") }
    private var interfaceIndex: Int { Int(interface.drop { !$0.isNumber }) ?? .max }

    static func reachable(_ addresses: [LocalAddress]) -> [String] {
        let routable = addresses.filter { !$0.isLinkLocal }
        let preferred = routable.filter(\.isNetworkInterface)
        let candidates = preferred.isEmpty ? (routable.isEmpty ? addresses : routable) : preferred
        let ordered = candidates.sorted { ($0.interfaceIndex, $0.interface, $0.value) < ($1.interfaceIndex, $1.interface, $1.value) }
        var seen: Set<String> = []
        return ordered.map(\.value).filter { seen.insert($0).inserted }
    }
}
