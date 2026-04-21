import Foundation

public enum PostgresConnectorError: Error, LocalizedError, Sendable {
    case duplicateDatabaseIdentifier(String)
    case databaseNotRegistered(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateDatabaseIdentifier(let id):
            return "Duplicate Postgres database id registered: \(id)"
        case .databaseNotRegistered(let id):
            return "No Postgres database registered for id: \(id)"
        }
    }
}
