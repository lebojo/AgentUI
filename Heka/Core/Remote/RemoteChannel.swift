import Foundation
import Network

enum RemoteChannel {
    static func parameters(key: PairingKey) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let identity = Data(RemotePairing.identity.utf8)
        sec_protocol_options_add_pre_shared_key(options, key.data.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
                                                identity.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 15
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.noDelay = true
        return NWParameters(tls: tls, tcp: tcp)
    }

    private static let callGate = RemoteCallGate(limit: 4)

    static func connection(to host: String, key: PairingKey) throws -> NWConnection {
        NWConnection(host: try RemoteProtocol.host(host), port: NWEndpoint.Port(rawValue: RemoteProtocol.port)!, using: parameters(key: key))
    }

    static func call<Value: Decodable & Sendable>(_ request: RemoteRequest, host: String, key: PairingKey,
                                                  as type: Value.Type = Value.self) async throws -> Value {
        guard request.waitsForInspectorSlot else { return try await perform(request, host: host, key: key, as: type) }
        try await callGate.enter()
        do {
            let value = try await perform(request, host: host, key: key, as: type)
            await callGate.leave()
            return value
        } catch {
            await callGate.leave()
            throw error
        }
    }

    private static func perform<Value: Decodable & Sendable>(_ request: RemoteRequest, host: String, key: PairingKey,
                                                             as type: Value.Type) async throws -> Value {
        let connection = try Self.connection(to: host, key: key)
        return try await withTaskCancellationHandler {
            defer { connection.cancel() }
            return try await withTimeout(request.timeout, on: connection, failure: unresponsiveHost) {
                connection.start(queue: .global(qos: .userInitiated))
                try await send(request, on: connection)
                let reply: RemoteReply = try await receive(on: connection)
                return try reply.decode(type)
            }
        } onCancel: { connection.cancel() }
    }

    static func firstEvent(after request: RemoteRequest, on connection: NWConnection) async throws -> RemoteEvent {
        try await withTimeout(on: connection, failure: unresponsiveHost) {
            connection.start(queue: .global(qos: .userInitiated))
            try await send(request, on: connection)
            return try await receive(on: connection)
        }
    }

    static func withTimeout<Value: Sendable>(_ timeout: Duration = .seconds(15), on connection: NWConnection, failure: some Error & Sendable,
                                             _ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutExpired()
            }
            defer { group.cancelAll() }
            do {
                return try await group.next()!
            } catch is TimeoutExpired {
                connection.cancel()
                throw failure
            }
        }
    }

    private static var unresponsiveHost: RemoteError {
        RemoteError(message: String(localized: "The Mac isn’t responding. Check its IP address, the local network and its Local Access settings."))
    }

    @concurrent static func send(_ value: some Encodable & Sendable, on connection: NWConnection) async throws {
        let data = try frame(value)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: translated(error)) }
                else { continuation.resume() }
            })
        }
    }

    static func push(_ value: some Encodable & Sendable, on connection: NWConnection) async throws {
        try await withTimeout(.seconds(30), on: connection, failure: CancellationError()) {
            try await send(value, on: connection)
        }
    }

    static func enqueue(_ value: some Encodable, on connection: NWConnection, failure: @escaping @Sendable (Error) -> Void) throws {
        connection.send(content: try frame(value), completion: .contentProcessed { error in
            if let error { failure(translated(error)) }
        })
    }

    static func cancelWhenPeerCloses(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in connection.cancel() }
    }

    private static func frame(_ value: some Encodable) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= RemoteProtocol.maximumFrame else { throw RemoteError(message: String(localized: "Response too large.")) }
        let size = UInt32(data.count)
        return Data([UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)]) + data
    }

    @concurrent static func receive<Value: Decodable & Sendable>(on connection: NWConnection) async throws -> Value {
        let header = try await read(count: 4, on: connection)
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0, count <= RemoteProtocol.maximumFrame else { throw RemoteError(message: String(localized: "Invalid network message.")) }
        return try JSONDecoder().decode(Value.self, from: await read(count: count, on: connection))
    }

    private static func read(count: Int, on connection: NWConnection) async throws -> Data {
        var data = Data()
        while data.count < count {
            let remaining = count - data.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    if let error { continuation.resume(throwing: translated(error)) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: RemoteError(message: complete ? String(localized: "Connection to the Mac closed.") : String(localized: "Empty network response."))) }
                }
            }
            data.append(chunk)
        }
        return data
    }

    private static let pairingMismatch: Set<OSStatus> = [errSSLPeerBadRecordMac, errSSLBadRecordMac, errSSLDecryptionFail,
                                                         errSSLPeerDecryptError, errSSLPeerDecryptionFail]

    private static func translated(_ error: NWError) -> Error {
        guard case .tls(let status) = error, pairingMismatch.contains(status) else { return error }
        return RemoteError(message: String(localized: "Pairing code rejected. Copy the code shown on the Mac in Settings → Local Access."), isPermanent: true)
    }
}

private struct TimeoutExpired: Error {}

private actor RemoteCallGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let limit: Int
    private var running = 0
    private var waiting: [Waiter] = []

    init(limit: Int) {
        self.limit = limit
    }

    func enter() async throws {
        guard running >= limit else {
            running += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await wait(id)
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func wait(_ id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
            else { waiting.append(Waiter(id: id, continuation: continuation)) }
        }
    }

    func leave() {
        if waiting.isEmpty { running -= 1 }
        else { waiting.removeFirst().continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
