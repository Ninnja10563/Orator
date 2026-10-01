import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension PowerPoint {
    static func tableXML(_ table: TableContent,object: SlideObject,theme: Theme) -> String {
        let rows=table.cells.count, columns=table.cells[0].count
        let widths=table.columnWidths ?? Array(repeating:1,count:columns), heights=table.rowHeights ?? Array(repeating:1,count:rows)
        let grid=widths.map { "<a:gridCol w=\"\(emu(object.frame.width*$0/widths.reduce(0,+)))\"/>" }.joined()
        var body=""
        for r in 0..<rows {
            body += "<a:tr h=\"\(emu(object.frame.height*heights[r]/heights.reduce(0,+)))\">"
            for c in 0..<columns {
                let merge=table.merges?.first { $0.contains(row:r,column:c) }
                var attrs=""
                if let merge=merge {
                    if r == merge.row { attrs += " rowSpan=\"\(merge.rows)\"" } else { attrs += " vMerge=\"1\"" }
                    if c == merge.column { attrs += " gridSpan=\"\(merge.columns)\"" } else { attrs += " hMerge=\"1\"" }
                }
                let cell=table.styles?["\(r):\(c)"] ?? CellStyle()
                var textStyle=cell.textStyle ?? object.textStyle
                if cell.textStyle == nil { textStyle.size=min(textStyle.size,24); textStyle.bold=r == 0; if r == 0 { let color=theme.accent; textStyle.color=color.red*0.2126+color.green*0.7152+color.blue*0.0722 > 0.6 ? .ink : .white } }
                let fill=cell.fill ?? (r == 0 ? theme.accent : theme.background)
                let border=cell.border ?? theme.foreground.withAlpha(0.18)
                let edges=["lnL","lnR","lnT","lnB"].map { "<a:\($0) w=\"\(emu(cell.borderWidth))\">\(solid(border))<a:prstDash val=\"solid\"/></a:\($0)>" }.joined()
                let anchor=cell.vertical == .top ? "t" : cell.vertical == .middle ? "ctr" : "b"
                body += "<a:tc\(attrs)><a:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs(table.cells[r][c],style:textStyle,theme:theme))</a:txBody><a:tcPr marL=\"\(emu(cell.padding))\" marR=\"\(emu(cell.padding))\" marT=\"\(emu(cell.padding))\" marB=\"\(emu(cell.padding))\" anchor=\"\(anchor)\">\(edges)\(solid(fill))</a:tcPr></a:tc>"
            }; body += "</a:tr>"
        }
        return "<a:tbl><a:tblPr firstRow=\"1\" bandRow=\"1\"/><a:tblGrid>\(grid)</a:tblGrid>\(body)</a:tbl>"
    }
    static func readTable(_ node: XMLElement,style: TextStyle,links: [String:String]) throws -> TableContent {
        let rows=node.descendants("tr"); var table=TableContent(); table.cells=[]; table.styles=[:]
        table.rowHeights=rows.map { max(0.001,$0.number("h")/9525) }; table.columnWidths=node.descendants("gridCol").map { max(0.001,$0.number("w")/9525) }
        var merges: [CellMerge]=[]
        for (r,row) in rows.enumerated() {
            var values: [String]=[]
            for (c,cell) in row.descendants("tc").enumerated() {
                let imported=cell.direct("txBody").map { readText($0,defaultStyle:style,links:links) }
                values.append(imported?.0 ?? "")
                var settings=CellStyle(); settings.textStyle=imported?.1.first?.style
                if let props=cell.direct("tcPr") {
                    settings.padding=props.number("marL",default:95250)/9525
                    settings.vertical=["ctr":.middle,"b":.bottom][props.attr("anchor")] ?? .top
                    settings.fill=props.direct("solidFill")?.first("srgbClr")?.rgba
                    if let line=props.direct("lnL") { settings.border=line.first("srgbClr")?.rgba; settings.borderWidth=line.number("w")/9525 }
                }; table.styles?["\(r):\(c)"]=settings
                if cell.attr("hMerge") != "1", cell.attr("vMerge") != "1" {
                    let height=Int(cell.number("rowSpan",default:1)), width=Int(cell.number("gridSpan",default:1))
                    if height > 1 || width > 1 { merges.append(CellMerge(row:r,column:c,rows:height,columns:width)) }
                }
            }; table.cells.append(values)
        }
        for merge in merges { try table.merge(merge) }; return table
    }
}
private extension RGBA { func withAlpha(_ value: Double) -> RGBA { RGBA(red,green,blue,value) } }
