import Foundation
import NIOCore
import NIOPosix
import PostgresKit

// public final class PostgresConnector: @unchecked Sendable {
public final class PostgresConnector {
    private let eventLoopGroup: any EventLoopGroup
    private let ownsEventLoopGroup: Bool
    private let pools: [PostgresDatabaseIdentifier: EventLoopGroupConnectionPool<PostgresConnectionSource>]

    public init(
        databases: [PostgresDatabase],
        eventLoopGroup: any EventLoopGroup
    ) throws {
        self.eventLoopGroup = eventLoopGroup
        self.ownsEventLoopGroup = false
        self.pools = try Self.makePools(
            databases: databases,
            eventLoopGroup: eventLoopGroup
        )
    }

    private init(
        databases: [PostgresDatabase],
        managedEventLoopGroup: MultiThreadedEventLoopGroup
    ) throws {
        self.eventLoopGroup = managedEventLoopGroup
        self.ownsEventLoopGroup = true
        self.pools = try Self.makePools(
            databases: databases,
            eventLoopGroup: managedEventLoopGroup
        )
    }

    public convenience init(
        databases: [PostgresDatabase],
        threadCount: Int = max(1, ProcessInfo.processInfo.activeProcessorCount)
    ) throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)

        do {
            try self.init(
                databases: databases,
                managedEventLoopGroup: group
            )
        } catch {
            try? group.syncShutdownGracefully()
            throw error
        }
    }

    public func pool(
        for database: PostgresDatabaseIdentifier
    ) throws -> EventLoopGroupConnectionPool<PostgresConnectionSource> {
        guard let pool = pools[database] else {
            throw PostgresConnectorError.databaseNotRegistered(database.rawValue)
        }
        return pool
    }

    public func rows(
        for query: PostgresPreparedQuery,
        on database: PostgresDatabaseIdentifier
    ) async throws -> [PostgresRow] {
        let pool = try pool(for: database)

        return try await withCheckedThrowingContinuation { continuation in
            pool.withConnection { connection in
                connection.query(query.sql, query.binds).map(\.rows)
            }.whenComplete { result in
                continuation.resume(with: result)
            }
        }
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
        let pool = try pool(for: database)

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
        sql: String,
        binds: [PostgresData] = [],
        on database: PostgresDatabaseIdentifier
    ) async throws {
        try await run(
            .init(sql: sql, binds: binds),
            on: database
        )
    }

    public func shutdown() {
        for pool in pools.values {
            try? pool.syncShutdownGracefully()
        }

        if ownsEventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }

    private static func makePools(
        databases: [PostgresDatabase],
        eventLoopGroup: any EventLoopGroup
    ) throws -> [PostgresDatabaseIdentifier: EventLoopGroupConnectionPool<PostgresConnectionSource>] {
        var pools: [PostgresDatabaseIdentifier: EventLoopGroupConnectionPool<PostgresConnectionSource>] = [:]
        pools.reserveCapacity(databases.count)

        for database in databases {
            if pools[database.id] != nil {
                throw PostgresConnectorError.duplicateDatabaseIdentifier(database.id.rawValue)
            }

            let sqlConfiguration = try database.makeSQLConfiguration()
            let source = PostgresConnectionSource(sqlConfiguration: sqlConfiguration)

            pools[database.id] = EventLoopGroupConnectionPool(
                source: source,
                on: eventLoopGroup
            )
        }

        return pools
    }
}
