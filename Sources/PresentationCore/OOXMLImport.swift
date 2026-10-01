import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension PowerPoint {
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
        var documents: [String:XMLElement]=[:]
        func document(_ path: String) throws -> XMLElement {
            if let cached=documents[path] { return cached }
            let data=try read(path)
            guard let string=String(data:data,encoding:.utf8), !string.uppercased().contains("<!DOCTYPE"), !string.uppercased().contains("<!ENTITY") else { throw FormatError.invalid("unsupported XML declarations") }
            guard let root=try XMLDocument(data:data,options:[]).rootElement() else { throw FormatError.invalid("empty Office XML part") }; documents[path]=root; return root
        }
        func resolve(_ target: String,relativeTo source: String) throws -> String {
            guard !target.contains(":"), !target.hasPrefix("/") else { throw FormatError.invalid("external Office relationship") }
            var parts=source.split(separator:"/").dropLast().map(String.init)
            for part in target.split(separator:"/") {
                if part == ".." { guard !parts.isEmpty else { throw FormatError.invalid("Office relationship escapes package") }; parts.removeLast() }
                else if part != "." { parts.append(String(part)) }
            }; return parts.joined(separator:"/")
        }
        func relations(_ source: String,includeHyperlinks: Bool = false) throws -> [String:String] {
            let components=source.split(separator:"/").map(String.init)
            let path=components.dropLast().joined(separator:"/")+"/_rels/"+(components.last ?? "")+".rels"
            guard members.contains(path) else { return [:] }
            let root=try document(path); var result: [String:String]=[:]
            for rel in root.elements(forName:"Relationship") {
                if rel.attr("TargetMode") == "External" { if includeHyperlinks && rel.attr("Type").hasSuffix("/hyperlink") { result[rel.attr("Id")]=rel.attr("Target") }; continue }
                result[rel.attr("Id")]=try resolve(rel.attr("Target"),relativeTo:source)
            }; return result
        }
        let root=try document("ppt/presentation.xml"), rels=try relations("ppt/presentation.xml")
        var deck=Presentation(); deck.slides=[]; deck.title=archive.deletingPathExtension().lastPathComponent
        var importedAssets: [String:Asset]=[:]
        func loadAsset(_ path: String) throws -> Asset { if let cached=importedAssets[path] { return cached }; let value=Asset(name:URL(fileURLWithPath:path).lastPathComponent,data:try read(path)); importedAssets[path]=value; return value }
        if let size=root.first("sldSz") { deck.width=size.number("cx",default:12192000)/9525; deck.height=size.number("cy",default:6858000)/9525 }
        var warnings=Set(["Import currently reads direct slide text, shapes, pictures, tables, notes and basic transitions. Master and layout appearances are resolved into editable slide objects. Master relationships and animations are not retained. Media playback settings may need adjustment. Keep the original PowerPoint file."])
        for ref in root.descendants("sldId") {
            guard let path=rels[ref.attr("r:id")] else { throw FormatError.invalid("missing slide relationship") }
            let source=try document(path), links=try relations(path), textLinks=try relations(path,includeHyperlinks:true)
            let layoutPath=links.values.first { $0.contains("slideLayouts/") }
            let layout=try layoutPath.map(document), layoutLinks=try layoutPath.map { try relations($0,includeHyperlinks:true) } ?? [:]
            let masterPath=layoutLinks.values.first { $0.contains("slideMasters/") }
            let master=try masterPath.map(document), masterLinks=try masterPath.map { try relations($0,includeHyperlinks:true) } ?? [:]
            let themePath=masterLinks.values.first { $0.contains("theme/") }, theme=try themePath.map(document)
            var palette: [String:RGBA]=[:]
            for item in theme?.first("clrScheme")?.children?.compactMap({ $0 as? XMLElement }) ?? [] { palette[item.localName ?? ""]=item.officeColor(palette:[:]) }
            let map=master?.first("clrMap")
            for alias in ["bg1","bg2","tx1","tx2"] { palette[alias]=palette[map?.attr(alias) ?? ""] }
            let titleFont=theme?.first("majorFont")?.first("latin")?.attr("typeface") ?? "Helvetica Neue", bodyFont=theme?.first("minorFont")?.first("latin")?.attr("typeface") ?? "Helvetica Neue"
            if deck.slides.isEmpty { deck.theme=Theme(name:theme?.attr("name") ?? "Imported",background:palette["bg1"] ?? palette["lt1"] ?? .white,foreground:palette["tx1"] ?? palette["dk1"] ?? .ink,accent:palette["accent1"] ?? .accent,fontName:bodyFont); deck.theme.chartColors=(1...6).compactMap { palette["accent\($0)"] } }
            var slide=Slide(); slide.title=source.first("cSld")?.attr("name") ?? "Slide"; slide.skipped=source.attr("show") == "0"
            slide.background=(source.first("bg") ?? layout?.first("bg") ?? master?.first("bg"))?.officeColor(palette:palette) ?? palette["bg1"]
            if source.first("transition")?.first("fade") != nil { slide.transition.kind = .fade }
            if source.first("transition")?.first("push") != nil { slide.transition.kind = .push }
            var shapeIDs: [String:UUID]=[:], attachments: [UUID:(String,String,Int,Int)]=[:]
            var nodes: [(XMLElement,[String:String],Bool)]=[]
            for (owner,relationships) in [(master,masterLinks),(layout,layoutLinks)] {
                if source.attr("showMasterSp") != "0" { nodes += (owner?.first("spTree")?.children?.compactMap { $0 as? XMLElement } ?? []).filter { $0.first("ph") == nil }.map { ($0,relationships,true) } }
            }
            nodes += (source.first("spTree")?.children?.compactMap { $0 as? XMLElement } ?? []).map { ($0,links,false) }
            func parseNode(_ node: XMLElement,objectLinks: [String:String],inherited: Bool,depth: Int = 0) throws -> SlideObject? {
                guard depth < 32 else { throw FormatError.invalid("Office groups are nested too deeply") }
                if node.localName == "grpSp" {
                    let transform=node.direct("grpSpPr")?.direct("xfrm"), off=transform?.direct("off"), ext=transform?.direct("ext"), childOff=transform?.direct("chOff"), childExt=transform?.direct("chExt")
                    let frame=Rect((off?.number("x") ?? 0)/9525,(off?.number("y") ?? 0)/9525,max(1,(ext?.number("cx") ?? 9525)/9525),max(1,(ext?.number("cy") ?? 9525)/9525))
                    var group=SlideObject(kind:.group,name:node.direct("nvGrpSpPr")?.first("cNvPr")?.attr("name") ?? "Group",frame:frame)
                    group.rotation=(transform?.number("rot") ?? 0)/60000
                    if !inherited { shapeIDs[node.direct("nvGrpSpPr")?.first("cNvPr")?.attr("id") ?? ""]=group.id }
                    for child in node.children?.compactMap({ $0 as? XMLElement }) ?? [] { if let object=try parseNode(child,objectLinks:objectLinks,inherited:inherited,depth:depth+1) { group.children.append(object) } }
                    group.frame=Rect((childOff?.number("x") ?? 0)/9525,(childOff?.number("y") ?? 0)/9525,max(0.001,(childExt?.number("cx") ?? 9525)/9525),max(0.001,(childExt?.number("cy") ?? 9525)/9525))
                    group.transform(to:frame); return group
                }
                func placeholder(in owner: XMLElement?) -> XMLElement? {
                    guard let ph=node.first("ph") else { return nil }
                    return owner?.first("spTree")?.descendants("sp").first { candidate in guard let other=candidate.first("ph") else { return false }; if !ph.attr("idx").isEmpty { return ph.attr("idx") == other.attr("idx") }; return ph.attr("type") == other.attr("type") }
                }
                let layoutShape=inherited ? nil : placeholder(in:layout), masterShape=inherited ? nil : placeholder(in:master)
                guard ["sp","pic","graphicFrame","cxnSp"].contains(node.localName ?? "") else { return nil }
                let transform=node.first("xfrm") ?? layoutShape?.first("xfrm") ?? masterShape?.first("xfrm"), off=transform?.first("off"), ext=transform?.first("ext")
                let frame=Rect((off?.number("x") ?? 0)/9525,(off?.number("y") ?? 0)/9525,max(1,(ext?.number("cx",default:2857500) ?? 2857500)/9525),max(1,(ext?.number("cy",default:952500) ?? 952500)/9525))
                let geometry=node.first("prstGeom")?.attr("prst") ?? "rect"
                let map: [String:ShapeKind]=["rect":.rectangle,"roundRect":.roundedRectangle,"ellipse":.ellipse,"hexagon":.polygon,"leftRightArrow":.doubleArrow,"wedgeRoundRectCallout":.speechBubble,"triangle":.triangle,"diamond":.diamond,"star5":.star,"line":.line,"rightArrow":.arrow]
                let isText=node.first("cNvSpPr")?.attr("txBox") == "1" || node.first("ph") != nil
                var object=SlideObject(kind:isText ? .text : .shape,name:node.first("cNvPr")?.attr("name") ?? "Object",frame:frame)
                object.rotation=(transform?.number("rot") ?? 0)/60000; object.shape=map[geometry] ?? .rectangle
                if let fill=node.first("spPr")?.direct("solidFill") ?? node.first("style")?.first("fillRef") { object.style.fill=fill.officeColor(palette:palette) }
                if node.first("spPr")?.direct("noFill") != nil { object.style.fill=RGBA(0,0,0,0) }
                if let line=node.first("spPr")?.direct("ln") { object.style.strokeWidth=line.number("w")/9525; if let color=line.officeColor(palette:palette) { object.style.stroke=color } }
                readObjectEffects(node,object:&object,palette:palette)
                if geometry == "line", node.first("tailEnd")?.attr("type") == "triangle" { object.shape=node.first("headEnd")?.attr("type") == "triangle" ? .doubleArrow : .arrow }
                if !inherited { shapeIDs[node.first("cNvPr")?.attr("id") ?? ""]=object.id }
                if node.localName == "cxnSp" {
                    let flipX=transform?.attr("flipH") == "1", flipY=transform?.attr("flipV") == "1"
                    var connector=Connector(start:ConnectorEndpoint(point:Point(flipX ? frame.maxX : frame.x,flipY ? frame.maxY : frame.y)),end:ConnectorEndpoint(point:Point(flipX ? frame.x : frame.maxX,flipY ? frame.y : frame.maxY)))
                    connector.kind=geometry.hasPrefix("bent") ? .elbow : geometry.hasPrefix("curved") ? .curved : .straight; connector.arrow=node.first("tailEnd")?.attr("type") == "triangle"; object.connector=connector; object.shape = .line
                    attachments[object.id]=(node.first("stCxn")?.attr("id") ?? "",node.first("endCxn")?.attr("id") ?? "",Int(node.first("stCxn")?.number("idx") ?? 0),Int(node.first("endCxn")?.number("idx") ?? 0))
                }
                if let textBody=node.direct("txBody") {
                    let type=node.first("ph")?.attr("type") ?? "body", isTitle=["title","ctrTitle"].contains(type)
                    var base=object.textStyle; base.fontName=isTitle ? titleFont : bodyFont; base.color=palette["tx1"] ?? .ink
                    for source in [master?.first("txStyles")?.direct(isTitle ? "titleStyle" : "bodyStyle")?.direct("lvl1pPr")?.direct("defRPr"),masterShape?.first("defRPr"),layoutShape?.first("defRPr")] {
                        if let source=source { if source.number("sz") > 0 { base.size=source.number("sz")/75 }; if let color=source.officeColor(palette:palette) { base.color=color } }
                    }
                    let imported=readText(textBody,defaultStyle:base,links:inherited ? objectLinks : textLinks,palette:palette)
                    object.text=imported.0; object.textRuns=imported.1; if let first=imported.1.first { object.textStyle=first.style }
                    if slide.title.isEmpty || slide.title == "Slide" { slide.title=String(object.text.prefix(100)) }
                }
                if node.localName == "pic" {
                    guard let blip=node.first("blip"), let target=objectLinks[blip.attr("r:embed")] else { warnings.insert("An externally linked image was omitted."); return nil }
                    let asset=try loadAsset(target); deck.assets[asset.id]=asset; object.kind = .image; object.image=ImageContent(assetID:asset.id)
                    if let crop=node.first("srcRect") { let l=crop.number("l")/100000,t=crop.number("t")/100000; object.image?.crop=Rect(l,t,1-l-crop.number("r")/100000,1-t-crop.number("b")/100000) }
                    object.opacity=(node.first("blip")?.first("alphaModFix")?.number("amt",default:100000) ?? 100000)/100000; object.image?.fill=true; object.image?.flippedHorizontally=transform?.attr("flipH") == "1"; object.image?.flippedVertically=transform?.attr("flipV") == "1"; object.image?.mask=geometry == "ellipse" ? .ellipse : geometry == "roundRect" ? .roundedRectangle : .rectangle
                    if let reference=node.first("videoFile") ?? node.first("audioFile"), let target=objectLinks[reference.attr("r:link")] {
                        let mediaAsset=try loadAsset(target); deck.assets[mediaAsset.id]=mediaAsset
                        object.kind=reference.localName == "videoFile" ? .video : .audio
                        object.media=MediaContent(assetID:mediaAsset.id); object.media?.posterAssetID=asset.id; object.image=nil
                    }
                }
                if node.localName == "graphicFrame" {
                    if let table=node.first("tbl") { object.kind = .table; object.table=try readTable(table,style:object.textStyle,links:textLinks) }
                    else if let chart=node.first("chart"), let target=objectLinks[chart.attr("r:id")] { object.kind = .chart; object.chart=try readChart(document(target)) }
                    else { warnings.insert("An unsupported graphic was omitted."); return nil }
                }
                return object
            }
            for (node,objectLinks,inherited) in nodes { if let object=try parseNode(node,objectLinks:objectLinks,inherited:inherited) { slide.objects.append(object) } }
            func connect(_ objects: inout [SlideObject]) {
                for i in objects.indices {
                    if let (start,end,s,e)=attachments[objects[i].id] { let anchors: [ConnectionAnchor]=[.top,.left,.bottom,.right]; objects[i].connector?.start.objectID=shapeIDs[start]; objects[i].connector?.end.objectID=shapeIDs[end]; objects[i].connector?.start.anchor=anchors[max(0,min(3,s))]; objects[i].connector?.end.anchor=anchors[max(0,min(3,e))] }
                    connect(&objects[i].children)
                }
            }; connect(&slide.objects)
            if let notesPath=links.values.first(where: { $0.contains("notesSlides/") }) {
                let notes=try document(notesPath)
                slide.notes=notes.descendants("sp").filter { $0.first("ph")?.attr("type") == "body" }.flatMap { $0.descendants("p") }.map { $0.descendants("t").map { $0.stringValue ?? "" }.joined() }.joined(separator:"\n")
            }
            if slide.title.isEmpty { slide.title="Slide \(deck.slides.count+1)" }; deck.slides.append(slide)
        }
        try PresentationFile.validate(deck); return ImportResult(deck:deck,warnings:warnings.sorted())
    }
}
