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
    public static func make(
        host: String,
        port: Int,
        backend: TransportBackend,
        proxy: ProxySettings? = nil
    ) throws -> Transport {
        if let proxy {
            let transport = try makeDirect(host: proxy.host, port: proxy.port, backend: backend)
            transport.open()
            let client = ProxyClientFactory.make(transport: transport, settings: proxy)
            do {
                try client.connect(to: host, port: port)
            } catch {
                transport.close()
                throw error
            }
            return transport
        }
        return try makeDirect(host: host, port: port, backend: backend)
    }

    private static func makeDirect(host: String, port: Int, backend: TransportBackend) throws -> Transport {
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
