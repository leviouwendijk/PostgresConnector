import Foundation
import PostgresKit

public struct PostgresPreparedQuery: Sendable {
    public let sql: String
    public let binds: [PostgresData]

    public init(
        sql: String,
        binds: [PostgresData] = []
    ) {
        self.sql = sql
        self.binds = binds
    }
}
