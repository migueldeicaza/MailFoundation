//
// TlsChannelBinding.swift
//
// TLS channel binding helpers.
//

import Foundation

#if canImport(Security)
import Security
#endif

#if canImport(CryptoKit)
import CryptoKit
#endif

enum TlsChannelBindingHelper {
    static func tlsServerEndPoint(from outputStream: Stream) -> ScramChannelBinding? {
        #if canImport(Security)
        let trustKey = Stream.PropertyKey(kCFStreamPropertySSLPeerTrust as String)
        guard let trustValue = outputStream.property(forKey: trustKey) else {
            return nil
        }
        let trust = trustValue as! SecTrust

        let first: SecCertificate?
        if #available(macOS 12.0, iOS 15.0, *) {
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
                return nil
            }
            first = chain.first
        } else {
            first = SecTrustGetCertificateAtIndex(trust, 0)
        }

        guard let first else {
            return nil
        }

        return tlsServerEndPoint(from: first)
        #else
        return nil
        #endif
    }

    static func tlsServerEndPoint(from certificate: SecCertificate) -> ScramChannelBinding? {
        #if canImport(Security) && canImport(CryptoKit)
        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
        return ScramChannelBinding.tlsServerEndPoint(Data(digest))
        #else
        return nil
        #endif
    }
}
