import Foundation
import PostgresConnector
import TestFlows

extension PostgresConnectorFlowSuite {
    static var transactionFlow: TestFlow {
        TestFlow(
            "transaction",
            tags: [
                "postgres",
                "connector",
                "transaction",
                "integration",
            ]
        ) {
            Step("transaction pins one PostgreSQL session") {
                try await withTestConnector { connector, database in
                    let table = makeTestTableName(
                        prefix: "temporary"
                    )

                    let rowCount = try await connector.transaction(
                        on: database
                    ) { transaction in
                        try await transaction.run(
                            sql: """
                            CREATE TEMPORARY TABLE \(table)
                            (
                                marker integer NOT NULL
                            )
                            ON COMMIT DROP
                            """
                        )

                        try await transaction.run(
                            sql: """
                            INSERT INTO \(table)
                                (
                                    marker
                                )
                            VALUES
                                (
                                    1
                                )
                            """
                        )

                        let rows = try await transaction.rows(
                            sql: """
                            SELECT
                                marker
                            FROM
                                \(table)
                            """
                        )

                        return rows.count
                    }

                    try Expect.equal(
                        rowCount,
                        1,
                        "transaction.connection-pinning"
                    )
                }
            }

            Step("successful transaction commits") {
                try await withTestConnector { connector, database in
                    try await withTestTable(
                        connector: connector,
                        database: database
                    ) { table in
                        try await connector.transaction(
                            on: database
                        ) { transaction in
                            try await transaction.run(
                                sql: """
                                INSERT INTO \(table)
                                    (
                                        marker
                                    )
                                VALUES
                                    (
                                        1
                                    )
                                """
                            )
                        }

                        let rows = try await connector.rows(
                            sql: """
                            SELECT
                                marker
                            FROM
                                \(table)
                            """,
                            on: database
                        )

                        try Expect.equal(
                            rows.count,
                            1,
                            "transaction.commit"
                        )
                    }
                }
            }

            Step("throwing transaction rolls back") {
                try await withTestConnector { connector, database in
                    try await withTestTable(
                        connector: connector,
                        database: database
                    ) { table in
                        var observedExpectedFailure = false

                        do {
                            try await connector.transaction(
                                on: database
                            ) { transaction -> Void in
                                try await transaction.run(
                                    sql: """
                                    INSERT INTO \(table)
                                        (
                                            marker
                                        )
                                    VALUES
                                        (
                                            1
                                        )
                                    """
                                )

                                throw TransactionProbeError
                                    .deliberateRollback
                            }
                        } catch TransactionProbeError.deliberateRollback {
                            observedExpectedFailure = true
                        }

                        try Expect.equal(
                            observedExpectedFailure,
                            true,
                            "transaction.rollback.error-preserved"
                        )

                        let rows = try await connector.rows(
                            sql: """
                            SELECT
                                marker
                            FROM
                                \(table)
                            """,
                            on: database
                        )

                        try Expect.equal(
                            rows.count,
                            0,
                            "transaction.rollback"
                        )
                    }
                }
            }

            Step("closure result survives commit") {
                try await withTestConnector { connector, database in
                    let result: String = try await connector.transaction(
                        on: database
                    ) { _ in
                        "committed"
                    }

                    try Expect.equal(
                        result,
                        "committed",
                        "transaction.result"
                    )
                }
            }

            Step("transaction options are applied") {
                try await withTestConnector { connector, database in
                    let matchingRows = try await connector.transaction(
                        on: database,
                        options: .init(
                            isolation: .serializable,
                            accessMode: .readOnly
                        )
                    ) { transaction in
                        try await transaction.rows(
                            sql: """
                            SELECT
                                1
                            WHERE
                                current_setting(
                                    'transaction_isolation'
                                ) = 'serializable'
                                AND
                                current_setting(
                                    'transaction_read_only'
                                ) = 'on'
                            """
                        )
                    }

                    try Expect.equal(
                        matchingRows.count,
                        1,
                        "transaction.options"
                    )
                }
            }

            Step("escaped transaction is closed") {
                try await withTestConnector { connector, database in
                    let escaped: PostgresTransaction =
                        try await connector.transaction(
                            on: database
                        ) { transaction in
                            transaction
                        }

                    var observedClosedError = false

                    do {
                        try await escaped.run(
                            sql: "SELECT 1"
                        )
                    } catch PostgresTransactionError.closed {
                        observedClosedError = true
                    }

                    try Expect.equal(
                        observedClosedError,
                        true,
                        "transaction.closed"
                    )
                }
            }

            Step("unregistered database is rejected") {
                try await withTestConnector { connector, _ in
                    let missing: PostgresDatabaseIdentifier =
                        "unregistered"

                    var observedExpectedError = false

                    do {
                        try await connector.transaction(
                            on: missing
                        ) { _ -> Void in
                            ()
                        }
                    } catch PostgresConnectorError
                        .databaseNotRegistered(let identifier)
                    {
                        observedExpectedError =
                            identifier == missing.rawValue
                    }

                    try Expect.equal(
                        observedExpectedError,
                        true,
                        "transaction.database-not-registered"
                    )
                }
            }
        }
    }
}

private enum TransactionProbeError:
    Error,
    Sendable,
    Equatable
{
    case deliberateRollback
}

private func withTestConnector<Result: Sendable>(
    _ operation: @escaping @Sendable (
        PostgresConnector,
        PostgresDatabaseIdentifier
    ) async throws -> Result
) async throws -> Result {
    let environment = try PostgresConnectorTestEnvironment.load()
    let fixture = try environment.makeConnector()

    do {
        let result = try await operation(
            fixture.connector,
            fixture.database
        )

        await fixture.connector.shutdown()

        return result
    } catch {
        await fixture.connector.shutdown()

        throw error
    }
}

private func withTestTable<Result: Sendable>(
    connector: PostgresConnector,
    database: PostgresDatabaseIdentifier,
    _ operation: @escaping @Sendable (
        String
    ) async throws -> Result
) async throws -> Result {
    let table = makeTestTableName(
        prefix: "persistent"
    )

    try await connector.run(
        sql: """
        CREATE TABLE \(table)
        (
            marker integer NOT NULL
        )
        """,
        on: database
    )

    do {
        let result = try await operation(
            table
        )

        try await connector.run(
            sql: """
            DROP TABLE IF EXISTS \(table)
            """,
            on: database
        )

        return result
    } catch {
        try? await connector.run(
            sql: """
            DROP TABLE IF EXISTS \(table)
            """,
            on: database
        )

        throw error
    }
}

private func makeTestTableName(
    prefix: String
) -> String {
    let identifier = UUID()
        .uuidString
        .replacingOccurrences(
            of: "-",
            with: ""
        )
        .lowercased()

    return """
    postgresconnector_test_\(prefix)_\(identifier)
    """
}
