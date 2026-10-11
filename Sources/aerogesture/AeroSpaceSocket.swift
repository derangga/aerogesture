import Foundation

// AeroSpace 0.21+ socket wire protocol: version handshake + length-prefixed frames.
// Must match SOCKET_PROTOCOL_VERSION in AeroSpace/Sources/Common/model/clientServer.swift.
private let SOCKET_PROTOCOL_VERSION: UInt32 = 1
private let maxFrameLength: UInt32 = 1_048_576

enum SwipeError: Error {
    case socketError(String)
    case commandFail(String)
    case timeout
}

struct ClientRequest: Codable {
    enum CodingKeys: String, CodingKey { case command, args, stdin, windowId, workspace }

    let command: String
    let args: [String]
    let stdin: String
    let windowId: UInt32?
    let workspace: String?

    init(args: [String], stdin: String = "") {
        self.command = ""
        self.args = args
        self.stdin = stdin
        self.windowId = nil
        self.workspace = nil
    }

    // AeroSpace rejects a request that lacks these keys, so send explicit nulls.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(command, forKey: .command)
        try c.encode(args, forKey: .args)
        try c.encode(stdin, forKey: .stdin)
        try c.encode(windowId, forKey: .windowId)
        try c.encode(workspace, forKey: .workspace)
    }
}

struct ServerAnswer: Codable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let serverVersionAndHash: String
}

final class AeroSpaceSocket {
    private var fd: Int32 = -1
    private let socketPath: String
    private let queue = DispatchQueue(label: "aerogesture.ipc", qos: .userInteractive)
    private let inFlight = DispatchSemaphore(value: 1)

    init() {
        self.socketPath = "/tmp/bobko.aerospace-\(NSUserName()).sock"
    }

    func connect() {
        if fd >= 0 {
            Darwin.close(fd)
        }
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("aerogesture: failed to create socket\n", stderr)
            return
        }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, size)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, size)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let bound = sunPath.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    strlcpy(dest, ptr, 104)
                }
                _ = bound
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result < 0 {
            fputs("aerogesture: failed to connect to AeroSpace at \(socketPath): \(String(cString: strerror(errno)))\n", stderr)
            Darwin.close(fd)
            fd = -1
            return
        }

        // Protocol handshake: send our version, server replies with its version.
        guard (try? writeUInt32(SOCKET_PROTOCOL_VERSION)) != nil,
              let serverVersion = try? readUInt32(),
              serverVersion == SOCKET_PROTOCOL_VERSION else {
            fputs("aerogesture: AeroSpace socket handshake failed (protocol version mismatch — restart AeroSpace?)\n", stderr)
            Darwin.close(fd)
            fd = -1
            return
        }
    }

    // MARK: - Framing primitives (little-endian length prefix, native byte order)

    private func ioError(_ what: String) -> SwipeError {
        errno == EAGAIN || errno == EWOULDBLOCK ? .timeout : .socketError("\(what): \(String(cString: strerror(errno)))")
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return } // empty payload
            var total = 0
            while total < data.count {
                let n = Darwin.write(fd, base + total, data.count - total)
                if n <= 0 { throw ioError("write failed") }
                total += n
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        if count == 0 { return Data() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: count)
        while data.count < count {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, count - data.count) }
            if n <= 0 { throw n == 0 ? SwipeError.socketError("connection closed") : ioError("read failed") }
            data.append(contentsOf: buf[0..<n])
        }
        return data
    }

    private func writeUInt32(_ value: UInt32) throws {
        var v = value
        try withUnsafeBytes(of: &v) { try writeAll(Data($0)) }
    }

    private func readUInt32() throws -> UInt32 {
        try readExactly(4).withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    /// Safe to call from any thread. Blocks until the IPC queue has closed the socket.
    func disconnect() {
        queue.sync { closeSocket() }
    }

    private func closeSocket() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    @discardableResult
    func runCommand(_ args: [String], stdin: String = "") -> Result<String, SwipeError> {
        let payload: Data
        do {
            payload = try JSONEncoder().encode(ClientRequest(args: args, stdin: stdin))
        } catch {
            return .failure(.socketError(error.localizedDescription))
        }

        // Write request: UInt32 length prefix + JSON payload. A failed write means
        // AeroSpace never got a full frame, so one reconnect and resend is safe.
        var written = false
        for attempt in 0..<2 where !written {
            if fd < 0 {
                if attempt == 0 { fputs("aerogesture: not connected, attempting to connect...\n", stderr) }
                connect()
            }
            guard fd >= 0 else { return .failure(.socketError("Not connected")) }
            do {
                try writeUInt32(UInt32(payload.count))
                try writeAll(payload)
                written = true
            } catch SwipeError.timeout {
                closeSocket()
                return .failure(.timeout)
            } catch {
                fputs("aerogesture: socket error, reconnecting...\n", stderr)
                closeSocket()
            }
        }
        guard written else { return .failure(.socketError("write failed after reconnect")) }

        // Read response: UInt32 length prefix + JSON payload. The command may already have
        // run, so any failure here closes the socket and does not resend.
        do {
            let len = try readUInt32()
            guard len <= maxFrameLength else {
                throw SwipeError.socketError("reply frame too large (\(len) bytes)")
            }
            let answer = try JSONDecoder().decode(ServerAnswer.self, from: try readExactly(Int(len)))
            if answer.exitCode != 0 {
                return .failure(.commandFail(answer.stderr))
            }
            return .success(answer.stdout)
        } catch let error as SwipeError {
            closeSocket()
            return .failure(error)
        } catch {
            closeSocket()
            return .failure(.socketError(error.localizedDescription))
        }
    }

    /// Queue a workspace switch on the IPC queue. Drops it if one is already running.
    func requestSwitch(direction: Direction, config: WorkspaceConfig) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        queue.async {
            defer { self.inFlight.signal() }
            self.switchWorkspace(direction: direction, config: config)
        }
    }

    private func switchWorkspace(direction: Direction, config: WorkspaceConfig) {
        // Focus the workspace under the cursor first
        if let mouseWs = try? runCommand(["list-workspaces", "--monitor", "mouse", "--visible"]).get() {
            let trimmed = mouseWs.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                runCommand(["workspace", trimmed])
            }
        }

        var nonEmpty: String?
        if config.skipEmpty {
            nonEmpty = try? runCommand(["list-workspaces", "--monitor", "focused", "--empty", "no"]).get()
        }
        let (args, stdin) = AeroSpaceSocket.switchArgs(direction: direction, config: config, nonEmptyWorkspaces: nonEmpty)
        if case .failure(let err) = runCommand(args, stdin: stdin) {
            // Swiping past the last workspace is normal, not an error
            if case .commandFail(let msg) = err, msg.contains("of the supplied workspaces list") { return }
            fputs("aerogesture: workspace switch failed: \(err)\n", stderr)
        }
    }

    static func switchArgs(
        direction: Direction,
        config: WorkspaceConfig,
        nonEmptyWorkspaces: String?
    ) -> (args: [String], stdin: String) {
        var args = ["workspace", direction.value]
        var stdin = ""
        if config.wrapAround {
            args.append("--wrap-around")
        }
        if config.skipEmpty, let ws = nonEmptyWorkspaces, !ws.isEmpty {
            stdin = ws
            args.append("--stdin")
        }
        return (args, stdin)
    }
}
