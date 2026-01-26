//
// MD4.swift
//
// MD4 hash implementation for NTLM authentication.
//
// Port of MailKit's MD4.cs (originally from Mono.Security)
// MD4 is required for NTLM password hashing and is not available in CryptoKit.
//

import Foundation

/// MD4 hash implementation.
///
/// This is a pure Swift implementation of the MD4 hash algorithm as specified
/// in RFC 1320. MD4 is required for NTLM authentication but is not available
/// in modern crypto libraries due to its known weaknesses.
///
/// - Warning: MD4 is cryptographically broken and should only be used for
///   legacy protocol compatibility (like NTLM).
public final class MD4: @unchecked Sendable {
    // Shift amounts for each round
    private static let s11: UInt32 = 3
    private static let s12: UInt32 = 7
    private static let s13: UInt32 = 11
    private static let s14: UInt32 = 19
    private static let s21: UInt32 = 3
    private static let s22: UInt32 = 5
    private static let s23: UInt32 = 9
    private static let s24: UInt32 = 13
    private static let s31: UInt32 = 3
    private static let s32: UInt32 = 9
    private static let s33: UInt32 = 11
    private static let s34: UInt32 = 15

    private var state: [UInt32] = [0, 0, 0, 0]
    private var count: [UInt32] = [0, 0]
    private var buffer: [UInt8] = Array(repeating: 0, count: 64)
    private var x: [UInt32] = Array(repeating: 0, count: 16)

    /// Creates a new MD4 hash instance.
    public init() {
        initialize()
    }

    /// Resets the hash state to initial values.
    public func initialize() {
        count[0] = 0
        count[1] = 0
        state[0] = 0x6745_2301
        state[1] = 0xEFCD_AB89
        state[2] = 0x98BA_DCFE
        state[3] = 0x1032_5476
        buffer = Array(repeating: 0, count: 64)
        x = Array(repeating: 0, count: 16)
    }

    /// Computes the MD4 hash of the given data.
    ///
    /// - Parameter data: The data to hash.
    /// - Returns: The 16-byte MD4 hash.
    public func computeHash(_ data: Data) -> Data {
        computeHash(Array(data))
    }

    /// Computes the MD4 hash of the given bytes.
    ///
    /// - Parameter bytes: The bytes to hash.
    /// - Returns: The 16-byte MD4 hash.
    public func computeHash(_ bytes: [UInt8]) -> Data {
        initialize()
        hashCore(bytes, offset: 0, count: bytes.count)
        return hashFinal()
    }

    // MARK: - Private Implementation

    private func hashCore(_ block: [UInt8], offset: Int, count: Int) {
        // Compute number of bytes mod 64
        var index = Int((self.count[0] >> 3) & 0x3F)

        // Update number of bits
        self.count[0] &+= UInt32(count << 3)
        if self.count[0] < UInt32(count << 3) {
            self.count[1] &+= 1
        }
        self.count[1] &+= UInt32(count >> 29)

        let partLen = 64 - index
        var i = 0

        // Transform as many times as possible
        if count >= partLen {
            for j in 0..<partLen {
                buffer[index + j] = block[offset + j]
            }
            md4Transform(buffer, index: 0)

            i = partLen
            while i + 63 < count {
                md4Transform(block, index: offset + i)
                i += 64
            }

            index = 0
        }

        // Buffer remaining input
        for j in 0..<(count - i) {
            buffer[index + j] = block[offset + i + j]
        }
    }

    private func hashFinal() -> Data {
        // Save number of bits
        var bits = [UInt8](repeating: 0, count: 8)
        encode(&bits, input: count, count: 8)

        // Pad out to 56 mod 64
        let index = Int((count[0] >> 3) & 0x3F)
        let padLen = (index < 56) ? (56 - index) : (120 - index)
        hashCore(padding(padLen), offset: 0, count: padLen)

        // Append length (before padding)
        hashCore(bits, offset: 0, count: 8)

        // Store state in digest
        var digest = [UInt8](repeating: 0, count: 16)
        encode(&digest, input: state, count: 16)

        return Data(digest)
    }

    private func padding(_ length: Int) -> [UInt8] {
        guard length > 0 else { return [] }
        var pad = [UInt8](repeating: 0, count: length)
        pad[0] = 0x80
        return pad
    }

    // Basic MD4 functions
    private static func f(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) | (~x & z)
    }

    private static func g(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) | (x & z) | (y & z)
    }

    private static func h(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        x ^ y ^ z
    }

    // Rotate left
    private static func rol(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    // Transformation functions for rounds 1, 2, and 3
    private static func ff(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32) {
        a &+= f(b, c, d) &+ x
        a = rol(a, s)
    }

    private static func gg(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32) {
        a &+= g(b, c, d) &+ x &+ 0x5A82_7999
        a = rol(a, s)
    }

    private static func hh(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32) {
        a &+= h(b, c, d) &+ x &+ 0x6ED9_EBA1
        a = rol(a, s)
    }

    private func encode(_ output: inout [UInt8], input: [UInt32], count: Int) {
        var j = 0
        for i in 0..<(count / 4) {
            output[j] = UInt8(input[i] & 0xFF)
            output[j + 1] = UInt8((input[i] >> 8) & 0xFF)
            output[j + 2] = UInt8((input[i] >> 16) & 0xFF)
            output[j + 3] = UInt8((input[i] >> 24) & 0xFF)
            j += 4
        }
    }

    private func decode(_ output: inout [UInt32], input: [UInt8], index: Int) {
        var j = index
        for i in 0..<output.count {
            output[i] =
                UInt32(input[j])
                | (UInt32(input[j + 1]) << 8)
                | (UInt32(input[j + 2]) << 16)
                | (UInt32(input[j + 3]) << 24)
            j += 4
        }
    }

    private func md4Transform(_ block: [UInt8], index: Int) {
        var a = state[0]
        var b = state[1]
        var c = state[2]
        var d = state[3]

        decode(&x, input: block, index: index)

        // Round 1
        MD4.ff(&a, b, c, d, x[0], MD4.s11)
        MD4.ff(&d, a, b, c, x[1], MD4.s12)
        MD4.ff(&c, d, a, b, x[2], MD4.s13)
        MD4.ff(&b, c, d, a, x[3], MD4.s14)
        MD4.ff(&a, b, c, d, x[4], MD4.s11)
        MD4.ff(&d, a, b, c, x[5], MD4.s12)
        MD4.ff(&c, d, a, b, x[6], MD4.s13)
        MD4.ff(&b, c, d, a, x[7], MD4.s14)
        MD4.ff(&a, b, c, d, x[8], MD4.s11)
        MD4.ff(&d, a, b, c, x[9], MD4.s12)
        MD4.ff(&c, d, a, b, x[10], MD4.s13)
        MD4.ff(&b, c, d, a, x[11], MD4.s14)
        MD4.ff(&a, b, c, d, x[12], MD4.s11)
        MD4.ff(&d, a, b, c, x[13], MD4.s12)
        MD4.ff(&c, d, a, b, x[14], MD4.s13)
        MD4.ff(&b, c, d, a, x[15], MD4.s14)

        // Round 2
        MD4.gg(&a, b, c, d, x[0], MD4.s21)
        MD4.gg(&d, a, b, c, x[4], MD4.s22)
        MD4.gg(&c, d, a, b, x[8], MD4.s23)
        MD4.gg(&b, c, d, a, x[12], MD4.s24)
        MD4.gg(&a, b, c, d, x[1], MD4.s21)
        MD4.gg(&d, a, b, c, x[5], MD4.s22)
        MD4.gg(&c, d, a, b, x[9], MD4.s23)
        MD4.gg(&b, c, d, a, x[13], MD4.s24)
        MD4.gg(&a, b, c, d, x[2], MD4.s21)
        MD4.gg(&d, a, b, c, x[6], MD4.s22)
        MD4.gg(&c, d, a, b, x[10], MD4.s23)
        MD4.gg(&b, c, d, a, x[14], MD4.s24)
        MD4.gg(&a, b, c, d, x[3], MD4.s21)
        MD4.gg(&d, a, b, c, x[7], MD4.s22)
        MD4.gg(&c, d, a, b, x[11], MD4.s23)
        MD4.gg(&b, c, d, a, x[15], MD4.s24)

        // Round 3
        MD4.hh(&a, b, c, d, x[0], MD4.s31)
        MD4.hh(&d, a, b, c, x[8], MD4.s32)
        MD4.hh(&c, d, a, b, x[4], MD4.s33)
        MD4.hh(&b, c, d, a, x[12], MD4.s34)
        MD4.hh(&a, b, c, d, x[2], MD4.s31)
        MD4.hh(&d, a, b, c, x[10], MD4.s32)
        MD4.hh(&c, d, a, b, x[6], MD4.s33)
        MD4.hh(&b, c, d, a, x[14], MD4.s34)
        MD4.hh(&a, b, c, d, x[1], MD4.s31)
        MD4.hh(&d, a, b, c, x[9], MD4.s32)
        MD4.hh(&c, d, a, b, x[5], MD4.s33)
        MD4.hh(&b, c, d, a, x[13], MD4.s34)
        MD4.hh(&a, b, c, d, x[3], MD4.s31)
        MD4.hh(&d, a, b, c, x[11], MD4.s32)
        MD4.hh(&c, d, a, b, x[7], MD4.s33)
        MD4.hh(&b, c, d, a, x[15], MD4.s34)

        state[0] &+= a
        state[1] &+= b
        state[2] &+= c
        state[3] &+= d
    }
}
