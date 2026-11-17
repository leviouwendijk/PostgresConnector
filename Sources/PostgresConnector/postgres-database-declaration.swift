import Foundation
import Milieu
import NIOSSL

/// A database the connector should serve. Its configuration (credentials,
/// TLS) is resolved when the connector is created, one declaration at a time,
/// so a database that cannot be configured is recorded as unavailable instead
/// of failing every other database with it.
public struct PostgresDatabaseDeclaration {
    public enum Requirement: Sendable, Equatable {
        /// The connector refuses to start without it.
        case required

        /// Recorded as unavailable when it cannot be configured; queries
        /// against it throw `PostgresConnectorError.databaseUnavailable`.
        case optional
    }

    public let id: PostgresDatabaseIdentifier
    public let requirement: Requirement

    let resolve: () throws -> PostgresDatabase

    public init(
        id: PostgresDatabaseIdentifier,
        requirement: Requirement = .required,
        resolve: @escaping () throws -> PostgresDatabase
    ) {
        self.id = id
        self.requirement = requirement
        self.resolve = resolve
    }

    /// An already configured database.
    public init(
        _ database: PostgresDatabase,
        requirement: Requirement = .required
    ) {
        self.init(id: database.id, requirement: requirement) { database }
    }

    /// A database configured from environment keys, resolved when the
    /// connector is created.
    public static func environment<HostKey, UserKey, PasswordKey, CAKey>(
        id: PostgresDatabaseIdentifier,
        requirement: Requirement = .required,
        host: HostKey,
        port: Int = 5432,
        username: UserKey,
        password: PasswordKey,
        database: String,
        caCert: CAKey,
        verification: CertificateVerification = .noHostnameVerification
    ) -> Self
        where
        HostKey: EnvironmentExtractable,
        UserKey: EnvironmentExtractable,
        PasswordKey: EnvironmentExtractable,
        CAKey: EnvironmentExtractable
    {
        Self(id: id, requirement: requirement) {
            try PostgresDatabase(
                id: id,
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                caCert: caCert,
                verification: verification
            )
        }
    }
}

/// Whether a declared database can be queried.
public enum PostgresDatabaseStatus: Sendable, Equatable {
    case configured
    case unavailable(reason: String)
}

public struct PostgresDatabaseState: Sendable, Equatable {
    public let id: PostgresDatabaseIdentifier
    public let requirement: PostgresDatabaseDeclaration.Requirement
    public let status: PostgresDatabaseStatus
}

/// The result of probing one declared database with `SELECT 1`.
public struct PostgresDatabaseHealth: Sendable, Codable, Equatable {
    public enum State: String, Sendable, Codable {
        /// Configured and answered `SELECT 1`.
        case ready

        /// Configured, but the probe failed or timed out.
        case unreachable

        /// Could not be configured when the connector was created.
        case unconfigured
    }

    public let id: String
    public let required: Bool
    public let state: State
    public let latencyMilliseconds: Int?
    public let detail: String?

    public var isHealthy: Bool {
        state == .ready
    }
}
