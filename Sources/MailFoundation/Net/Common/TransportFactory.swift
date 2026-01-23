//
// TransportFactory.swift
//
// Synchronous transport factory helpers.
//

public enum TransportBackend: Sendable {
    case tcp
    case socket
}

public enum TransportFactoryError: Error, Sendable {
    case backendUnavailable
}

public enum TransportFactory {
    public static func make(host: String, port: Int, backend: TransportBackend) throws -> Transport {
        switch backend {
        case .tcp:
            return TcpTransport(host: host, port: port)
        case .socket:
            #if !os(iOS)
            return PosixSocketTransport(host: host, port: UInt16(port))
            #else
            throw TransportFactoryError.backendUnavailable
            #endif
        }
    }
}
