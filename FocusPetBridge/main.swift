// FocusPetBridge — Native Messaging host for the FocusPet browser extension.
//
// The browser launches this helper and talks to it over stdio using Chrome's framing (4-byte
// little-endian length + UTF-8 JSON). The helper relays each message as one line of JSON over the
// running app's Unix socket, and frames the app's lines back to the browser. If the app isn't
// running it keeps retrying, replaying the extension's last `hello` whenever it (re)connects.
// It exits when the browser closes stdin.
import Foundation

let socketPath = ProcessInfo.processInfo.environment["FOCUSPET_BRIDGE_SOCKET"]
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FocusPet/bridge.sock").path
let maxMessageBytes = 1 << 20  // Chrome's limit for host → extension messages

signal(SIGPIPE, SIG_IGN)

final class Relay: @unchecked Sendable {  // all mutable state guarded by `lock`
    private let lock = NSLock()
    private var socketFD: Int32 = -1
    private var lastHello: Data?

    func setSocket(_ fd: Int32) {
        lock.lock(); socketFD = fd; let hello = lastHello; lock.unlock()
        if let hello { writeLine(hello, to: fd) }
    }

    func clearSocket() {
        lock.lock(); if socketFD >= 0 { close(socketFD) }; socketFD = -1; lock.unlock()
    }

    /// Browser → app. Messages sent while the app is down are dropped, except `hello`, which is replayed.
    func fromBrowser(_ json: Data) {
        let isHello = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["type"] as? String == "hello"
        lock.lock()
        if isHello { lastHello = json }
        let fd = socketFD
        lock.unlock()
        if fd >= 0 { writeLine(json, to: fd) }
    }

    private func writeLine(_ json: Data, to fd: Int32) {
        var line = json
        line.append(0x0A)
        line.withUnsafeBytes { buf in
            var offset = 0
            while offset < buf.count {
                let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n <= 0 { return }
                offset += n
            }
        }
    }
}

let stdoutLock = NSLock()

/// App → browser, framed for Native Messaging.
func toBrowser(_ json: Data) {
    guard json.count <= maxMessageBytes else { return }
    var length = UInt32(json.count).littleEndian
    stdoutLock.lock(); defer { stdoutLock.unlock() }
    let out = FileHandle.standardOutput
    out.write(Data(bytes: &length, count: 4))
    out.write(json)
}

func toBrowser(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object) { toBrowser(data) }
}

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        let chunk = FileHandle.standardInput.readData(ofLength: count - data.count)
        if chunk.isEmpty { return nil }  // EOF: the browser closed the port
        data.append(chunk)
    }
    return data
}

func connectToApp() -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        raw.copyBytes(from: pathBytes)
        raw[pathBytes.count] = 0
    }
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
        }
    }
    if !ok { close(fd); return nil }
    return fd
}

let relay = Relay()

// App side: connect (retrying), then pump lines from the app to the browser.
Thread.detachNewThread {
    var announcedUnavailable = false
    while true {
        guard let fd = connectToApp() else {
            if !announcedUnavailable { toBrowser(["v": 1, "type": "appUnavailable"]); announcedUnavailable = true }
            Thread.sleep(forTimeInterval: 2)
            continue
        }
        announcedUnavailable = false
        toBrowser(["v": 1, "type": "connected"])
        relay.setSocket(fd)

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.isEmpty { toBrowser(Data(line)) }
            }
        }
        relay.clearSocket()
    }
}

// Browser side: read frames until stdin closes.
while let header = readExactly(4) {
    let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
    guard length > 0, length <= 64 << 20, let body = readExactly(length) else { break }
    relay.fromBrowser(body)
}
exit(0)
