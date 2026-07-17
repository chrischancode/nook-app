//
//  OpencodeCommandSocket.swift
//  Nook
//
//  Client for /tmp/nook-command.sock — sends commands to the opencode plugin.
//
//  The plugin (Resources/opencode-plugin/index.js) listens on this Unix domain
//  socket for JSON commands from Nook. The primary use case is replying to
//  permission prompts: opencode emits `permission.asked` with a request id
//  (e.g. "per_xxx"), and Nook sends back `permission.reply` with "once",
//  "always", or "reject" so the in-process client can resume the tool call.
//

import Foundation

final class OpencodeCommandSocket: @unchecked Sendable {
    static let shared = OpencodeCommandSocket()
    private init() {}

    static let socketPath = "/tmp/nook-command.sock"

    /// Send a JSON command to the opencode plugin. The write is fire-and-
    /// forget: if the plugin isn't connected or the socket is missing, the
    /// command is silently dropped. Commands are serialized on a background
    /// queue so the caller (always the MainActor SessionMonitor) never blocks.
    func sendCommand(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.connectAndWrite(data)
        }
    }

    private func connectAndWrite(_ data: Data) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Self.socketPath
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            // Copy the path bytes (excluding null terminator) into sun_path.
            // sockaddr_un already zero-pads sun_path.
            let pathBytes = path.utf8CString
            let count = min(pathBytes.count - 1, buf.count)
            pathBytes.withUnsafeBufferPointer { src in
                buf.copyMemory(from: UnsafeRawBufferPointer(start: src.baseAddress, count: count))
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { return }

        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            _ = write(fd, base, data.count)
        }
        // Half-close write side so plugin's socket.on("end") fires immediately
        shutdown(fd, Int32(SHUT_WR))
    }
}
