import Foundation
import NIOCore
import PostgresKit
import PSQL

public enum PostgresTransactionIsolation:
    String,
    Sendable,
    Hashable,
    Codable
{
    case readCommitted
    case repeatableRead
    case serializable

    internal var sql: String {
        switch self {
        case .readCommitted:
            return "READ COMMITTED"

        case .repeatableRead:
            return "REPEATABLE READ"

        case .serializable:
            return "SERIALIZABLE"
        }
    }
}

public enum PostgresTransactionAccessMode:
    String,
    Sendable,
    Hashable,
    Codable
{
    case readWrite
    case readOnly

    internal var sql: String {
        switch self {
        case .readWrite:
            return "READ WRITE"

        case .readOnly:
            return "READ ONLY"
        }
    }
}

public struct PostgresTransactionOptions:
    Sendable,
    Hashable,
    Codable
{
    public let isolation: PostgresTransactionIsolation
    public let accessMode: PostgresTransactionAccessMode

    public init(
        isolation: PostgresTransactionIsolation = .readCommitted,
        accessMode: PostgresTransactionAccessMode = .readWrite
    ) {
        self.isolation = isolation
        self.accessMode = accessMode
    }

    internal var beginStatement: String {
        """
        BEGIN TRANSACTION \
        ISOLATION LEVEL \(isolation.sql), \
        \(accessMode.sql)
        """
    }
}

public enum PostgresTransactionError:
    Error,
    LocalizedError,
    Sendable,
    Equatable
{
    case closed
    case concurrentOperation

    case rollbackFailed(
        operation: String,
        rollback: String
    )

    public var errorDescription: String? {
        switch self {
        case .closed:
            return "The PostgreSQL transaction is no longer active."

        case .concurrentOperation:
            return """
            Another operation is already running on this PostgreSQL \
            transaction.
            """

        case .rollbackFailed(
            let operation,
            let rollback
        ):
            return """
            The transaction failed and its rollback also failed. \
            Operation failure: \(operation). \
            Rollback failure: \(rollback).
            """
        }
    }
}

public actor PostgresTransaction {
    private let connection: PostgresConnection

    private var isOpen = true
    private var operationInFlight = false

    internal init(
        connection: PostgresConnection
    ) {
        self.connection = connection
    }

    public func rows(
        for query: PostgresPreparedQuery
    ) async throws -> [PostgresRow] {
        try beginOperation()

        do {
            let rows = try await connection
                .query(
                    query.sql,
                    query.binds
                )
                .map(\.rows)
                .get()

            finishOperation()

            return rows
        } catch {
            finishOperation()

            throw error
        }
    }

    public func rows(
        for renderedSQL: PSQL.RenderedSQL
    ) async throws -> [PostgresRow] {
        try await rows(
            for: .init(
                renderedSQL
            )
        )
    }

    public func rows(
        sql: String,
        binds: [PostgresData] = []
    ) async throws -> [PostgresRow] {
        try await rows(
            for: .init(
                sql: sql,
                binds: binds
            )
        )
    }

    public func run(
        _ query: PostgresPreparedQuery
    ) async throws {
        try beginOperation()

        do {
            _ = try await connection
                .query(
                    query.sql,
                    query.binds
                )
                .get()

            finishOperation()
        } catch {
            finishOperation()

            throw error
        }
    }

    public func run(
        _ renderedSQL: PSQL.RenderedSQL
    ) async throws {
        try await run(
            .init(
                renderedSQL
            )
        )
    }

    public func run(
        sql: String,
        binds: [PostgresData] = []
    ) async throws {
        try await run(
            .init(
                sql: sql,
                binds: binds
            )
        )
    }

    internal func begin(
        options: PostgresTransactionOptions
    ) async throws {
        try await run(
            sql: options.beginStatement
        )
    }

    internal func commit() async throws {
        try await run(
            sql: "COMMIT"
        )
    }

    internal func rollback() async throws {
        try await run(
            sql: "ROLLBACK"
        )
    }

    internal func close() {
        isOpen = false
    }

    private func beginOperation() throws {
        guard isOpen else {
            throw PostgresTransactionError.closed
        }

        guard !operationInFlight else {
            throw PostgresTransactionError.concurrentOperation
        }

        operationInFlight = true
    }

    private func finishOperation() {
        operationInFlight = false
    }
}
