import Foundation
import PostgresConnector
import TestFlows

private struct MissingKey: Error, LocalizedError {
    var errorDescription: String? { "LINKER_DB_USER is not set" }
}

private func local(_ id: PostgresDatabaseIdentifier) -> PostgresDatabase {
    PostgresDatabase(
        id: id,
        host: "127.0.0.1",
        username: "nobody",
        password: "unused",
        database: id.rawValue,
        tls: .disabled
    )
}

extension PostgresConnectorFlowSuite {
    static var declarationFlow: TestFlow {
        TestFlow(
            "declarations",
            tags: [
                "postgres",
                "connector",
                "configuration",
            ]
        ) {
            Step("an optional database that cannot be configured is isolated") {
                let connector = try PostgresConnector(
                    declarations: [
                        PostgresDatabaseDeclaration(local("tokens")),
                        PostgresDatabaseDeclaration(id: "linker", requirement: .optional) {
                            throw MissingKey()
                        },
                    ],
                    threadCount: 1
                )
                defer { Task { await connector.shutdown() } }

                let states = await connector.databaseStates()
                try Expect.equal(states.map(\.id.rawValue), ["tokens", "linker"], "declarations.order")
                try Expect.equal(states[0].status, .configured, "declarations.tokens-configured")
                try Expect.equal(
                    states[1].status,
                    .unavailable(reason: "LINKER_DB_USER is not set"),
                    "declarations.linker-unavailable"
                )
                try Expect.equal(
                    await connector.registeredDatabaseIdentifiers().map(\.rawValue),
                    ["tokens"],
                    "declarations.only-configured-registered"
                )

                var thrown: PostgresConnectorError?
                do {
                    _ = try await connector.rows(sql: "SELECT 1", on: "linker")
                } catch let error as PostgresConnectorError {
                    thrown = error
                }
                guard case .databaseUnavailable(let id, let reason) = thrown else {
                    throw TestFlowAssertionFailure(label: "declarations.unavailable-error", message: "wrong or no error: \(String(describing: thrown))")
                }
                try Expect.equal(id, "linker", "declarations.unavailable-id")
                try Expect.equal(reason, "LINKER_DB_USER is not set", "declarations.unavailable-reason")

                let health = await connector.health(timeoutSeconds: 1)
                let linker = try Expect.notNil(health.first { $0.id == "linker" }, "declarations.health-linker")
                try Expect.equal(linker.state, .unconfigured, "declarations.health-unconfigured")
                try Expect.false(linker.required, "declarations.health-optional")
            }

            Step("a required database that cannot be configured stops the connector") {
                var thrown: PostgresConnectorError?
                do {
                    _ = try PostgresConnector(
                        declarations: [
                            PostgresDatabaseDeclaration(local("tokens")),
                            PostgresDatabaseDeclaration(id: "analytics") { throw MissingKey() },
                        ],
                        threadCount: 1
                    )
                } catch let error as PostgresConnectorError {
                    thrown = error
                }
                guard case .requiredDatabasesUnavailable(let entries) = thrown else {
                    throw TestFlowAssertionFailure(label: "declarations.required-error", message: "wrong or no error: \(String(describing: thrown))")
                }
                try Expect.equal(entries, ["analytics: LINKER_DB_USER is not set"], "declarations.required-entries")
            }

            Step("duplicate ids are rejected") {
                try Expect.throwsError("declarations.duplicate") {
                    _ = try PostgresConnector(
                        declarations: [
                            PostgresDatabaseDeclaration(local("tokens")),
                            PostgresDatabaseDeclaration(local("tokens"), requirement: .optional),
                        ],
                        threadCount: 1
                    )
                }
            }
        }
    }
}
