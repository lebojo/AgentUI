import Foundation
import Darwin
import os

enum CommandRunner {
    private static let registry = Registry()

    static func cancelAll() { registry.cancelAll() }

    static func run(_ executable: URL, _ arguments: [String], at path: String,
                    timeout: TimeInterval, limit: Int, readOnly: Bool,
                    gitConfiguration: [String: String] = [:]) async throws -> Data {
        let job = Job()
        let id = UUID()
        registry.add(job, id: id)
        defer { registry.remove(id) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await execute(job, executable: executable, arguments: arguments, at: path, timeout: timeout, limit: limit,
                                     readOnly: readOnly, gitConfiguration: gitConfiguration)
        } onCancel: { job.stop(.cancelled) }
    }

    static func environment(readOnly: Bool, gitConfiguration: [String: String] = [:],
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        environment["GIT_TERMINAL_PROMPT"] = "0"
        if readOnly { environment["GIT_OPTIONAL_LOCKS"] = "0" }
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_PAGER"] = "cat"
        environment["NO_COLOR"] = "1"
        environment.removeValue(forKey: "GH_DEBUG")
        return GitConfiguration.appending(gitConfiguration.merging(GitConfiguration.hardened) { $1 }, to: environment)
    }

    @concurrent private static func execute(_ job: Job, executable: URL, arguments: [String], at path: String,
                                            timeout: TimeInterval, limit: Int, readOnly: Bool,
                                            gitConfiguration: [String: String]) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("agentui-command-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout"), errURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: outURL), error = try FileHandle(forWritingTo: errURL)
        defer { try? output.close(); try? error.close() }
        let pid = try job.start(executable: executable.path, arguments: arguments,
                                environment: environment(readOnly: readOnly, gitConfiguration: gitConfiguration),
                                directory: path, output: output.fileDescriptor, error: error.fileDescriptor)
        let queue = DispatchQueue(label: "AgentUI.command", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let deadline = DispatchTime.now() + timeout
        let outFD = output.fileDescriptor, errFD = error.fileDescriptor
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
        timer.setEventHandler {
            var outStat = stat(), errStat = stat()
            if fstat(outFD, &outStat) == 0, fstat(errFD, &errStat) == 0,
               outStat.st_size > limit || errStat.st_size > 65_536 { job.stop(.outputLimit) }
            else if DispatchTime.now() >= deadline { job.stop(.timeout) }
        }
        timer.resume()
        defer { timer.cancel(); queue.sync {} }
        if await !waitForExit(of: pid, on: queue) { job.stop(.waitFailure) }
        var status: Int32 = 0
        try job.finish(status: &status)
        let reader = try FileHandle(forReadingFrom: outURL)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ReadCommandError(message: "La sortie dépasse la limite d’affichage. Ouvre ce contenu dans ton éditeur.") }
        guard status == 0 else {
            let reader = try FileHandle(forReadingFrom: errURL)
            defer { try? reader.close() }
            let diagnostic = String(decoding: try reader.read(upToCount: 4096) ?? Data(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ReadCommandError(message: diagnostic.isEmpty ? "La commande a échoué (statut \(status))." : diagnostic)
        }
        return data
    }

    private static func waitForExit(of pid: pid_t, on queue: DispatchQueue) async -> Bool {
        await withCheckedContinuation { continuation in
            let observation = ExitObservation()
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            source.setEventHandler { source.cancel() }
            source.setCancelHandler { continuation.resume(returning: !observation.failed) }
            source.resume()
            queue.async {
                switch exitState(of: pid) {
                case .running: break
                case .exited: source.cancel()
                case .failed: observation.failed = true; source.cancel()
                }
            }
        }
    }

    private enum ExitState { case running, exited, failed }

    private static func exitState(of pid: pid_t) -> ExitState {
        var info = siginfo_t()
        var result: Int32
        repeat { result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT | WNOHANG) } while result == -1 && errno == EINTR
        if result == -1 { return .failed }
        return info.si_pid == pid ? .exited : .running
    }

    private final class ExitObservation: @unchecked Sendable {
        var failed = false
    }

    private enum StopReason { case cancelled, timeout, outputLimit, waitFailure }

    private final class Registry: Sendable {
        private let jobs = OSAllocatedUnfairLock<[UUID: Job]>(initialState: [:])
        func add(_ job: Job, id: UUID) { jobs.withLock { $0[id] = job } }
        func remove(_ id: UUID) { _ = jobs.withLock { $0.removeValue(forKey: id) } }
        func cancelAll() {
            let active = jobs.withLock { Array($0.values) }
            active.forEach { $0.stop(.cancelled) }
        }
    }

    private final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var pid: pid_t?
        private var reason: StopReason?
        private var finished = false

        func start(executable: String, arguments: [String], environment: [String: String], directory: String,
                   output: Int32, error: Int32) throws -> pid_t {
            lock.lock()
            defer { lock.unlock() }
            if reason != nil { throw CancellationError() }
            var actions: posix_spawn_file_actions_t?
            var attributes: posix_spawnattr_t?
            try checked(posix_spawn_file_actions_init(&actions))
            defer { posix_spawn_file_actions_destroy(&actions) }
            try checked(posix_spawnattr_init(&attributes))
            defer { posix_spawnattr_destroy(&attributes) }
            try checked(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
            try checked(posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO))
            try checked(posix_spawn_file_actions_adddup2(&actions, error, STDERR_FILENO))
            if #available(macOS 26, *) {
                try checked(posix_spawn_file_actions_addchdir(&actions, directory))
            } else {
                try checked(posix_spawn_file_actions_addchdir_np(&actions, directory))
            }
            try checked(posix_spawnattr_setpgroup(&attributes, 0))
            try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
            let argv = ([executable] + arguments).map { strdup($0) } + [nil]
            let env = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer { argv.forEach { free($0) }; env.forEach { free($0) } }
            var child: pid_t = 0
            let result = argv.withUnsafeBufferPointer { args in
                env.withUnsafeBufferPointer { environment in
                    posix_spawn(&child, executable, &actions, &attributes, args.baseAddress!, environment.baseAddress!)
                }
            }
            try checked(result)
            pid = child
            return child
        }

        func stop(_ reason: StopReason) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished, self.reason == nil else { return }
            self.reason = reason
            if let pid { kill(-pid, SIGKILL) }
        }

        func finish(status: inout Int32) throws {
            lock.lock()
            defer { lock.unlock() }
            if let pid {
                var result: pid_t
                repeat { result = waitpid(pid, &status, 0) } while result == -1 && errno == EINTR
            }
            finished = true
            pid = nil
            switch reason {
            case .cancelled: throw CancellationError()
            case .timeout: throw ReadCommandError(message: "La commande n’a pas répondu à temps. L’opération a été interrompue.")
            case .outputLimit: throw ReadCommandError(message: "La sortie dépasse la limite d’affichage. L’opération a été interrompue.")
            case .waitFailure: throw ReadCommandError(message: "Impossible de suivre la commande. L’opération a été interrompue.")
            case nil: break
            }
        }

        private func checked(_ result: Int32) throws {
            if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        }
    }
}
