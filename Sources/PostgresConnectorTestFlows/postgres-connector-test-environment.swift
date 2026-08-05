import Milieu
import PostgresConnector

private enum PostgresConnectorTestEnvironmentKey:
    String,
    EnvironmentExtractable
{
    case ridgeback_database_host
    case test_db_user
    case test_db_passwd
    case ca_cert

    var key: EnvironmentExtractableKey {
        .auto
    }
}

struct PostgresConnectorTestEnvironment:
    Sendable
{
    private let database: PostgresDatabase

    static func load() throws -> Self {
        let identifier: PostgresDatabaseIdentifier = "test"

        return Self(
            database: try PostgresDatabase(
                id: identifier,
                host: PostgresConnectorTestEnvironmentKey
                    .ridgeback_database_host,
                port: 5432,
                username: PostgresConnectorTestEnvironmentKey
                    .test_db_user,
                password: PostgresConnectorTestEnvironmentKey
                    .test_db_passwd,
                database: "test",
                caCert: PostgresConnectorTestEnvironmentKey
                    .ca_cert
            )
        )
    }

    func makeConnector() throws -> (
        connector: PostgresConnector,
        database: PostgresDatabaseIdentifier
    ) {
        return (
            connector: try PostgresConnector(
                databases: [
                    database,
                ],
                threadCount: 2
            ),
            database: database.id
        )
    }
}
