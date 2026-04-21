import Foundation
import NIOSSL
import PostgresKit

public struct PostgresDatabase: Sendable {
    public struct TLS: Sendable {
        public let caFile: String?
        public let verification: CertificateVerification

        public init(
            caFile: String?,
            verification: CertificateVerification = .noHostnameVerification
        ) {
            self.caFile = caFile
            self.verification = verification
        }

        public static func requireCAFile(
            _ path: String,
            verification: CertificateVerification = .noHostnameVerification
        ) -> Self {
            return .init(
                caFile: path,
                verification: verification
            )
        }

        public static var disabled: Self {
            return .init(caFile: nil)
        }
    }

    public let id: PostgresDatabaseIdentifier
    public let host: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String
    public let tls: TLS

    public init(
        id: PostgresDatabaseIdentifier,
        host: String,
        port: Int = 5432,
        username: String,
        password: String,
        database: String,
        tls: TLS
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.tls = tls
    }

    public func makeSQLConfiguration() throws -> SQLPostgresConfiguration {
        if let caFile = tls.caFile {
            let sslContext = try Self.makeSSLContext(
                caFile: caFile,
                verification: tls.verification
            )

            return SQLPostgresConfiguration(
                hostname: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tls: .require(sslContext)
            )
        }

        return SQLPostgresConfiguration(
            hostname: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
    }

    private static func makeSSLContext(
        caFile: String,
        verification: CertificateVerification
    ) throws -> NIOSSLContext {
        var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
        tlsConfiguration.certificateVerification = verification
        tlsConfiguration.trustRoots = .file(caFile)

        return try NIOSSLContext(configuration: tlsConfiguration)
    }
}
