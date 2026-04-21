import Foundation
import PostgresKit
import PSQL

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

    public init(
        _ renderedSQL: PSQL.RenderedSQL
    ) {
        self.init(
            sql: renderedSQL.sql,
            binds: renderedSQL.binds.map(PostgresData.from)
        )
    }
}
