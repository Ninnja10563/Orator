import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension PowerPoint {
    static func timingXML(_ slide: Slide,ids: [UUID:Int],width: Double,height: Double) -> String {
        let schedule=AnimationEngine.schedule(slide.animations ?? []).filter { ids[$0.animation.objectID] != nil }
        func allObjects(_ objects: [SlideObject]) -> [SlideObject] { objects.flatMap { [$0]+allObjects($0.children) } }
        let mediaObjects=allObjects(slide.objects).filter { $0.media != nil && ids[$0.id] != nil }
        guard !schedule.isEmpty || !mediaObjects.isEmpty else { return "" }
        var nextID=2
        func identifier() -> Int { nextID += 1; return nextID }
        func find(_ id: UUID,in objects: [SlideObject]) -> SlideObject? {
            for object in objects { if object.id == id { return object }; if let nested=find(id,in:object.children) { return nested } }; return nil
        }
        func effect(_ entry: ScheduledAnimation) -> String {
            let animation=entry.animation, target=ids[animation.objectID]!, outerID=identifier()
            let nodeType=animation.start == .onClick ? "clickEffect" : animation.start == .withPrevious ? "withEffect" : "afterEffect"
            let category=animation.effect.entrance ? "entr" : animation.effect.exit ? "exit" : animation.effect == .motionPath ? "path" : "emph"
            let duration=max(1,Int((animation.duration*1000).rounded()))
            func behavior(_ attribute: String? = nil,reverse: Bool = false) -> String {
                let names=attribute.map { "<p:attrNameLst><p:attrName>\($0)</p:attrName></p:attrNameLst>" } ?? ""
                return "<p:cBhvr><p:cTn id=\"\(identifier())\" dur=\"\(reverse ? max(1,duration/2) : duration)\" fill=\"hold\"\(reverse ? " autoRev=\"1\"" : "")/><p:tgtEl><p:spTgt spid=\"\(target)\"/></p:tgtEl>\(names)</p:cBhvr>"
            }
            var body=""
            switch animation.effect {
            case .appear,.disappear:
                body="<p:set>\(behavior("style.visibility"))<p:to><p:strVal val=\"\(animation.effect == .appear ? "visible" : "hidden")\"/></p:to></p:set>"
            case .fadeIn,.fadeOut,.flyIn,.flyOut,.zoomIn,.zoomOut,.wipeIn:
                let direction: String
                switch animation.direction { case .left:direction="Left"; case .right:direction="Right"; case .up:direction="Top"; case .down:direction="Bottom" }
                let filter: String
                switch animation.effect {
                case .flyIn,.flyOut:filter="slide(from\(direction))"
                case .zoomIn,.zoomOut:filter="zoom(in)"
                case .wipeIn:filter="wipe(\(direction.lowercased()))"
                default:filter="fade"
                }
                body="<p:animEffect transition=\"\(animation.effect.exit ? "out" : "in")\" filter=\"\(filter)\">\(behavior())</p:animEffect>"
            case .spin: body="<p:animRot by=\"21600000\">\(behavior("r"))</p:animRot>"
            case .grow,.pulse:
                let amount=animation.effect == .pulse ? 112000 : 125000
                body="<p:animScale>\(behavior(nil,reverse:animation.effect == .pulse))<p:by x=\"\(amount)\" y=\"\(amount)\"/></p:animScale>"
            case .colorChange: body="<p:animClr clrSpc=\"rgb\" dir=\"cw\">\(behavior("fillcolor"))<p:to>\(color(animation.targetColor))</p:to></p:animClr>"
            case .motionPath:
                let object=find(animation.objectID,in:slide.objects), center=Point(object?.frame.midX ?? 0,object?.frame.midY ?? 0)
                let points=animation.path.count > 1 ? animation.path : [center,center]
                func coordinates(_ p: Point) -> String { "\((p.x-center.x)/width) \((p.y-center.y)/height)" }
                var path="M \(coordinates(points[0])) "
                for index in 0..<(points.count-1) {
                    if animation.curvedPath == true && points.count > 2 {
                        let previous=points[max(0,index-1)], start=points[index], end=points[index+1], next=points[min(points.count-1,index+2)]
                        let c1=Point(start.x+(end.x-previous.x)/6,start.y+(end.y-previous.y)/6), c2=Point(end.x-(next.x-start.x)/6,end.y-(next.y-start.y)/6)
                        path += "C \(coordinates(c1)) \(coordinates(c2)) \(coordinates(end)) "
                    } else { path += "L \(coordinates(points[index+1])) " }
                }
                body="<p:animMotion origin=\"layout\" path=\"\(path)E\" pathEditMode=\"relative\">\(behavior())</p:animMotion>"
            }
            return "<p:par><p:cTn id=\"\(outerID)\" presetClass=\"\(category)\" fill=\"hold\" nodeType=\"\(nodeType)\"><p:stCondLst><p:cond delay=\"\(Int((entry.start*1000).rounded()))\"/></p:stCondLst><p:childTnLst>\(body)</p:childTnLst></p:cTn></p:par>"
        }
        var groups=""
        for click in Array(Set(schedule.map(\.click))).sorted() {
            let groupID=identifier(), children=schedule.filter { $0.click == click }.map(effect).joined()
            groups += "<p:par><p:cTn id=\"\(groupID)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"\(click == 0 ? "0" : "indefinite")\"/></p:stCondLst><p:childTnLst>\(children)</p:childTnLst></p:cTn></p:par>"
        }
        let mediaNodes=mediaObjects.map { object -> String in
            let media=object.media!, target=ids[object.id]!, kind=object.kind == .video ? "video" : "audio"
            let condition=media.autoplay ? "<p:cond delay=\"0\"/>" : "<p:cond evt=\"onClick\" delay=\"0\"><p:tgtEl><p:spTgt spid=\"\(target)\"/></p:tgtEl></p:cond>"
            return "<p:\(kind)><p:cMediaNode vol=\"\(Int((media.volume*100000).rounded()))\" numSld=\"\(media.acrossSlides ? 999 : 1)\" showWhenStopped=\"1\"><p:cTn id=\"\(identifier())\" dur=\"media\" fill=\"hold\"\(media.loop ? " repeatCount=\"indefinite\"" : "")><p:stCondLst>\(condition)</p:stCondLst></p:cTn><p:tgtEl><p:spTgt spid=\"\(target)\"/></p:tgtEl></p:cMediaNode></p:\(kind)>"
        }.joined()
        return "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst><p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>\(groups)</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst><p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>\(mediaNodes)</p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
    }
    static func readAnimations(_ source: XMLElement,ids: [String:UUID],objects: [SlideObject],width: Double,height: Double) -> ([ObjectAnimation],Bool) {
        guard let timing=source.direct("timing") else { return ([],false) }
        var result: [ObjectAnimation]=[], unsupported=false
        func find(_ id: UUID,in objects: [SlideObject]) -> SlideObject? { for object in objects { if object.id == id { return object }; if let child=find(id,in:object.children) { return child } }; return nil }
        for node in timing.descendants("cTn") where ["clickEffect","withEffect","afterEffect"].contains(node.attr("nodeType")) {
            guard let shape=node.first("spTgt"), let objectID=ids[shape.attr("spid")] else { unsupported=true; continue }
            var animation=ObjectAnimation(objectID:objectID,effect:.appear)
            animation.start=node.attr("nodeType") == "withEffect" ? .withPrevious : node.attr("nodeType") == "afterEffect" ? .afterPrevious : .onClick
            var behavior: XMLElement?
            if let effect=node.first("animEffect") {
                let filter=effect.attr("filter").lowercased(), exit=effect.attr("transition") == "out"
                if filter == "fade" { animation.effect=exit ? .fadeOut : .fadeIn }
                else if filter.hasPrefix("slide(") { animation.effect=exit ? .flyOut : .flyIn }
                else if filter.hasPrefix("zoom(") { animation.effect=exit ? .zoomOut : .zoomIn }
                else if filter.hasPrefix("wipe(") && !exit { animation.effect = .wipeIn }
                else { unsupported=true; continue }
                if filter.contains("right") { animation.direction = .right }; if filter.contains("top") { animation.direction = .up }; if filter.contains("bottom") { animation.direction = .down }
                behavior=effect.first("cTn")
            } else if let rotate=node.first("animRot") { animation.effect = .spin; behavior=rotate.first("cTn"); if rotate.number("by") != 21600000 { unsupported=true } }
            else if let scale=node.first("animScale") { behavior=scale.first("cTn"); animation.effect=behavior?.attr("autoRev") == "1" ? .pulse : .grow }
            else if let color=node.first("animClr") { animation.effect = .colorChange; behavior=color.first("cTn"); animation.targetColor=color.direct("to")?.officeColor(palette:[:]) ?? .accent }
            else if let motion=node.first("animMotion"), let object=find(objectID,in:objects) {
                animation.effect = .motionPath; behavior=motion.first("cTn")
                let parsed=readMotionPath(motion.attr("path"),center:Point(object.frame.midX,object.frame.midY),width:width,height:height)
                animation.path=parsed.0; animation.curvedPath=false; unsupported = unsupported || !parsed.1
            } else if let set=node.first("set"), set.first("attrName")?.stringValue == "style.visibility" { animation.effect=set.first("strVal")?.attr("val") == "hidden" ? .disappear : .appear; behavior=set.first("cTn") }
            else { unsupported=true; continue }
            let milliseconds=behavior?.number("dur",default:500) ?? 500
            animation.duration=min(60,max(0,milliseconds/1000*(animation.effect == .pulse ? 2 : 1)))
            let start=max(0,node.direct("stCondLst")?.first("cond")?.number("delay") ?? 0)/1000
            let prior=AnimationEngine.schedule(result).last
            let base=animation.start == .withPrevious ? prior?.start ?? 0 : animation.start == .afterPrevious ? prior?.end ?? 0 : 0
            animation.delay=min(86400,max(0,start-base)); result.append(animation)
        }
        if result.isEmpty && !timing.descendants("spTgt").isEmpty { unsupported=true }
        return (result,unsupported)
    }
    /// Preserve imported cubic geometry as closely sampled editable path points.
    static func readMotionPath(_ path: String,center: Point,width: Double,height: Double) -> ([Point],Bool) {
        let pattern="[MLCZEm lcze]|[-+]?(?:[0-9]*\\.)?[0-9]+(?:[eE][-+]?[0-9]+)?"
        guard let regex=try? NSRegularExpression(pattern:pattern.replacingOccurrences(of:" ",with:"")) else { return ([],false) }
        let text=path as NSString, tokens=regex.matches(in:path,range:NSRange(location:0,length:text.length)).map { text.substring(with:$0.range) }
        var index=0, point=Point(), start=Point(), result: [Point]=[]
        func convert(_ p: Point) -> Point { Point(center.x+p.x*width,center.y+p.y*height) }
        func pair() -> Point? { guard index+1 < tokens.count, let x=Double(tokens[index]), let y=Double(tokens[index+1]), x.isFinite,y.isFinite else { return nil }; index += 2; return Point(x,y) }
        while index < tokens.count && result.count < 10000 {
            let command=tokens[index]; index += 1
            if command.uppercased() == "E" { return (result,true) }
            if command.uppercased() == "Z" { point=start; result.append(convert(point)); continue }
            let relative=command == command.lowercased()
            func positioned(_ p: Point) -> Point { relative ? Point(point.x+p.x,point.y+p.y) : p }
            guard let raw=pair() else { return (result,false) }; let first=positioned(raw)
            if command.uppercased() == "C" {
                guard let raw2=pair(), let raw3=pair() else { return (result,false) }
                let second=positioned(raw2), end=positioned(raw3), origin=point
                for sample in 1...24 { let t=Double(sample)/24,u=1-t; result.append(convert(Point(u*u*u*origin.x+3*u*u*t*first.x+3*u*t*t*second.x+t*t*t*end.x,u*u*u*origin.y+3*u*u*t*first.y+3*u*t*t*second.y+t*t*t*end.y))) }; point=end
            } else if ["M","L"].contains(command.uppercased()) { point=first; if command.uppercased() == "M" { start=point }; result.append(convert(point)) }
            else { return (result,false) }
        }; return (result,index == tokens.count)
    }
}
