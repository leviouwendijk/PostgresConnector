import Foundation

public enum PostgresConnectorError: Error, LocalizedError, Sendable {
    case duplicateDatabaseIdentifier(String)
    case databaseNotRegistered(String)

    /// Declared, but could not be configured when the connector was created.
    case databaseUnavailable(id: String, reason: String)

    /// One or more required databases could not be configured; the connector
    /// was not created. Each entry is `id: reason`.
    case requiredDatabasesUnavailable([String])

    case healthProbeTimedOut(id: String, seconds: Double)

    public var errorDescription: String? {
        switch self {
        case .duplicateDatabaseIdentifier(let id):
            return "Duplicate Postgres database id registered: \(id)"
        case .databaseNotRegistered(let id):
            return "No Postgres database registered for id: \(id)"
        case .databaseUnavailable(let id, let reason):
            return "Postgres database '\(id)' is unavailable: \(reason)"
        case .requiredDatabasesUnavailable(let entries):
            return "Required Postgres databases could not be configured: \(entries.joined(separator: "; "))"
        case .healthProbeTimedOut(let id, let seconds):
            return "Postgres database '\(id)' did not answer within \(seconds)s"
        }
    }
}
