import Foundation

public enum VerticalAlignment: String, Codable, CaseIterable, Sendable { case top, middle, bottom }
public struct CellStyle: Codable, Equatable, Sendable {
    public var fill: RGBA? = nil
    public var border: RGBA? = nil
    public var borderWidth: Double = 1
    public var padding: Double = 10
    public var vertical: VerticalAlignment = .top
    public var textStyle: TextStyle? = nil
    public init() {}
}
public struct CellMerge: Codable, Equatable, Sendable {
    public var row: Int; public var column: Int; public var rows: Int; public var columns: Int
    public init(row: Int,column: Int,rows: Int,columns: Int) { self.row=row; self.column=column; self.rows=rows; self.columns=columns }
    public func contains(row: Int,column: Int) -> Bool { (self.row..<self.row+rows).contains(row) && (self.column..<self.column+columns).contains(column) }
}
public extension TableContent {
    func cellFrame(row: Int,column: Int,in frame: Rect) -> Rect {
        let rows=cells.count, columns=cells.first?.count ?? 0
        guard row >= 0, column >= 0, row < rows, column < columns else { return Rect(frame.x,frame.y,1,1) }
        let widths=columnWidths?.count == columns ? columnWidths! : Array(repeating:1.0,count:columns)
        let heights=rowHeights?.count == rows ? rowHeights! : Array(repeating:1.0,count:rows)
        let merge=merges?.first { $0.row == row && $0.column == column }
        let rowSpan=min(rows-row,merge?.rows ?? 1), columnSpan=min(columns-column,merge?.columns ?? 1)
        return Rect(frame.x+frame.width*widths.prefix(column).reduce(0,+)/widths.reduce(0,+),frame.y+frame.height*heights.prefix(row).reduce(0,+)/heights.reduce(0,+),frame.width*widths[column..<column+columnSpan].reduce(0,+)/widths.reduce(0,+),frame.height*heights[row..<row+rowSpan].reduce(0,+)/heights.reduce(0,+))
    }
    func anchor(row: Int,column: Int) -> (Int,Int) {
        guard let merged=merges?.first(where: { $0.contains(row:row,column:column) }) else { return (row,column) }
        return (merged.row,merged.column)
    }
    mutating func merge(_ region: CellMerge) throws {
        guard region.row >= 0, region.column >= 0, region.rows > 0, region.columns > 0, region.row+region.rows <= cells.count, region.column+region.columns <= (cells.first?.count ?? 0) else { throw FormatError.invalid("merge is outside the table") }
        let overlap=(merges ?? []).contains { old in (region.row..<region.row+region.rows).contains { r in (region.column..<region.column+region.columns).contains { c in old.contains(row:r,column:c) } } }
        guard !overlap else { throw FormatError.invalid("split existing merged cells before merging an overlapping range") }
        merges=(merges ?? [])+[region]
    }
    mutating func split(row: Int,column: Int) { merges?.removeAll { $0.contains(row:row,column:column) } }
    mutating func insertRow(at index: Int) {
        guard (0...cells.count).contains(index), cells.count < 1000 else { return }
        cells.insert(Array(repeating:"",count:cells.first?.count ?? 1),at:index)
        if rowHeights != nil { rowHeights?.insert(1,at:index) }
        remapCells(row:index,delta:1,column:nil)
    }
    mutating func removeRow(at index: Int) {
        guard cells.count > 1, cells.indices.contains(index) else { return }
        cells.remove(at:index); rowHeights?.remove(at:index); remapCells(row:index,delta:-1,column:nil)
    }
    mutating func insertColumn(at index: Int) {
        guard let count=cells.first?.count, (0...count).contains(index), count < 100 else { return }
        for r in cells.indices { cells[r].insert("",at:index) }; columnWidths?.insert(1,at:index); remapCells(row:nil,delta:1,column:index)
    }
    mutating func removeColumn(at index: Int) {
        guard let count=cells.first?.count, count > 1, (0..<count).contains(index) else { return }
        for r in cells.indices { cells[r].remove(at:index) }; columnWidths?.remove(at:index); remapCells(row:nil,delta:-1,column:index)
    }
    private mutating func remapCells(row: Int?,delta: Int,column: Int?) {
        var result: [String:CellStyle]=[:]
        for (key,value) in styles ?? [:] {
            let parts=key.split(separator:":").compactMap { Int($0) }; guard parts.count == 2 else { continue }
            var r=parts[0], c=parts[1]
            if let index=row { if delta < 0 && r == index { continue }; if r >= index { r += delta } }
            if let index=column { if delta < 0 && c == index { continue }; if c >= index { c += delta } }
            result["\(r):\(c)"]=value
        }; styles=result
        // Preserve merges outside the edited range; split merges intersected by a deletion.
        merges=merges?.compactMap { original in
            var merge=original
            if let index=row {
                if delta < 0 && (merge.row..<merge.row+merge.rows).contains(index) { return nil }
                if index <= merge.row { merge.row += delta } else if index < merge.row+merge.rows { merge.rows += delta }
            }
            if let index=column {
                if delta < 0 && (merge.column..<merge.column+merge.columns).contains(index) { return nil }
                if index <= merge.column { merge.column += delta } else if index < merge.column+merge.columns { merge.columns += delta }
            }; return merge
        }
    }
}
