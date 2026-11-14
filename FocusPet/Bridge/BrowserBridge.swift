import Foundation

/// Unix-socket server that FocusPetBridge helpers (one per browser) connect to. Messages are one
/// JSON object per line, protocol v1 — see docs/browser-extension.md. Outgoing messages are
/// broadcast; each extension decides for itself whether one of its tabs is the target.
@MainActor
final class BrowserBridge {
    static let protocolVersion = 1

    private let socketPath: String
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]

    private final class Client {
        let source: DispatchSourceRead
        var buffer = Data()
        var browser = "unknown"
        init(source: DispatchSourceRead) { self.source = source }
    }

    var connectedBrowsers: [String] { clients.values.map(\.browser) }

    init(socketPath: String? = nil) {
        self.socketPath = socketPath ?? ProcessInfo.processInfo.environment["FOCUSPET_BRIDGE_SOCKET"]
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FocusPet/bridge.sock").path
    }

    func start() {
        guard listenFD < 0 else { return }
        try? FileManager.default.createDirectory(atPath: (socketPath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        unlink(socketPath)  // stale socket from a previous run

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = Self.address(for: socketPath) else {
            Log.bridge.error("bridge: could not create socket")
            return
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
        }
        guard bound, chmod(socketPath, 0o600) == 0, listen(fd, 8) == 0 else {
            Log.bridge.error("bridge: bind/listen failed on \(self.socketPath, privacy: .public): errno \(errno)")
            close(fd)
            return
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.acceptClients() } }
        source.resume()
        listenSource = source
        Log.bridge.info("bridge: listening on \(self.socketPath, privacy: .public)")
    }

    func stop() {
        for fd in Array(clients.keys) { disconnect(fd) }
        listenSource?.cancel(); listenSource = nil
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(socketPath)
    }

    func send(_ message: [String: Any]) {
        var payload = message
        payload["v"] = Self.protocolVersion
        guard var line = try? JSONSerialization.data(withJSONObject: payload) else { return }
        line.append(0x0A)
        Log.bridge.info("bridge → \(self.clients.count) client(s): \(message["type"] as? String ?? "?", privacy: .public)")
        for fd in Array(clients.keys) where !Self.writeAll(line, to: fd) {
            disconnect(fd)
        }
    }

    // MARK: - Connections

    private func acceptClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readClient(fd) } }
            clients[fd] = Client(source: source)
            source.resume()
            Log.bridge.info("bridge: helper connected (fd \(fd))")
        }
    }

    private func readClient(_ fd: Int32) {
        guard let client = clients[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let n = read(fd, &chunk, chunk.count)
        guard n > 0 else { disconnect(fd); return }
        client.buffer.append(contentsOf: chunk[0..<n])
        for line in Self.takeLines(from: &client.buffer) {
            handle(line, from: client)
        }
    }

    private func disconnect(_ fd: Int32) {
        guard let client = clients.removeValue(forKey: fd) else { return }
        client.source.cancel()
        close(fd)
        Log.bridge.info("bridge: \(client.browser, privacy: .public) disconnected")
    }

    private func handle(_ line: Data, from client: Client) {
        guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              msg["v"] as? Int == Self.protocolVersion, let type = msg["type"] as? String else { return }
        switch type {
        case "hello":
            client.browser = msg["browser"] as? String ?? "unknown"
            Log.bridge.info("bridge: hello from \(client.browser, privacy: .public) extension \(msg["extensionVersion"] as? String ?? "?", privacy: .public)")
        case "ack":
            Log.bridge.info("bridge: \(client.browser, privacy: .public) ack \(msg["for"] as? String ?? "?", privacy: .public) ok=\(msg["ok"] as? Bool ?? false) \(msg["reason"] as? String ?? "", privacy: .public)")
        case "returnAnyway":
            Log.bridge.info("bridge: user chose Return anyway on \(msg["host"] as? String ?? "?", privacy: .public)")
        default:
            break
        }
    }

    // MARK: - Helpers

    /// Splits complete newline-terminated lines off the front of `buffer`.
    nonisolated static func takeLines(from buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buf in
            var offset = 0
            while offset < buf.count {
                let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    private static func address(for path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }
}
