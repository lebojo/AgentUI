import Foundation

enum MobileSavedHosts {
    private static let hostsKey = "savedHosts"
    private static let selectionKey = "selectedHost"
    private static let legacyHostKey = "remoteHost"
    private static let legacyPairingAccount = "remotePairingCode"

    static func load() -> (hosts: [SavedHost], selection: UUID?) {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: hostsKey), let hosts = try? JSONDecoder().decode([SavedHost].self, from: data) {
            let selection = defaults.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
            return (hosts, hosts.contains { $0.id == selection } ? selection : nil)
        }
        guard let address = defaults.string(forKey: legacyHostKey), !address.isEmpty else { return ([], nil) }
        let host = SavedHost(name: address, addresses: [address], pairingAccount: legacyPairingAccount)
        save([host], selection: host.id)
        return ([host], host.id)
    }

    static func save(_ hosts: [SavedHost], selection: UUID?) {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(hosts) { defaults.set(data, forKey: hostsKey) }
        defaults.set(selection?.uuidString, forKey: selectionKey)
        defaults.removeObject(forKey: legacyHostKey)
    }
}
