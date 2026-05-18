import Foundation

struct GameGridLayout {
    static func dimensions(for count: Int) -> (columns: Int, rows: Int) {
        guard count > 0 else { return (columns: 0, rows: 0) }
        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        return (columns: columns, rows: rows)
    }
}
