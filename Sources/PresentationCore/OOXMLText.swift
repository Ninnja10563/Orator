import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension PowerPoint {
    static func paragraphs(_ text: String,style: TextStyle,theme: Theme,runs: [TextRun]? = nil,opacity: Double = 1,hyperlink: ((String) -> String)? = nil) -> String {
        var offset=0
        func properties(_ value: TextStyle) -> String {
            let foreground=value.color ?? theme.foreground
            let visible=RGBA(foreground.red,foreground.green,foreground.blue,foreground.alpha*opacity)
            let link=value.hyperlink.flatMap { hyperlink?($0) }.map { "<a:hlinkClick r:id=\"\(xml($0))\"/>" } ?? ""
            let highlight=value.highlight.map { "<a:highlight>\(color($0))</a:highlight>" } ?? ""
            return "<a:rPr lang=\"en-US\" sz=\"\(Int(value.size*75))\" b=\"\(value.bold ? 1 : 0)\" i=\"\(value.italic ? 1 : 0)\" u=\"\(value.underline ? "sng" : "none")\" strike=\"\(value.strikethrough == true ? "sngStrike" : "noStrike")\" spc=\"\(Int(((value.tracking ?? 0)*75).rounded()))\">\(solid(visible))\(highlight)<a:latin typeface=\"\(xml(value.fontName))\"/>\(link)</a:rPr>"
        }
        return text.components(separatedBy:"\n").map { line in
            let length=line.utf16.count, start=offset; offset += length+1
            let paragraphStyle=runs?.first(where: { $0.location <= start && $0.location+$0.length > start })?.style ?? style
            let alignment: String
            switch paragraphStyle.alignment { case .left:alignment="l"; case .center:alignment="ctr"; case .right:alignment="r"; case .justified:alignment="just" }
            let settings=paragraphStyle.paragraph ?? ParagraphSettings()
            let list: String
            switch settings.list { case .none:list="<a:buNone/>"; case .bullet:list="<a:buChar char=\"•\"/>"; case .numbered:list="<a:buAutoNum type=\"arabicPeriod\"/>" }
            let pPr="<a:pPr algn=\"\(alignment)\" lvl=\"\(settings.level)\" marL=\"\(emu(settings.indent))\" indent=\"\(emu(settings.firstLineIndent-settings.indent))\"><a:lnSpc><a:spcPts val=\"\(Int((paragraphStyle.size+paragraphStyle.lineSpacing)*75))\"/></a:lnSpc><a:spcBef><a:spcPts val=\"\(Int(settings.before*75))\"/></a:spcBef><a:spcAft><a:spcPts val=\"\(Int(settings.after*75))\"/></a:spcAft>\(list)</a:pPr>"
            var breaks=Set([0,length])
            for run in runs ?? [] where run.location < start+length && run.location+run.length > start { breaks.insert(max(0,run.location-start)); breaks.insert(min(length,run.location+run.length-start)) }
            let positions=breaks.sorted(); var body=""
            for i in 0..<max(0,positions.count-1) {
                let location=positions[i], count=positions[i+1]-location
                let effective=runs?.first(where: { $0.location <= start+location && $0.location+$0.length > start+location })?.style ?? style
                let string=(line as NSString).substring(with:NSRange(location:location,length:count))
                body += "<a:r>\(properties(effective))<a:t xml:space=\"preserve\">\(xml(string))</a:t></a:r>"
            }
            return "<a:p>\(pPr)\(body)<a:endParaRPr lang=\"en-US\" sz=\"\(Int(paragraphStyle.size*75))\"/></a:p>"
        }.joined()
    }
    static func readText(_ body: XMLElement,defaultStyle: TextStyle,links: [String:String],palette: [String:RGBA] = [:]) -> (String,[TextRun]) {
        var text="", runs: [TextRun]=[]
        func style(_ props: XMLElement?,base: TextStyle) -> TextStyle {
            guard let props=props else { return base }; var value=base
            if !props.attr("sz").isEmpty { value.size=max(1,min(1000,props.number("sz")/75)) }
            if !props.attr("b").isEmpty { value.bold=props.attr("b") == "1" }; if !props.attr("i").isEmpty { value.italic=props.attr("i") == "1" }
            if !props.attr("u").isEmpty { value.underline=props.attr("u") != "none" }
            value.strikethrough=props.attr("strike") == "sngStrike" || props.attr("strike") == "dblStrike"
            value.tracking=props.number("spc")/75
            if let color=props.direct("solidFill")?.officeColor(palette:palette) { value.color=color }
            if let color=props.direct("highlight")?.first("srgbClr") { value.highlight=color.rgba }
            if let font=props.first("latin"), !font.attr("typeface").isEmpty, !font.attr("typeface").hasPrefix("+") { value.fontName=font.attr("typeface") }
            if let link=props.first("hlinkClick") { value.hyperlink=links[link.attr("r:id")] }
            return value
        }
        for (i,paragraph) in body.descendants("p").enumerated() {
            if i > 0 { text += "\n" }
            let pPr=paragraph.direct("pPr"); var base=style(pPr?.direct("defRPr"),base:defaultStyle)
            base.alignment=["ctr":.center,"r":.right,"just":.justified][pPr?.attr("algn") ?? ""] ?? .left
            var options=ParagraphSettings(); options.level=max(0,min(8,Int(pPr?.number("lvl") ?? 0))); options.indent=(pPr?.number("marL") ?? 0)/9525; options.firstLineIndent=options.indent+(pPr?.number("indent") ?? 0)/9525
            options.before=(pPr?.direct("spcBef")?.first("spcPts")?.number("val") ?? 0)/75; options.after=(pPr?.direct("spcAft")?.first("spcPts")?.number("val") ?? 0)/75
            if pPr?.first("buChar") != nil { options.list = .bullet }; if pPr?.first("buAutoNum") != nil { options.list = .numbered }; base.paragraph=options
            if let spacing=pPr?.direct("lnSpc")?.first("spcPts") { base.lineSpacing=max(0,spacing.number("val")/75-base.size) }
            for child in paragraph.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                let value: String
                if child.localName == "br" { value="\n" }
                else if ["r","fld"].contains(child.localName ?? "") { value=child.direct("t")?.stringValue ?? "" }
                else { continue }
                if !value.isEmpty { runs.append(TextRun(location:text.utf16.count,length:value.utf16.count,style:style(child.direct("rPr"),base:base))); text += value }
            }
        }; return (text,runs)
    }
}
