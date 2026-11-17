import Foundation
import NIOCore
import NIOPosix
import PostgresKit
import PSQL

public actor PostgresConnector {
    private let eventLoopGroup: any EventLoopGroup
    private let ownsEventLoopGroup: Bool
    private let pools: [PostgresDatabaseIdentifier: EventLoopGroupConnectionPool<PostgresConnectionSource>]
    private let states: [PostgresDatabaseState]

    /// Every database is required: any configuration failure throws, as before.
    public init(
        databases: [PostgresDatabase],
        eventLoopGroup: any EventLoopGroup
    ) throws {
        try self.init(
            declarations: databases.map { PostgresDatabaseDeclaration($0) },
            eventLoopGroup: eventLoopGroup
        )
    }

    /// Every database is required: any configuration failure throws, as before.
    public init(
        databases: [PostgresDatabase],
        threadCount: Int = max(1, ProcessInfo.processInfo.activeProcessorCount)
    ) throws {
        try self.init(
            declarations: databases.map { PostgresDatabaseDeclaration($0) },
            threadCount: threadCount
        )
    }

    /// Configures each declaration independently. Optional databases that
    /// cannot be configured are recorded as unavailable; the initializer throws
    /// only when a required one fails (or an id is declared twice).
    public init(
        declarations: [PostgresDatabaseDeclaration],
        eventLoopGroup: any EventLoopGroup
    ) throws {
        let built = try Self.build(
            declarations: declarations,
            eventLoopGroup: eventLoopGroup
        )
        self.eventLoopGroup = eventLoopGroup
        self.ownsEventLoopGroup = false
        self.pools = built.pools
        self.states = built.states
    }

    /// Configures each declaration independently. Optional databases that
    /// cannot be configured are recorded as unavailable; the initializer throws
    /// only when a required one fails (or an id is declared twice).
    public init(
        declarations: [PostgresDatabaseDeclaration],
        threadCount: Int = max(1, ProcessInfo.processInfo.activeProcessorCount)
    ) throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)

        do {
            let built = try Self.build(
                declarations: declarations,
                eventLoopGroup: group
            )
            self.eventLoopGroup = group
            self.ownsEventLoopGroup = true
            self.pools = built.pools
            self.states = built.states
        } catch {
            try? group.syncShutdownGracefully()
            throw error
        }
    }

    public func rows(
        for query: PostgresPreparedQuery,
        on database: PostgresDatabaseIdentifier
    ) async throws -> [PostgresRow] {
        let pool = try self.pool(for: database)

        return try await withCheckedThrowingContinuation { continuation in
            pool.withConnection { connection in
                connection.query(query.sql, query.binds).map(\.rows)
            }.whenComplete { result in
                continuation.resume(with: result)
            }
        }
    }

    public func rows(
        for renderedSQL: PSQL.RenderedSQL,
        on database: PostgresDatabaseIdentifier
    ) async throws -> [PostgresRow] {
        return try await rows(
            for: .init(renderedSQL),
            on: database
        )
    }

    public func rows(
        sql: String,
        binds: [PostgresData] = [],
        on database: PostgresDatabaseIdentifier
    ) async throws -> [PostgresRow] {
        return try await rows(
            for: .init(sql: sql, binds: binds),
            on: database
        )
    }

    public func run(
        _ query: PostgresPreparedQuery,
        on database: PostgresDatabaseIdentifier
    ) async throws {
        let pool = try self.pool(for: database)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pool.withConnection { connection in
                connection.query(query.sql, query.binds)
            }.whenComplete { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func run(
        _ renderedSQL: PSQL.RenderedSQL,
        on database: PostgresDatabaseIdentifier
    ) async throws {
        try await run(
            .init(renderedSQL),
            on: database
        )
    }

    public func run(
        sql: String,
        binds: [PostgresData] = [],
        on database: PostgresDatabaseIdentifier
    ) async throws {
        try await run(
            .init(sql: sql, binds: binds),
            on: database
        )
    }

    public func transaction<Result: Sendable>(
        on database: PostgresDatabaseIdentifier,
        options: PostgresTransactionOptions = .init(),
        _ operation: @escaping @Sendable (
            PostgresTransaction
        ) async throws -> Result
    ) async throws -> Result {
        let pool = try self.pool(
            for: database
        )

        return try await pool
            .withConnection { connection in
                connection.eventLoop.makeFutureWithTask {
                    let transaction = PostgresTransaction(
                        connection: connection
                    )

                    do {
                        try Task.checkCancellation()

                        try await transaction.begin(
                            options: options
                        )
                    } catch {
                        await transaction.close()

                        throw error
                    }

                    do {
                        let result = try await operation(
                            transaction
                        )

                        try Task.checkCancellation()

                        try await transaction.commit()

                        await transaction.close()

                        return result
                    } catch {
                        let operationError = error

                        do {
                            try await transaction.rollback()
                        } catch {
                            let rollbackError = error

                            await transaction.close()

                            throw PostgresTransactionError
                                .rollbackFailed(
                                    operation: String(
                                        describing: operationError
                                    ),
                                    rollback: String(
                                        describing: rollbackError
                                    )
                                )
                        }

                        await transaction.close()

                        throw operationError
                    }
                }
            }
            .get()
    }

    /// Every declared database and whether it can be queried, in declaration order.
    public func databaseStates() -> [PostgresDatabaseState] {
        states
    }

    /// Probes every declared database with `SELECT 1`. Never throws: each
    /// database reports `ready`, `unreachable` (with the error) or `unconfigured`.
    public func health(
        timeoutSeconds: Double = 3
    ) async -> [PostgresDatabaseHealth] {
        var results: [PostgresDatabaseHealth] = []

        for state in states {
            let required = state.requirement == .required

            guard case .configured = state.status else {
                if case .unavailable(let reason) = state.status {
                    results.append(
                        PostgresDatabaseHealth(
                            id: state.id.rawValue,
                            required: required,
                            state: .unconfigured,
                            latencyMilliseconds: nil,
                            detail: reason
                        )
                    )
                }
                continue
            }

            let started = DispatchTime.now()

            do {
                try await probe(state.id, timeoutSeconds: timeoutSeconds)
                let elapsed = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds

                results.append(
                    PostgresDatabaseHealth(
                        id: state.id.rawValue,
                        required: required,
                        state: .ready,
                        latencyMilliseconds: Int(elapsed / 1_000_000),
                        detail: nil
                    )
                )
            } catch {
                results.append(
                    PostgresDatabaseHealth(
                        id: state.id.rawValue,
                        required: required,
                        state: .unreachable,
                        latencyMilliseconds: nil,
                        detail: String(describing: error)
                    )
                )
            }
        }

        return results
    }

    private func probe(
        _ database: PostgresDatabaseIdentifier,
        timeoutSeconds: Double
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await self.rows(sql: "SELECT 1", on: database)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw PostgresConnectorError.healthProbeTimedOut(id: database.rawValue, seconds: timeoutSeconds)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    public func registeredDatabaseIdentifiers() -> [PostgresDatabaseIdentifier] {
        return pools.keys.sorted {
            $0.rawValue < $1.rawValue
        }
    }

    public func shutdown() {
        for pool in pools.values {
            try? pool.syncShutdownGracefully()
        }

        if ownsEventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }

    private func pool(
        for database: PostgresDatabaseIdentifier
    ) throws -> EventLoopGroupConnectionPool<PostgresConnectionSource> {
        guard let pool = pools[database] else {
            if let state = states.first(where: { $0.id == database }),
               case .unavailable(let reason) = state.status
            {
                throw PostgresConnectorError.databaseUnavailable(id: database.rawValue, reason: reason)
            }
            throw PostgresConnectorError.databaseNotRegistered(database.rawValue)
        }
        return pool
    }

    private static func build(
        declarations: [PostgresDatabaseDeclaration],
        eventLoopGroup: any EventLoopGroup
    ) throws -> (
        pools: [PostgresDatabaseIdentifier: EventLoopGroupConnectionPool<PostgresConnectionSource>],
        states: [PostgresDatabaseState]
    ) {
        var seen: Set<PostgresDatabaseIdentifier> = []
        for declaration in declarations {
            guard seen.insert(declaration.id).inserted else {
                throw PostgresConnectorError.duplicateDatabaseIdentifier(declaration.id.rawValue)
            }
        }

        var pools: [PostgresDatabaseIdentifier: EventLoopGroupConnectionPool<PostgresConnectionSource>] = [:]
        var states: [PostgresDatabaseState] = []
        var missingRequired: [String] = []

        for declaration in declarations {
            do {
                let database = try declaration.resolve()
                guard database.id == declaration.id else {
                    throw PostgresConnectorError.databaseNotRegistered(
                        "declaration '\(declaration.id.rawValue)' resolved to '\(database.id.rawValue)'"
                    )
                }

                let sqlConfiguration = try database.make.sql_configuration()

                pools[declaration.id] = EventLoopGroupConnectionPool(
                    source: PostgresConnectionSource(sqlConfiguration: sqlConfiguration),
                    on: eventLoopGroup
                )
                states.append(
                    PostgresDatabaseState(id: declaration.id, requirement: declaration.requirement, status: .configured)
                )
            } catch {
                let reason = error.localizedDescription
                states.append(
                    PostgresDatabaseState(id: declaration.id, requirement: declaration.requirement, status: .unavailable(reason: reason))
                )
                if declaration.requirement == .required {
                    missingRequired.append("\(declaration.id.rawValue): \(reason)")
                }
            }
        }

        guard missingRequired.isEmpty else {
            for pool in pools.values {
                try? pool.syncShutdownGracefully()
            }
            throw PostgresConnectorError.requiredDatabasesUnavailable(missingRequired)
        }

        return (pools, states)
    }
}
