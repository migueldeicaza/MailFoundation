//
// RC4.swift
//
// RC4 stream cipher implementation for NTLM authentication.
//
// Port of MailKit's RC4.cs (originally ARC4Managed from Mono.Security)
// RC4 is required for NTLM session key encryption.
//

import Foundation

/// RC4 (Alleged RC4) stream cipher implementation.
///
/// This is a pure Swift implementation of the RC4 stream cipher. RC4 is required
/// for NTLM authentication session key encryption but is not available in modern
/// crypto libraries due to its known weaknesses.
///
/// - Warning: RC4 is cryptographically weak and should only be used for
///   legacy protocol compatibility (like NTLM).
public final class RC4: @unchecked Sendable {
    private var state: [UInt8] = Array(repeating: 0, count: 256)
    private var x: UInt8 = 0
    private var y: UInt8 = 0

    /// Creates a new RC4 cipher instance.
    public init() {}

    /// Creates a new RC4 cipher instance with the given key.
    ///
    /// - Parameter key: The encryption key.
    public convenience init(key: Data) {
        self.init()
        setKey(key)
    }

    /// Creates a new RC4 cipher instance with the given key.
    ///
    /// - Parameter key: The encryption key.
    public convenience init(key: [UInt8]) {
        self.init()
        setKey(key)
    }

    /// Sets the encryption key and initializes the cipher state.
    ///
    /// - Parameter key: The encryption key (must not be empty).
    public func setKey(_ key: Data) {
        setKey(Array(key))
    }

    /// Sets the encryption key and initializes the cipher state.
    ///
    /// - Parameter key: The encryption key (must not be empty).
    public func setKey(_ key: [UInt8]) {
        precondition(!key.isEmpty, "Key must not be empty")

        // Initialize state array
        for i in 0..<256 {
            state[i] = UInt8(i)
        }

        x = 0
        y = 0

        var index1: UInt8 = 0
        var index2: UInt8 = 0

        for counter in 0..<256 {
            index2 = key[Int(index1)] &+ state[counter] &+ index2

            // Swap
            let tmp = state[counter]
            state[counter] = state[Int(index2)]
            state[Int(index2)] = tmp

            index1 = (index1 + 1) % UInt8(key.count)
        }
    }

    /// Transforms (encrypts or decrypts) the given data.
    ///
    /// RC4 is a symmetric stream cipher, so encryption and decryption
    /// use the same operation.
    ///
    /// - Parameter data: The data to transform.
    /// - Returns: The transformed data.
    public func transform(_ data: Data) -> Data {
        Data(transform(Array(data)))
    }

    /// Transforms (encrypts or decrypts) the given bytes.
    ///
    /// RC4 is a symmetric stream cipher, so encryption and decryption
    /// use the same operation.
    ///
    /// - Parameter input: The bytes to transform.
    /// - Returns: The transformed bytes.
    public func transform(_ input: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count)

        for i in 0..<input.count {
            x = x &+ 1
            y = state[Int(x)] &+ y

            // Swap
            let tmp = state[Int(x)]
            state[Int(x)] = state[Int(y)]
            state[Int(y)] = tmp

            let xorIndex = state[Int(x)] &+ state[Int(y)]
            output[i] = input[i] ^ state[Int(xorIndex)]
        }

        return output
    }
}

// MARK: - Convenience Functions

extension RC4 {
    /// Encrypts or decrypts data using RC4 with the given key.
    ///
    /// - Parameters:
    ///   - key: The encryption key.
    ///   - message: The message to transform.
    /// - Returns: The transformed message.
    public static func transform(key: Data, message: Data) -> Data {
        let rc4 = RC4(key: key)
        return rc4.transform(message)
    }

    /// Encrypts or decrypts bytes using RC4 with the given key.
    ///
    /// - Parameters:
    ///   - key: The encryption key.
    ///   - message: The message to transform.
    /// - Returns: The transformed message.
    public static func transform(key: [UInt8], message: [UInt8]) -> [UInt8] {
        let rc4 = RC4(key: key)
        return rc4.transform(message)
    }
}
