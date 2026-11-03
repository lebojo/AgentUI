import Foundation
import Darwin
import os

enum CommandRunner {
    enum OutputOverflow: Sendable {
        case stop, discard, truncate
    }

    private static let registry = Registry()
    private static let diagnosticLimit = 65_536
    private static let diagnosticTail = 16_384
    private static let terminationGrace: DispatchTimeInterval = .seconds(2)

    static func terminateAll(within grace: Duration = .milliseconds(500)) { registry.terminateAll(within: grace) }

    struct Output: Sendable {
        let data: Data
        let isTruncated: Bool
    }

    enum ExitStatus: Equatable, Sendable {
        case exited(Int32)
        case signalled(Int32)

        init(waitStatus: Int32) {
            let signal = waitStatus & 0x7f
            self = signal == 0 ? .exited((waitStatus >> 8) & 0xff) : .signalled(signal)
        }

        var exitCode: Int32? {
            if case .exited(let code) = self { code } else { nil }
        }

        var failureMessage: String {
            switch self {
            case .exited(let code): String(localized: "The command failed (exit code \(code)).")
            case .signalled(let signal): String(localized: "The command was interrupted by signal \(signal) (\(String(cString: strsignal(signal)))).")
            }
        }
    }

    static func run(_ executable: URL, _ arguments: [String], at path: String,
                    timeout: TimeInterval, limit: Int, readOnly: Bool, overflow: OutputOverflow = .stop,
                    gitConfiguration: [String: String] = [:]) async throws -> Data {
        try await output(executable, arguments, at: path, timeout: timeout, limit: limit, readOnly: readOnly,
                         overflow: overflow, gitConfiguration: gitConfiguration).data
    }

    static func output(_ executable: URL, _ arguments: [String], at path: String,
                       timeout: TimeInterval, limit: Int, readOnly: Bool, overflow: OutputOverflow = .stop,
                       gitConfiguration: [String: String] = [:]) async throws -> Output {
        let job = Job()
        let id = UUID()
        registry.add(job, id: id)
        defer { registry.remove(id) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await execute(job, executable: executable, arguments: arguments, at: path, timeout: timeout, limit: limit,
                                     readOnly: readOnly, overflow: overflow, gitConfiguration: gitConfiguration)
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
                                            timeout: TimeInterval, limit: Int, readOnly: Bool, overflow: OutputOverflow,
                                            gitConfiguration: [String: String]) async throws -> Output {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("heka-command-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout"), errURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forUpdating: outURL), error = try FileHandle(forUpdating: errURL)
        defer { try? output.close(); try? error.close() }
        _ = fcntl(output.fileDescriptor, F_SETFL, O_APPEND)
        _ = fcntl(error.fileDescriptor, F_SETFL, O_APPEND)
        let pid = try job.start(executable: executable.path, arguments: arguments,
                                environment: environment(readOnly: readOnly, gitConfiguration: gitConfiguration),
                                directory: path, output: output.fileDescriptor, error: error.fileDescriptor)
        let queue = DispatchQueue(label: "Heka.command", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let deadline = DispatchTime.now() + timeout
        let outFD = output.fileDescriptor, errFD = error.fileDescriptor, diagnosticLimit = Self.diagnosticLimit
        let outStart = OSAllocatedUnfairLock<off_t>(initialState: 0), errStart = OSAllocatedUnfairLock<off_t>(initialState: 0)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
        timer.setEventHandler {
            job.killIfStillRunning(after: terminationGrace)
            var outStat = stat(), errStat = stat()
            let outOverflows = fstat(outFD, &outStat) == 0 && outStat.st_size > limit
            let errOverflows = fstat(errFD, &errStat) == 0 && errStat.st_size > diagnosticLimit
            if overflow == .discard {
                let outSize = outStat.st_size, errSize = errStat.st_size
                outStart.withLock { $0 = discardHead(of: outFD, size: outSize, keptFrom: $0) }
                errStart.withLock { $0 = discardHead(of: errFD, size: errSize, keptFrom: $0) }
            } else if overflow == .truncate, outOverflows {
                return job.stop(.truncated)
            } else if outOverflows || errOverflows {
                return job.stop(.outputLimit)
            }
            if DispatchTime.now() >= deadline { job.stop(.timeout) }
        }
        timer.resume()
        if await !waitForExit(of: pid, on: queue) { job.stop(.waitFailure) }
        timer.cancel()
        queue.sync {}
        var status: Int32 = 0
        let isTruncated = try job.finish(status: &status)
        let reader = try FileHandle(forReadingFrom: outURL)
        defer { try? reader.close() }
        try reader.seek(toOffset: UInt64(outStart.withLock { $0 }))
        let data = try reader.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit || overflow != .stop else { throw ReadCommandError(message: String(localized: "The output exceeds the display limit. Open this content in your editor.")) }
        guard status == 0 || isTruncated else {
            let errors = try diagnostic(at: errURL, fromEnd: overflow == .discard)
            let diagnostic = errors.isEmpty ? try diagnostic(at: outURL, fromEnd: true) : errors
            throw ReadCommandError(message: diagnostic.isEmpty ? ExitStatus(waitStatus: status).failureMessage : diagnostic)
        }
        let exceedsLimit = data.count > limit
        return Output(data: exceedsLimit ? Data(data.prefix(limit)) : data, isTruncated: isTruncated || exceedsLimit)
    }

    private static func diagnostic(at url: URL, fromEnd: Bool) throws -> String {
        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        if fromEnd, let end = try? reader.seekToEnd(), end > 4096 { try reader.seek(toOffset: end - 4096) }
        else { try reader.seek(toOffset: 0) }
        return String(decoding: try reader.read(upToCount: 4096) ?? Data(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func discardHead(of descriptor: Int32, size: off_t, keptFrom start: off_t) -> off_t {
        var volume = statfs()
        guard size - start > diagnosticLimit, fstatfs(descriptor, &volume) == 0, volume.f_bsize > 0 else { return start }
        let block = off_t(volume.f_bsize)
        let end = (size - off_t(diagnosticTail)) / block * block
        var hole = fpunchhole_t(fp_flags: 0, reserved: 0, fp_offset: start, fp_length: end - start)
        return end > start && fcntl(descriptor, F_PUNCHHOLE, &hole) == 0 ? end : start
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

    private enum StopReason { case cancelled, quit, timeout, outputLimit, truncated, waitFailure }

    private final class Registry: Sendable {
        private let jobs = OSAllocatedUnfairLock<[UUID: Job]>(initialState: [:])
        func add(_ job: Job, id: UUID) { jobs.withLock { $0[id] = job } }
        func remove(_ id: UUID) { _ = jobs.withLock { $0.removeValue(forKey: id) } }
        func terminateAll(within grace: Duration) {
            let active = jobs.withLock { Array($0.values) }
            active.forEach { $0.stop(.quit) }
            let deadline = ContinuousClock.now + grace
            while active.contains(where: \.isRunning), ContinuousClock.now < deadline { usleep(10_000) }
            active.forEach { $0.forceStop() }
        }
    }

    private final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var pid: pid_t?
        private var reason: StopReason?
        private var stoppedAt: DispatchTime?
        private var killed = false
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
            var unblocked = sigset_t(), defaulted = sigset_t()
            sigemptyset(&unblocked)
            sigemptyset(&defaulted)
            [SIGTERM, SIGINT, SIGHUP, SIGQUIT].forEach { sigaddset(&defaulted, $0) }
            try checked(posix_spawnattr_setsigmask(&attributes, &unblocked))
            try checked(posix_spawnattr_setsigdefault(&attributes, &defaulted))
            try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
                                                                   | POSIX_SPAWN_CLOEXEC_DEFAULT)))
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
            guard !finished else { return }
            if self.reason == nil {
                self.reason = reason
                stoppedAt = .now()
                if let pid { kill(-pid, SIGTERM) }
            }
            if reason == .waitFailure { killGroup() }
        }

        var isRunning: Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !finished, let pid else { return false }
            return exitState(of: pid) == .running
        }

        func forceStop() {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            killGroup()
        }

        func killIfStillRunning(after grace: DispatchTimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished, let stoppedAt, DispatchTime.now() >= stoppedAt + grace else { return }
            killGroup()
        }

        private func killGroup() {
            guard !killed, let pid else { return }
            killed = true
            kill(-pid, SIGKILL)
        }

        func finish(status: inout Int32) throws -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if reason != nil { killGroup() }
            if let pid {
                var result: pid_t
                repeat { result = waitpid(pid, &status, 0) } while result == -1 && errno == EINTR
            }
            finished = true
            pid = nil
            switch reason {
            case .cancelled, .quit: throw CancellationError()
            case .timeout: throw ReadCommandError(message: String(localized: "The command didn’t respond in time. The operation was interrupted."))
            case .outputLimit: throw ReadCommandError(message: String(localized: "The output exceeds the display limit. The operation was interrupted."))
            case .waitFailure: throw ReadCommandError(message: String(localized: "Couldn’t follow the command. The operation was interrupted."))
            case .truncated: return true
            case nil: return false
            }
        }

        private func checked(_ result: Int32) throws {
            if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        }
    }
}
