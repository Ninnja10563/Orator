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
        var mediaTypes: [String:String]=[:]
        func override(_ part: String,_ type: String) { overrides += "<Override PartName=\"/\(part)\" ContentType=\"application/vnd.openxmlformats-officedocument.\(type)+xml\"/>" }
        override("ppt/presentation.xml","presentationml.presentation.main")
        override("ppt/slideMasters/slideMaster1.xml","presentationml.slideMaster")
        override("ppt/slideLayouts/slideLayout1.xml","presentationml.slideLayout")
        override("ppt/theme/theme1.xml","theme")
        for (index,sourceSlide) in deck.slides.enumerated() {
            let slide=deck.resolved(sourceSlide)
            let n=index+1; var rels=relationship("rIdLayout","slideLayout","../slideLayouts/slideLayout1.xml"), body="", objectNumber=1, hyperlinkNumber=0
            var numericIDs: [UUID:Int]=[:], nextObjectID=1
            func indexObjects(_ objects: [SlideObject]) { for object in objects where !object.hidden { if object.kind == .group { indexObjects(object.children) } else { nextObjectID += 1; numericIDs[object.id]=nextObjectID } } }; indexObjects(slide.objects)
            func objectXML(_ o: SlideObject) throws -> String {
                guard !o.hidden else { return "" }
                if o.kind == .group {
                    warnings.insert("Groups are flattened; group rotation is not retained.")
                    return try o.children.map(objectXML).joined()
                }
                objectNumber += 1; let id=objectNumber
                let nv="<p:cNvPr id=\"\(id)\" name=\"\(xml(o.name))\"/>"
                if let connector=o.connector {
                    func connection(_ tag: String,_ endpoint: ConnectorEndpoint) -> String {
                        guard let id=endpoint.objectID.flatMap({ numericIDs[$0] }) else { return "" }; let index: Int
                        switch endpoint.anchor { case .top,.center:index=0; case .left:index=1; case .bottom:index=2; case .right:index=3 }
                        return "<a:\(tag) id=\"\(id)\" idx=\"\(index)\"/>"
                    }
                    let geometry=connector.kind == .straight ? "line" : connector.kind == .elbow ? "bentConnector3" : "curvedConnector3"
                    let transform=xfrm(o).replacingOccurrences(of:"<a:xfrm ",with:"<a:xfrm flipH=\"\(connector.end.point.x < connector.start.point.x ? 1 : 0)\" flipV=\"\(connector.end.point.y < connector.start.point.y ? 1 : 0)\" ")
                    let arrow=connector.arrow ? "<a:tailEnd type=\"triangle\" w=\"med\" len=\"med\"/>" : ""
                    return "<p:cxnSp><p:nvCxnSpPr>\(nv)<p:cNvCxnSpPr>\(connection("stCxn",connector.start))\(connection("endCxn",connector.end))</p:cNvCxnSpPr><p:nvPr/></p:nvCxnSpPr><p:spPr>\(transform)<a:prstGeom prst=\"\(geometry)\"><a:avLst/></a:prstGeom><a:ln w=\"\(emu(max(1,o.style.strokeWidth)))\">\(solid(o.style.stroke))\(arrow)</a:ln></p:spPr></p:cxnSp>"
                }
                if o.opacity < 1 && [.chart,.table,.video,.audio].contains(o.kind) { warnings.insert("Table, chart and media object opacity is not retained in PowerPoint export.") }
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
                    let imageTransform=xfrm(o).replacingOccurrences(of:"<a:xfrm ",with:"<a:xfrm flipH=\"\(image.flippedHorizontally ? 1 : 0)\" flipV=\"\(image.flippedVertically == true ? 1 : 0)\" ")
                    return "<p:pic><p:nvPicPr>\(nv)<p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\(rid)\"><a:alphaModFix amt=\"\(Int(o.opacity*100000))\"/></a:blip><a:srcRect l=\"\(Int(c.x*100000))\" t=\"\(Int(c.y*100000))\" r=\"\(Int((1-c.maxX)*100000))\" b=\"\(Int((1-c.maxY)*100000))\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>\(imageTransform)<a:prstGeom prst=\"\(image.mask == .ellipse ? "ellipse" : image.mask == .roundedRectangle ? "roundRect" : "rect")\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
                }
                if o.kind == .table, let table=o.table, let columns=table.cells.first?.count, columns > 0 {
                    return "<p:graphicFrame><p:nvGraphicFramePr>\(nv)<p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"\(emu(o.frame.x))\" y=\"\(emu(o.frame.y))\"/><a:ext cx=\"\(emu(o.frame.width))\" cy=\"\(emu(o.frame.height))\"/></p:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\">\(tableXML(table,object:o,theme:deck.theme))</a:graphicData></a:graphic></p:graphicFrame>"
                }
                if let media=o.media, let asset=deck.assets[media.assetID] {
                    let ext=URL(fileURLWithPath:asset.name).pathExtension.lowercased()
                    let types=["mp4":"video/mp4","m4v":"video/mp4","mov":"video/quicktime","mp3":"audio/mpeg","m4a":"audio/mp4","wav":"audio/wav","aiff":"audio/aiff","aif":"audio/aiff"]
                    guard let mime=types[ext] else { throw FormatError.invalid("unsupported PowerPoint media extension: \(ext)") }
                    mediaTypes[ext]=mime
                    let filename="media\(n)_\(id).\(ext)", target=root.appendingPathComponent("ppt/media/"+filename)
                    try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true); try asset.data.write(to:target)
                    let rid="rIdMedia\(id)", embed="rIdEmbed\(id)", posterID="rIdPoster\(id)"
                    rels += relationship(rid,o.kind == .video ? "video" : "audio","../media/"+filename)
                    rels += "<Relationship Id=\"\(embed)\" Type=\"http://schemas.microsoft.com/office/2007/relationships/media\" Target=\"../media/\(xml(filename))\"/>"
                    let poster=media.posterAssetID.flatMap { deck.assets[$0]?.data } ?? Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
                    let posterName="poster\(n)_\(id).png"; try poster.write(to:root.appendingPathComponent("ppt/media/"+posterName)); rels += relationship(posterID,"image","../media/"+posterName)
                    warnings.insert("Audio/video assets are embedded. Orator trim, fade, loop and automatic playback settings are not exported; configure playback in PowerPoint.")
                    let kind=o.kind == .video ? "videoFile" : "audioFile"
                    return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"\(xml(o.name))\"><a:hlinkClick r:id=\"\" action=\"ppaction://media\"/></p:cNvPr><p:cNvPicPr/><p:nvPr><a:\(kind) r:link=\"\(rid)\"/><p:extLst><p:ext uri=\"{DAA4B4D4-6D71-4841-9C94-3DE7FCFB33CC}\"><p14:media xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" r:embed=\"\(embed)\"/></p:ext></p:extLst></p:nvPr></p:nvPicPr><p:blipFill><a:blip r:embed=\"\(posterID)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>\(xfrm(o))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
                }
                if let chart=o.chart, o.kind == .chart {
                    let name="chart\(n)_\(id)", rid="rIdChart\(id)"
                    try write("ppt/charts/\(name).xml",chartXML(chart,theme:deck.theme)); override("ppt/charts/\(name).xml","drawingml.chart")
                    try writeWorkbook(chart,to:root.appendingPathComponent("ppt/embeddings/\(name).xlsx")); mediaTypes["xlsx"]="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                    try write("ppt/charts/_rels/\(name).xml.rels",relationships(relationship("rIdWorkbook","package","../embeddings/\(name).xlsx")))
                    rels += relationship(rid,"chart","../charts/\(name).xml")
                    return "<p:graphicFrame><p:nvGraphicFramePr>\(nv)<p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"\(emu(o.frame.x))\" y=\"\(emu(o.frame.y))\"/><a:ext cx=\"\(emu(o.frame.width))\" cy=\"\(emu(o.frame.height))\"/></p:xfrm><a:graphic><a:graphicData uri=\"\(chartNS)\"><c:chart xmlns:c=\"\(chartNS)\" r:id=\"\(rid)\"/></a:graphicData></a:graphic></p:graphicFrame>"
                }
                let shapes: [ShapeKind:String]=[.rectangle:"rect",.roundedRectangle:"roundRect",.ellipse:"ellipse",.circle:"ellipse",.polygon:"hexagon",.doubleArrow:"line",.speechBubble:"wedgeRoundRectCallout",.triangle:"triangle",.diamond:"diamond",.star:"star5",.line:"line",.arrow:"line"]
                let style=objectStyleXML(o,theme:deck.theme)
                return "<p:sp><p:nvSpPr>\(nv)<p:cNvSpPr txBox=\"\(o.kind == .text ? 1 : 0)\"/><p:nvPr/></p:nvSpPr><p:spPr>\(xfrm(o))<a:prstGeom prst=\"\(shapes[o.shape] ?? "rect")\"><a:avLst/></a:prstGeom>\(style)</p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/><a:lstStyle/>\(paragraphs(o.text,style:o.textStyle,theme:deck.theme,runs:o.textRuns,opacity:o.opacity,hyperlink:{ target in hyperlinkNumber += 1; let id="rIdLink\(hyperlinkNumber)"; rels += "<Relationship Id=\"\(id)\" Type=\"\(r)/hyperlink\" Target=\"\(xml(target))\" TargetMode=\"External\"/>"; return id }))</p:txBody></p:sp>"
            }
            for object in slide.objects { body += try objectXML(object) }
            if !(slide.animations ?? []).isEmpty { warnings.insert("Object animations are not exported to PowerPoint yet.") }
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
        try write("[Content_Types].xml","<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Default Extension=\"tiff\" ContentType=\"image/tiff\"/>\(mediaTypes.sorted { $0.key < $1.key }.map { "<Default Extension=\"\(xml($0.key))\" ContentType=\"\(xml($0.value))\"/>" }.joined())\(overrides)</Types>")
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

}
extension XMLElement {
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
