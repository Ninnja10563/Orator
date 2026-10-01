import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// An intentionally bounded Office Open XML adapter. Native files remain lossless.
/// No untrusted archive paths are extracted onto the filesystem.
public enum PowerPoint {
    public struct ImportResult { public var deck: Presentation; public var warnings: [String] }
    static let a="http://schemas.openxmlformats.org/drawingml/2006/main"
    static let p="http://schemas.openxmlformats.org/presentationml/2006/main"
    static let r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let relNS="http://schemas.openxmlformats.org/package/2006/relationships"
    static func xml(_ s: String) -> String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;") }
    static func emu(_ d: Double) -> Int { Int((d*9525).rounded()) }
    static func hex(_ c: RGBA) -> String { String(format:"%02X%02X%02X",Int(min(1,max(0,c.red))*255),Int(min(1,max(0,c.green))*255),Int(min(1,max(0,c.blue))*255)) }
    static func color(_ c: RGBA) -> String { "<a:srgbClr val=\"\(hex(c))\"><a:alpha val=\"\(Int(c.alpha*100000))\"/></a:srgbClr>" }
    static func solid(_ c: RGBA) -> String { "<a:solidFill>\(color(c))</a:solidFill>" }
    static func xfrm(_ o: SlideObject) -> String { "<a:xfrm rot=\"\(Int(o.rotation*60000))\"><a:off x=\"\(emu(o.frame.x))\" y=\"\(emu(o.frame.y))\"/><a:ext cx=\"\(emu(o.frame.width))\" cy=\"\(emu(o.frame.height))\"/></a:xfrm>" }
    static func paragraphs(_ text: String,style: TextStyle,theme: Theme) -> String {
        let alignment: String
        switch style.alignment { case .left:alignment="l"; case .center:alignment="ctr"; case .right:alignment="r"; case .justified:alignment="just" }
        return text.components(separatedBy:"\n").map { line in
            "<a:p><a:pPr algn=\"\(alignment)\"/><a:r><a:rPr lang=\"en-US\" sz=\"\(Int(style.size*100))\" b=\"\(style.bold ? 1 : 0)\" i=\"\(style.italic ? 1 : 0)\" u=\"\(style.underline ? "sng" : "none")\">\(solid(style.color ?? theme.foreground))<a:latin typeface=\"\(xml(style.fontName))\"/></a:rPr><a:t xml:space=\"preserve\">\(xml(line))</a:t></a:r><a:endParaRPr lang=\"en-US\"/></a:p>"
        }.joined()
    }
    static func relationship(_ id: String,_ type: String,_ target: String) -> String { "<Relationship Id=\"\(id)\" Type=\"\(r)/\(type)\" Target=\"\(xml(target))\"/>" }
    static func relationships(_ items: String) -> String { "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"\(relNS)\">\(items)</Relationships>" }
    static let groupHeader="<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    @discardableResult public static func export(_ deck: Presentation,to destination: URL) throws -> [String] {
        try PresentationFile.validate(deck)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        func write(_ path: String,_ content: String) throws {
            let url=root.appendingPathComponent(path); try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true); try Data(content.utf8).write(to:url)
        }
        var overrides="", slideIDs="", presentationRels="", warnings=Set<String>()
        func override(_ part: String,_ type: String) { overrides += "<Override PartName=\"/\(part)\" ContentType=\"application/vnd.openxmlformats-officedocument.\(type)+xml\"/>" }
        override("ppt/presentation.xml","presentationml.presentation.main")
        override("ppt/slideMasters/slideMaster1.xml","presentationml.slideMaster")
        override("ppt/slideLayouts/slideLayout1.xml","presentationml.slideLayout")
        override("ppt/theme/theme1.xml","theme")
        for (index,sourceSlide) in deck.slides.enumerated() {
            let slide=deck.resolved(sourceSlide)
            let n=index+1; var rels=relationship("rIdLayout","slideLayout","../slideLayouts/slideLayout1.xml"), body="", objectNumber=1
            func objectXML(_ o: SlideObject) throws -> String {
                guard !o.hidden else { return "" }
                if o.kind == .group {
                    warnings.insert("Groups are flattened; group rotation is not retained.")
                    return try o.children.map(objectXML).joined()
                }
                objectNumber += 1; let id=objectNumber
                let nv="<p:cNvPr id=\"\(id)\" name=\"\(xml(o.name))\"/>"
                if o.opacity < 1 { warnings.insert("Object-level opacity is not retained in PowerPoint export.") }
                if o.kind == .image, let image=o.image, let asset=deck.assets[image.assetID] {
                    let ext: String
                    if asset.data.starts(with:[0x89,0x50,0x4e,0x47]) { ext="png" }
                    else if asset.data.starts(with:[0xff,0xd8]) { ext="jpg" }
                    else if asset.data.starts(with:[0x49,0x49,0x2a,0]) || asset.data.starts(with:[0x4d,0x4d,0,0x2a]) { ext="tiff" }
                    else { throw FormatError.invalid("convert unsupported image assets to PNG before PowerPoint export") }
                    let filename="image\(n)_\(id).\(ext)", path="ppt/media/\(filename)"
                    let url=root.appendingPathComponent(path); try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true); try asset.data.write(to:url)
                    let rid="rIdImage\(id)"; rels += relationship(rid,"image","../media/\(filename)")
                    let c=image.crop
                    let imageTransform=xfrm(o).replacingOccurrences(of:"<a:xfrm ",with:"<a:xfrm flipH=\"\(image.flippedHorizontally ? 1 : 0)\" ")
                    return "<p:pic><p:nvPicPr>\(nv)<p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\(rid)\"/><a:srcRect l=\"\(Int(c.x*100000))\" t=\"\(Int(c.y*100000))\" r=\"\(Int((1-c.maxX)*100000))\" b=\"\(Int((1-c.maxY)*100000))\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>\(imageTransform)<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
                }
                if o.kind == .table, let table=o.table, let columns=table.cells.first?.count, columns > 0 {
                    let grid=(0..<columns).map { _ in "<a:gridCol w=\"\(emu(o.frame.width/Double(columns)))\"/>" }.joined()
                    let rows=table.cells.map { row in "<a:tr h=\"\(emu(o.frame.height/Double(table.cells.count)))\">"+row.map { "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs($0,style:o.textStyle,theme:deck.theme))</a:txBody><a:tcPr/></a:tc>" }.joined()+"</a:tr>" }.joined()
                    return "<p:graphicFrame><p:nvGraphicFramePr>\(nv)<p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"\(emu(o.frame.x))\" y=\"\(emu(o.frame.y))\"/><a:ext cx=\"\(emu(o.frame.width))\" cy=\"\(emu(o.frame.height))\"/></p:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr firstRow=\"1\" bandRow=\"1\"/><a:tblGrid>\(grid)</a:tblGrid>\(rows)</a:tbl></a:graphicData></a:graphic></p:graphicFrame>"
                }
                if o.kind == .chart { warnings.insert("Charts must be flattened to images before export; an unsupported chart was omitted."); return "" }
                let shapes: [ShapeKind:String]=[.rectangle:"rect",.roundedRectangle:"roundRect",.ellipse:"ellipse",.triangle:"triangle",.diamond:"diamond",.star:"star5",.line:"line",.arrow:"rightArrow"]
                let style=o.kind == .text ? "<a:noFill/><a:ln><a:noFill/></a:ln>" : solid(o.style.fill ?? deck.theme.accent)+"<a:ln w=\"\(emu(o.style.strokeWidth))\">\(solid(o.style.stroke))</a:ln>"
                return "<p:sp><p:nvSpPr>\(nv)<p:cNvSpPr txBox=\"\(o.kind == .text ? 1 : 0)\"/><p:nvPr/></p:nvSpPr><p:spPr>\(xfrm(o))<a:prstGeom prst=\"\(shapes[o.shape] ?? "rect")\"><a:avLst/></a:prstGeom>\(style)</p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/><a:lstStyle/>\(paragraphs(o.text,style:o.textStyle,theme:deck.theme))</p:txBody></p:sp>"
            }
            for object in slide.objects { body += try objectXML(object) }
            var transition=""
            if slide.transition.kind != .none { transition="<p:transition spd=\"med\">"+(slide.transition.kind == .fade ? "<p:fade/>" : "<p:push dir=\"l\"/>")+"</p:transition>" }
            try write("ppt/slides/slide\(n).xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:sld xmlns:a=\"\(a)\" xmlns:r=\"\(r)\" xmlns:p=\"\(p)\" show=\"\(slide.skipped ? 0 : 1)\"><p:cSld name=\"\(xml(slide.title))\"><p:bg><p:bgPr>\(solid(slide.background ?? deck.theme.background))<a:effectLst/></p:bgPr></p:bg><p:spTree>\(groupHeader)\(body)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>\(transition)</p:sld>")
            if !slide.notes.isEmpty {
                rels += relationship("rIdNotes","notesSlide","../notesSlides/notesSlide\(n).xml")
                try write("ppt/notesSlides/notesSlide\(n).xml","<p:notes xmlns:a=\"\(a)\" xmlns:r=\"\(r)\" xmlns:p=\"\(p)\"><p:cSld><p:spTree>\(groupHeader)<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Notes\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs(slide.notes,style:TextStyle(),theme:deck.theme))</p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>")
                try write("ppt/notesSlides/_rels/notesSlide\(n).xml.rels",relationships(relationship("rId1","slide","../slides/slide\(n).xml")))
                override("ppt/notesSlides/notesSlide\(n).xml","presentationml.notesSlide")
            }
            try write("ppt/slides/_rels/slide\(n).xml.rels",relationships(rels))
            slideIDs += "<p:sldId id=\"\(256+n)\" r:id=\"rId\(n)\"/>"; presentationRels += relationship("rId\(n)","slide","slides/slide\(n).xml")
            override("ppt/slides/slide\(n).xml","presentationml.slide")
        }
        presentationRels += relationship("rIdMaster","slideMaster","slideMasters/slideMaster1.xml")
        try write("ppt/presentation.xml","<p:presentation xmlns:a=\"\(a)\" xmlns:r=\"\(r)\" xmlns:p=\"\(p)\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rIdMaster\"/></p:sldMasterIdLst><p:sldIdLst>\(slideIDs)</p:sldIdLst><p:sldSz cx=\"\(emu(deck.width))\" cy=\"\(emu(deck.height))\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>")
        try write("ppt/_rels/presentation.xml.rels",relationships(presentationRels))
        let clrMap="<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
        try write("ppt/slideMasters/slideMaster1.xml","<p:sldMaster xmlns:a=\"\(a)\" xmlns:r=\"\(r)\" xmlns:p=\"\(p)\"><p:cSld><p:spTree>\(groupHeader)</p:spTree></p:cSld>\(clrMap)<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rIdLayout\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>")
        try write("ppt/slideMasters/_rels/slideMaster1.xml.rels",relationships(relationship("rIdLayout","slideLayout","../slideLayouts/slideLayout1.xml")+relationship("rIdTheme","theme","../theme/theme1.xml")))
        try write("ppt/slideLayouts/slideLayout1.xml","<p:sldLayout xmlns:a=\"\(a)\" xmlns:r=\"\(r)\" xmlns:p=\"\(p)\" type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\"><p:spTree>\(groupHeader)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>")
        try write("ppt/slideLayouts/_rels/slideLayout1.xml.rels",relationships(relationship("rIdMaster","slideMaster","../slideMasters/slideMaster1.xml")))
        let colors=[("dk1",deck.theme.foreground),("lt1",deck.theme.background),("dk2",RGBA.ink),("lt2",RGBA.white)]+(1...6).map { ("accent\($0)",deck.theme.accent) }+[("hlink",RGBA.accent),("folHlink",RGBA.accent)]
        let scheme=colors.map { "<a:\($0.0)>\(color($0.1))</a:\($0.0)>" }.joined()
        let fonts="<a:latin typeface=\"\(xml(deck.theme.fontName))\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"
        let ph="<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let fills=String(repeating:ph,count:3), lines=String(repeating:"<a:ln w=\"9525\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\">\(ph)<a:prstDash val=\"solid\"/><a:miter lim=\"800000\"/></a:ln>",count:3)
        try write("ppt/theme/theme1.xml","<a:theme xmlns:a=\"\(a)\" name=\"Orator\"><a:themeElements><a:clrScheme name=\"\(xml(deck.theme.name))\">\(scheme)</a:clrScheme><a:fontScheme name=\"Orator\"><a:majorFont>\(fonts)</a:majorFont><a:minorFont>\(fonts)</a:minorFont></a:fontScheme><a:fmtScheme name=\"Orator\"><a:fillStyleLst>\(fills)</a:fillStyleLst><a:lnStyleLst>\(lines)</a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst>\(fills)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>")
        try write("_rels/.rels",relationships(relationship("rId1","officeDocument","ppt/presentation.xml")))
        try write("[Content_Types].xml","<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Default Extension=\"tiff\" ContentType=\"image/tiff\"/>\(overrides)</Types>")
        let archive=root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+".pptx")
        defer { try? FileManager.default.removeItem(at:archive) }
        _ = try run("/usr/bin/zip",["-q","-r",archive.path,"."],directory:root)
        try Data(contentsOf:archive).write(to:destination,options:.atomic)
        return warnings.sorted()
    }
    static func run(_ executable: String,_ args: [String],directory: URL? = nil) throws -> Data {
        let process=Process(); process.executableURL=URL(fileURLWithPath:executable); process.arguments=args; process.currentDirectoryURL=directory
        let output=Pipe(); process.standardOutput=output; process.standardError=FileHandle.nullDevice
        try process.run()
        var data=Data()
        while true {
            let chunk=output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            guard data.count+chunk.count <= 100*1024*1024 else {
                process.terminate(); output.fileHandleForReading.closeFile(); process.waitUntilExit()
                throw FormatError.invalid("Office archive part exceeds the 100 MB size limit")
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FormatError.invalid("Office archive could not be read or written") }; return data
    }
    public static func importDeck(from archive: URL) throws -> ImportResult {
        let listing=try run("/usr/bin/unzip",["-Z1",archive.path])
        guard let names=String(data:listing,encoding:.utf8)?.split(separator:"\n").map(String.init), names.count < 50000 else { throw FormatError.invalid("invalid archive listing") }
        let members=Set(names)
        guard members.contains("ppt/presentation.xml") else { throw FormatError.invalid("not an Office Open XML presentation") }
        var totalBytes=0
        func read(_ path: String) throws -> Data {
            guard !path.hasPrefix("/"), !path.split(separator:"/").contains(".."), members.contains(path) else { throw FormatError.invalid("missing or unsafe Office part: \(path)") }
            let data=try run("/usr/bin/unzip",["-p",archive.path,path]); totalBytes += data.count
            guard data.count < 100*1024*1024, totalBytes < 512*1024*1024 else { throw FormatError.invalid("Office package exceeds the import size limit") }; return data
        }
        func document(_ path: String) throws -> XMLElement {
            let data=try read(path)
            guard let string=String(data:data,encoding:.utf8), !string.uppercased().contains("<!DOCTYPE"), !string.uppercased().contains("<!ENTITY") else { throw FormatError.invalid("unsupported XML declarations") }
            guard let root=try XMLDocument(data:data,options:[]).rootElement() else { throw FormatError.invalid("empty Office XML part") }; return root
        }
        func resolve(_ target: String,relativeTo source: String) throws -> String {
            guard !target.contains(":"), !target.hasPrefix("/") else { throw FormatError.invalid("external Office relationship") }
            var parts=source.split(separator:"/").dropLast().map(String.init)
            for part in target.split(separator:"/") {
                if part == ".." { guard !parts.isEmpty else { throw FormatError.invalid("Office relationship escapes package") }; parts.removeLast() }
                else if part != "." { parts.append(String(part)) }
            }; return parts.joined(separator:"/")
        }
        func relations(_ source: String) throws -> [String:String] {
            let components=source.split(separator:"/").map(String.init)
            let path=components.dropLast().joined(separator:"/")+"/_rels/"+(components.last ?? "")+".rels"
            guard members.contains(path) else { return [:] }
            let root=try document(path); var result: [String:String]=[:]
            for rel in root.elements(forName:"Relationship") where rel.attr("TargetMode") != "External" { result[rel.attr("Id")]=try resolve(rel.attr("Target"),relativeTo:source) }; return result
        }
        let root=try document("ppt/presentation.xml"), rels=try relations("ppt/presentation.xml")
        var deck=Presentation(); deck.slides=[]; deck.title=archive.deletingPathExtension().lastPathComponent
        if let size=root.first("sldSz") { deck.width=size.number("cx",default:12192000)/9525; deck.height=size.number("cy",default:6858000)/9525 }
        var warnings=Set(["Import currently reads direct slide text, shapes, pictures, tables, notes and basic transitions. Master/layout inheritance, rich text runs, charts, media, animations and hyperlinks are not preserved. Keep the original PowerPoint file."])
        for ref in root.descendants("sldId") {
            guard let path=rels[ref.attr("r:id")] else { throw FormatError.invalid("missing slide relationship") }
            let source=try document(path), links=try relations(path)
            var slide=Slide(); slide.title=source.first("cSld")?.attr("name") ?? "Slide"; slide.skipped=source.attr("show") == "0"
            if let bg=source.first("bg")?.first("srgbClr") { slide.background=bg.rgba }
            if source.first("transition")?.first("fade") != nil { slide.transition.kind = .fade }
            if source.first("transition")?.first("push") != nil { slide.transition.kind = .push }
            for node in source.first("spTree")?.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                guard ["sp","pic","graphicFrame"].contains(node.localName ?? "") else { if node.localName == "grpSp" { warnings.insert("Grouped objects were omitted during import.") }; continue }
                let transform=node.first("xfrm"), off=transform?.first("off"), ext=transform?.first("ext")
                let frame=Rect((off?.number("x") ?? 0)/9525,(off?.number("y") ?? 0)/9525,max(1,(ext?.number("cx",default:2857500) ?? 2857500)/9525),max(1,(ext?.number("cy",default:952500) ?? 952500)/9525))
                let geometry=node.first("prstGeom")?.attr("prst") ?? "rect"
                let map: [String:ShapeKind]=["rect":.rectangle,"roundRect":.roundedRectangle,"ellipse":.ellipse,"triangle":.triangle,"diamond":.diamond,"star5":.star,"line":.line,"rightArrow":.arrow]
                let isText=node.first("cNvSpPr")?.attr("txBox") == "1" || node.first("ph") != nil
                var object=SlideObject(kind:isText ? .text : .shape,name:node.first("cNvPr")?.attr("name") ?? "Object",frame:frame)
                object.rotation=(transform?.number("rot") ?? 0)/60000; object.shape=map[geometry] ?? .rectangle
                if let color=node.first("spPr")?.direct("solidFill")?.first("srgbClr") { object.style.fill=color.rgba }
                if let line=node.first("spPr")?.direct("ln") { object.style.strokeWidth=line.number("w")/9525; if let color=line.first("srgbClr") { object.style.stroke=color.rgba } }
                if let textBody=node.direct("txBody") {
                    object.text=textBody.descendants("p").map { $0.descendants("t").map { $0.stringValue ?? "" }.joined() }.joined(separator:"\n")
                    if let props=textBody.first("rPr") ?? textBody.first("defRPr") {
                        object.textStyle.size=max(1,props.number("sz",default:3200)/100); object.textStyle.bold=props.attr("b") == "1"; object.textStyle.italic=props.attr("i") == "1"
                        object.textStyle.underline=props.attr("u") == "sng"
                        if let latin=props.first("latin") { object.textStyle.fontName=latin.attr("typeface") }
                        if let color=props.first("srgbClr") { object.textStyle.color=color.rgba }
                    }
                    if let pPr=textBody.first("pPr") { object.textStyle.alignment=["ctr":.center,"r":.right,"just":.justified][pPr.attr("algn")] ?? .left }
                    if slide.title.isEmpty || slide.title == "Slide" { slide.title=String(object.text.prefix(100)) }
                }
                if node.localName == "pic" {
                    guard let blip=node.first("blip"), let target=links[blip.attr("r:embed")] else { warnings.insert("An externally linked image was omitted."); continue }
                    let asset=Asset(name:URL(fileURLWithPath:target).lastPathComponent,data:try read(target)); deck.assets[asset.id]=asset; object.kind = .image; object.image=ImageContent(assetID:asset.id)
                    if let crop=node.first("srcRect") { let l=crop.number("l")/100000,t=crop.number("t")/100000; object.image?.crop=Rect(l,t,1-l-crop.number("r")/100000,1-t-crop.number("b")/100000) }
                    object.image?.fill=true; object.image?.flippedHorizontally=transform?.attr("flipH") == "1"
                }
                if node.localName == "graphicFrame" {
                    guard let table=node.first("tbl") else { warnings.insert("A chart or unsupported graphic was omitted."); continue }
                    object.kind = .table; var content=TableContent()
                    content.cells=table.descendants("tr").map { $0.descendants("tc").map { $0.descendants("t").map { $0.stringValue ?? "" }.joined(separator:"\n") } }; object.table=content
                }
                slide.objects.append(object)
            }
            if let notesPath=links.values.first(where: { $0.contains("notesSlides/") }) {
                let notes=try document(notesPath)
                slide.notes=notes.descendants("sp").filter { $0.first("ph")?.attr("type") == "body" }.flatMap { $0.descendants("p") }.map { $0.descendants("t").map { $0.stringValue ?? "" }.joined() }.joined(separator:"\n")
            }
            if slide.title.isEmpty { slide.title="Slide \(deck.slides.count+1)" }; deck.slides.append(slide)
        }
        try PresentationFile.validate(deck); return ImportResult(deck:deck,warnings:warnings.sorted())
    }
}
private extension XMLElement {
    func attr(_ name: String) -> String { attribute(forName:name)?.stringValue ?? "" }
    func number(_ name: String,default fallback: Double = 0) -> Double { Double(attr(name)) ?? fallback }
    func direct(_ name: String) -> XMLElement? { children?.compactMap { $0 as? XMLElement }.first { $0.localName == name } }
    func descendants(_ name: String) -> [XMLElement] {
        var result: [XMLElement]=[]
        for child in children?.compactMap({ $0 as? XMLElement }) ?? [] { if child.localName == name { result.append(child) }; result += child.descendants(name) }; return result
    }
    func first(_ name: String) -> XMLElement? { descendants(name).first }
    var rgba: RGBA {
        let raw=UInt32(attr("val"),radix:16) ?? 0
        return RGBA(Double((raw>>16)&255)/255,Double((raw>>8)&255)/255,Double(raw&255)/255,(first("alpha")?.number("val",default:100000) ?? 100000)/100000)
    }
}
