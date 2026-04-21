import Foundation
import PostgresKit
import PSQL

extension PostgresData {
    static func from(
        _ bind: PSQL.SQLBind
    ) -> PostgresData {
        if let value = bind.value {
            return fromTyped(value, hint: bind.hint)
        }

        return initialize(fromPSQLBind: bind)
    }

    private static func fromTyped(
        _ value: PSQL.SQLBindValue,
        hint: PSQLType?
    ) -> PostgresData {
        switch value {
        case .null:
            return .null

        case .text(let string):
            return PostgresData(string: string)

        case .bool(let bool):
            return PostgresData(bool: bool)

        case .int64(let int64):
            if let int = Int(exactly: int64) {
                return PostgresData(int: int)
            }

            return PostgresData(string: String(int64))

        case .double(let double):
            return PostgresData(double: double)

        case .date(let date):
            return PostgresData(string: makeISO8601Formatter().string(from: date))

        case .uuid(let uuid):
            return PostgresData(string: uuid.uuidString)

        case .decimal(let decimal):
            return PostgresData(string: decimal.description)

        case .json(let data),
             .jsonb(let data):
            return PostgresData(
                string: String(data: data, encoding: .utf8) ?? "null"
            )

        case .bytea(let data):
            let hex = "\\x" + data.map { String(format: "%02x", $0) }.joined()
            return PostgresData(string: hex)

        case .inet(let string):
            return PostgresData(string: string)

        case .array(let items, let element):
            let body = items
                .map { item -> String in
                    switch item {
                    case .null:
                        return "NULL"

                    case .text(let string):
                        return "\"\(string.replacingOccurrences(of: "\"", with: "\\\""))\""

                    case .int64(let int64):
                        return String(int64)

                    case .double(let double):
                        return String(double)

                    case .bool(let bool):
                        return bool ? "t" : "f"

                    default:
                        let mapped = PostgresData.fromTyped(
                            item,
                            hint: element
                        ).string ?? "null"

                        return "\"\(mapped.replacingOccurrences(of: "\"", with: "\\\""))\""
                    }
                }
                .joined(separator: ",")

            return PostgresData(string: "{\(body)}")
        }
    }

    static func initialize(
        fromPSQLBind bind: PSQL.SQLBind
    ) -> PostgresData {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeISO8601Formatter().string(from: date))
        }

        let data: Data
        do {
            data = try encoder.encode(bind)
        } catch {
            return PostgresData(
                string: #"{"_bind_encode_error":"\#(String(describing: error))"}"#
            )
        }

        if data.isEmpty {
            return .null
        }

        if let raw = String(data: data, encoding: .utf8), raw == "null" {
            return .null
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let value = try? decoder.decode(String.self, from: data) {
            return PostgresData(string: value)
        }

        if let value = try? decoder.decode(Bool.self, from: data) {
            return PostgresData(bool: value)
        }

        if let value = try? decoder.decode(Int.self, from: data) {
            return PostgresData(int: value)
        }

        if let value = try? decoder.decode(Int64.self, from: data) {
            if let int = Int(exactly: value) {
                return PostgresData(int: int)
            }

            return PostgresData(string: String(value))
        }

        if let value = try? decoder.decode(Double.self, from: data) {
            return PostgresData(double: value)
        }

        return PostgresData(
            string: String(data: data, encoding: .utf8) ?? "null"
        )
    }

    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
            .withColonSeparatorInTimeZone,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
