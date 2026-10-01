import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension PowerPoint {
    static let chartNS="http://schemas.openxmlformats.org/drawingml/2006/chart"
    static func spreadsheetColumn(_ number: Int) -> String {
        var number=number+1, result=""
        while number > 0 { number -= 1; result=String(UnicodeScalar(65+number%26)!)+result; number /= 26 }; return result
    }
    static func writeWorkbook(_ chart: ChartContent,to url: URL) throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
        func write(_ path: String,_ value: String) throws { let target=root.appendingPathComponent(path); try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true); try Data(value.utf8).write(to:target) }
        let ns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let types="http://schemas.openxmlformats.org/package/2006/content-types"
        try write("[Content_Types].xml","<Types xmlns=\"\(types)\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>")
        try write("_rels/.rels",relationships(relationship("rId1","officeDocument","xl/workbook.xml")))
        try write("xl/workbook.xml","<workbook xmlns=\"\(ns)\" xmlns:r=\"\(r)\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>")
        try write("xl/_rels/workbook.xml.rels",relationships(relationship("rId1","worksheet","worksheets/sheet1.xml")))
        func string(_ cell: String,_ text: String) -> String { "<c r=\"\(cell)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(text))</t></is></c>" }
        var rows="<row r=\"1\">"+string("A1","Category")
        for (i,series) in chart.dataSeries.enumerated() { rows += string(spreadsheetColumn(i+1)+"1",series.name) }; rows += "</row>"
        for row in chart.labels.indices {
            let index=row+2; rows += "<row r=\"\(index)\">"
            if chart.kind == .scatter { rows += "<c r=\"A\(index)\"><v>\(Double(chart.labels[row]) ?? Double(row+1))</v></c>" }
            else { rows += string("A\(index)",chart.labels[row]) }
            for (c,series) in chart.dataSeries.enumerated() { rows += "<c r=\"\(spreadsheetColumn(c+1))\(index)\"><v>\(series.values[row])</v></c>" }; rows += "</row>"
        }
        try write("xl/worksheets/sheet1.xml","<worksheet xmlns=\"\(ns)\"><sheetData>\(rows)</sheetData></worksheet>")
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        _=try run("/usr/bin/zip",["-q","-r",url.path,"."],directory:root)
    }
    static func chartXML(_ chart: ChartContent,theme: Theme) -> String {
        let data=chart.kind == .pie ? Array(chart.dataSeries.prefix(1)) : chart.dataSeries
        func strCache(_ values: [String]) -> String { "<c:ptCount val=\"\(values.count)\"/>"+values.enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\(xml($0.element))</c:v></c:pt>" }.joined() }
        func numCache(_ values: [Double]) -> String { "<c:formatCode>General</c:formatCode><c:ptCount val=\"\(values.count)\"/>"+values.enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\($0.element)</c:v></c:pt>" }.joined() }
        func strRef(_ formula: String,_ values: [String]) -> String { "<c:strRef><c:f>\(formula)</c:f><c:strCache>\(strCache(values))</c:strCache></c:strRef>" }
        func numRef(_ formula: String,_ values: [Double]) -> String { "<c:numRef><c:f>\(formula)</c:f><c:numCache>\(numCache(values))</c:numCache></c:numRef>" }
        func title(_ text: String) -> String { "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/>\(paragraphs(text,style:TextStyle(),theme:theme))</c:rich></c:tx><c:overlay val=\"0\"/></c:title>" }
        let end=max(2,chart.labels.count+1)
        var series=""
        for (i,item) in data.enumerated() {
            let column=spreadsheetColumn(i+1)
            series += "<c:ser><c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/><c:tx>\(strRef("Sheet1!$\(column)$1",[item.name]))</c:tx>"
            if let color=item.color { series += "<c:spPr>\(solid(color))<a:ln>\(solid(color))</a:ln></c:spPr>" }
            if chart.kind == .scatter { series += "<c:marker><c:symbol val=\"circle\"/><c:size val=\"6\"/></c:marker><c:xVal>\(numRef("Sheet1!$A$2:$A$\(end)",chart.labels.enumerated().map { Double($0.element) ?? Double($0.offset+1) }))</c:xVal><c:yVal>\(numRef("Sheet1!$\(column)$2:$\(column)$\(end)",item.values))</c:yVal>" }
            else { series += "<c:cat>\(strRef("Sheet1!$A$2:$A$\(end)",chart.labels))</c:cat><c:val>\(numRef("Sheet1!$\(column)$2:$\(column)$\(end)",item.values))</c:val>" }
            series += "</c:ser>"
        }
        let labels="<c:dLbls><c:showLegendKey val=\"0\"/><c:showVal val=\"\(chart.showDataLabels == true ? 1 : 0)\"/><c:showCatName val=\"0\"/><c:showSerName val=\"0\"/><c:showPercent val=\"0\"/><c:showBubbleSize val=\"0\"/></c:dLbls>"
        let tag: String, before: String
        switch chart.kind {
        case .bar,.column:tag="barChart"; before="<c:barDir val=\"\(chart.kind == .bar ? "bar" : "col")\"/><c:grouping val=\"clustered\"/>"
        case .line:tag="lineChart"; before="<c:grouping val=\"standard\"/>"
        case .area:tag="areaChart"; before="<c:grouping val=\"standard\"/>"
        case .pie:tag="pieChart"; before=""
        case .scatter:tag="scatterChart"; before="<c:scatterStyle val=\"marker\"/>"
        }
        let axes=chart.kind == .pie ? "" : "<c:axId val=\"1\"/><c:axId val=\"2\"/>"
        var plot="<c:\(tag)>\(before)<c:varyColors val=\"\(chart.kind == .pie ? 1 : 0)\"/>\(series)\(labels)\(axes)</c:\(tag)>"
        if chart.kind != .pie {
            for id in 1...2 {
                let numeric=id == 2 || chart.kind == .scatter, axis=numeric ? "valAx" : "catAx"
                let position=(id == 1) == (chart.kind != .bar) ? "b" : "l"
                let name=id == 1 ? chart.categoryAxisTitle : chart.valueAxisTitle
                plot += "<c:\(axis)><c:axId val=\"\(id)\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\(position)\"/>"
                if id == 2 && chart.showGridlines != false { plot += "<c:majorGridlines/>" }
                if let name=name, !name.isEmpty { plot += title(name) }
                plot += "<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:majorTickMark val=\"out\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"\(3-id)\"/><c:crosses val=\"autoZero\"/>"
                plot += numeric ? "<c:crossBetween val=\"between\"/>" : "<c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/><c:lblOffset val=\"100\"/>"
                plot += "</c:\(axis)>"
            }
        }
        let legend=chart.showLegend == false ? "" : "<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>"
        return "<c:chartSpace xmlns:c=\"\(chartNS)\" xmlns:a=\"\(a)\" xmlns:r=\"\(r)\"><c:date1904 val=\"0\"/><c:lang val=\"en-US\"/><c:chart>\(title(chart.title))<c:autoTitleDeleted val=\"0\"/><c:plotArea><c:layout/>\(plot)</c:plotArea>\(legend)<c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/></c:chart><c:externalData r:id=\"rIdWorkbook\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>"
    }
    static func readChart(_ root: XMLElement) throws -> ChartContent {
        var chart=ChartContent()
        guard let plot=root.first("plotArea"), let kind=plot.children?.compactMap({ $0 as? XMLElement }).first(where: { ["barChart","lineChart","pieChart","areaChart","scatterChart"].contains($0.localName ?? "") }) else { throw FormatError.invalid("unsupported chart type") }
        switch kind.localName { case "barChart":chart.kind=kind.first("barDir")?.attr("val") == "bar" ? .bar : .column; case "lineChart":chart.kind = .line; case "pieChart":chart.kind = .pie; case "areaChart":chart.kind = .area; default:chart.kind = .scatter }
        func strings(_ node: XMLElement?) -> [String] { node?.descendants("pt").sorted { $0.number("idx") < $1.number("idx") }.map { $0.direct("v")?.stringValue ?? "" } ?? [] }
        let series=kind.descendants("ser")
        chart.labels=strings(series.first?.direct(chart.kind == .scatter ? "xVal" : "cat"))
        let data=series.enumerated().map { i,node -> ChartSeries in
            let name=strings(node.direct("tx")).first ?? node.direct("tx")?.direct("v")?.stringValue ?? "Series \(i+1)"
            let values=strings(node.direct(chart.kind == .scatter ? "yVal" : "val")).map { Double($0) ?? 0 }
            return ChartSeries(name:name,values:values,color:node.direct("spPr")?.direct("solidFill")?.first("srgbClr")?.rgba)
        }
        chart.setSeries(data); chart.title=root.first("chart")?.direct("title")?.descendants("t").compactMap(\.stringValue).joined() ?? ""
        chart.showLegend=root.first("legend") != nil; chart.showGridlines=root.first("majorGridlines") != nil; chart.showDataLabels=kind.first("dLbls")?.first("showVal")?.attr("val") == "1"
        let axes=plot.children?.compactMap { $0 as? XMLElement }.filter { ["catAx","valAx"].contains($0.localName ?? "") } ?? []
        chart.categoryAxisTitle=axes.first?.direct("title")?.descendants("t").compactMap(\.stringValue).joined(); chart.valueAxisTitle=axes.last?.direct("title")?.descendants("t").compactMap(\.stringValue).joined()
        guard !data.isEmpty, data.allSatisfy({ $0.values.count == chart.labels.count }) else { throw FormatError.invalid("chart categories and cached data disagree") }; return chart
    }
}
