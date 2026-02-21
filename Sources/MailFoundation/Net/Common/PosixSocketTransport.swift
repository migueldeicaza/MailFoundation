//
// Author: Jeffrey Stedfast <jestedfa@microsoft.com>
//
// Copyright (c) 2013-2026 .NET Foundation and Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

//
// PosixSocketTransport.swift
//
// POSIX socket transport for non-iOS platforms.
//

#if !os(iOS)
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class PosixSocketTransport: Transport {
    private let host: String
    private let port: UInt16
    private let bufferSize: Int
    private var socketFD: Int32 = -1
    private var isOpen: Bool = false

    public init(host: String, port: UInt16, bufferSize: Int = 4096) {
        self.host = host
        self.port = port
        self.bufferSize = max(1, bufferSize)
    }

    public func open() {
        guard !isOpen else { return }
        socketFD = openSocket()
        isOpen = socketFD >= 0
    }

    public func close() {
        guard isOpen else { return }
        markDisconnected()
    }

    public var isConnected: Bool {
        isOpen && socketFD >= 0
    }

    public func write(_ bytes: [UInt8]) -> Int {
        guard isConnected, !bytes.isEmpty else { return 0 }
        var total = 0
        while total < bytes.count {
            let written = bytes.withUnsafeBytes { pointer -> Int in
                guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                #if canImport(Glibc)
                return Glibc.send(socketFD, base.advanced(by: total), bytes.count - total, Int32(MSG_NOSIGNAL))
                #else
                return Darwin.send(socketFD, base.advanced(by: total), bytes.count - total, 0)
                #endif
            }

            if written > 0 {
                total += written
                continue
            }

            if written == 0 {
                markDisconnected()
                break
            }

            #if canImport(Glibc)
            if errno == EINTR { continue }
            #elseif canImport(Darwin)
            if errno == EINTR { continue }
            #endif
            markDisconnected()
            break
        }
        return total
    }

    public func readAvailable(maxLength: Int = 4096) -> [UInt8] {
        guard isConnected else { return [] }
        let length = max(1, max(maxLength, bufferSize))
        var buffer = Array(repeating: UInt8(0), count: length)
        let bufferCount = buffer.count
        let count = buffer.withUnsafeMutableBytes { pointer -> Int in
            guard let base = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            #if canImport(Glibc)
            return Glibc.recv(socketFD, base, bufferCount, 0)
            #else
            return Darwin.recv(socketFD, base, bufferCount, 0)
            #endif
        }
        guard count > 0 else {
            if count == 0 {
                markDisconnected()
                return []
            }
            #if canImport(Glibc)
            if count < 0, (errno == EAGAIN || errno == EWOULDBLOCK) { return [] }
            #elseif canImport(Darwin)
            if count < 0, (errno == EAGAIN || errno == EWOULDBLOCK) { return [] }
            #endif
            markDisconnected()
            return []
        }
        return Array(buffer.prefix(count))
    }

    private func markDisconnected() {
        if socketFD >= 0 {
            #if canImport(Darwin)
            _ = Darwin.close(socketFD)
            #else
            _ = Glibc.close(socketFD)
            #endif
            socketFD = -1
        }
        isOpen = false
    }

    private func openSocket() -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var infoPointer: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        let status = getaddrinfo(host, portString, &hints, &infoPointer)
        guard status == 0, let firstInfo = infoPointer else {
            return -1
        }

        defer {
            freeaddrinfo(infoPointer)
        }

        var pointer: UnsafeMutablePointer<addrinfo>? = firstInfo
        while let info = pointer {
            let socketFD = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if socketFD < 0 {
                pointer = info.pointee.ai_next
                continue
            }

            #if canImport(Darwin)
            var noSigPipe: Int32 = 1
            _ = setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            #endif

            if connect(socketFD, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                #if canImport(Darwin)
                let flags = fcntl(socketFD, F_GETFL, 0)
                _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)
                #else
                let flags = fcntl(socketFD, F_GETFL, 0)
                _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)
                #endif
                return socketFD
            }

            #if canImport(Darwin)
            _ = Darwin.close(socketFD)
            #else
            _ = Glibc.close(socketFD)
            #endif
            pointer = info.pointee.ai_next
        }

        return -1
    }
}
#endif
