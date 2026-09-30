import Foundation

public enum EditError: Error { case missingSlide, invalidIndex, lastSlide }
/// Serializable document operations form the boundary for future synchronization.
/// Array order is the authoritative layer order; selection is never serialized.
public enum Edit: Codable, Equatable {
    case insertSlide(Slide, Int)
    case removeSlide(UUID)
    case replaceSlide(Slide)
    case orderSlides([UUID])
    case setTheme(Theme)
    case putAsset(Asset)
    case removeAsset(UUID)
    case batch([Edit])

    @discardableResult public func apply(to deck: inout Presentation) throws -> Edit {
        switch self {
        case let .insertSlide(slide,index):
            guard (0...deck.slides.count).contains(index), !deck.slides.contains(where: { $0.id == slide.id }) else { throw EditError.invalidIndex }
            deck.slides.insert(slide,at:index); return .removeSlide(slide.id)
        case let .removeSlide(id):
            guard deck.slides.count > 1 else { throw EditError.lastSlide }
            guard let i = deck.slides.firstIndex(where: { $0.id == id }) else { throw EditError.missingSlide }
            return .insertSlide(deck.slides.remove(at:i),i)
        case let .replaceSlide(slide):
            guard let i = deck.slides.firstIndex(where: { $0.id == slide.id }) else { throw EditError.missingSlide }
            let old = deck.slides[i]; deck.slides[i]=slide; return .replaceSlide(old)
        case let .orderSlides(ids):
            guard ids.count == deck.slides.count, Set(ids).count == ids.count, Set(ids) == Set(deck.slides.map(\.id)) else { throw EditError.invalidIndex }
            let old = deck.slides.map(\.id); let map = Dictionary(uniqueKeysWithValues: deck.slides.map { ($0.id,$0) })
            deck.slides = ids.compactMap { map[$0] }; return .orderSlides(old)
        case let .setTheme(theme): let old=deck.theme; deck.theme=theme; return .setTheme(old)
        case let .putAsset(asset): let old=deck.assets.updateValue(asset,forKey:asset.id); return old.map(Edit.putAsset) ?? .removeAsset(asset.id)
        case let .removeAsset(id): guard let old=deck.assets.removeValue(forKey:id) else { return .batch([]) }; return .putAsset(old)
        case let .batch(edits):
            var candidate=deck; var inverse: [Edit]=[]
            for edit in edits { inverse.insert(try edit.apply(to:&candidate),at:0) }
            deck=candidate; return .batch(inverse)
        }
    }
}
public enum Alignment { case left, center, right, top, middle, bottom, horizontal, vertical }
public enum Geometry {
    public static func bounds(_ objects: [SlideObject]) -> Rect? { objects.map(\.frame).reduce(nil) { $0?.union($1) ?? $1 } }
    public static func hit(_ point: Point, object: SlideObject) -> Bool {
        guard !object.hidden && !object.locked else { return false }
        let angle = -object.rotation * .pi / 180
        let dx=point.x-object.frame.midX, dy=point.y-object.frame.midY
        return object.frame.contains(Point(object.frame.midX+dx*cos(angle)-dy*sin(angle),object.frame.midY+dx*sin(angle)+dy*cos(angle)))
    }
    public static func aligned(_ objects: [SlideObject], command: Alignment) -> [SlideObject] {
        guard let b=bounds(objects), objects.count > 1 else { return objects }
        var result=objects
        if command == .horizontal || command == .vertical {
            let horizontal=command == .horizontal
            let sorted=result.indices.sorted { horizontal ? result[$0].frame.x < result[$1].frame.x : result[$0].frame.y < result[$1].frame.y }
            let occupied=result.reduce(0.0) { $0 + (horizontal ? $1.frame.width : $1.frame.height) }
            let gap=((horizontal ? b.width : b.height)-occupied)/Double(objects.count-1)
            var cursor=horizontal ? b.x : b.y
            for i in sorted { var f=result[i].frame; if horizontal { f.x=cursor } else { f.y=cursor }; result[i].transform(to:f); cursor += (horizontal ? f.width : f.height)+gap }
        } else {
            for i in result.indices {
                var f=result[i].frame
                switch command {
                case .left: f.x=b.x
                case .center: f.x=b.midX-f.width/2
                case .right: f.x=b.maxX-f.width
                case .top: f.y=b.y
                case .middle: f.y=b.midY-f.height/2
                case .bottom: f.y=b.maxY-f.height
                default: break
                }
                result[i].transform(to:f)
            }
        }
        return result
    }
    public static func snap(_ proposed: Rect, others: [Rect], guides: [Guide], width: Double, height: Double, tolerance: Double) -> (Rect,[Guide]) {
        let xs=[0.0,width/2,width,48,width-48]+others.flatMap { [$0.x,$0.midX,$0.maxX] }+guides.filter(\.vertical).map(\.position)
        let ys=[0.0,height/2,height,48,height-48]+others.flatMap { [$0.y,$0.midY,$0.maxY] }+guides.filter { !$0.vertical }.map(\.position)
        func closest(_ anchors: [Double], _ targets: [Double]) -> (Double,Double)? {
            var best: (Double,Double)?
            for a in anchors { for t in targets where abs(t-a) <= tolerance { if best == nil || abs(t-a) < abs(best!.0) { best=(t-a,t) } } }
            return best
        }
        var r=proposed; var lines: [Guide]=[]
        if let (d,t)=closest([r.x,r.midX,r.maxX],xs) { r.x += d; lines.append(Guide(vertical:true,position:t)) }
        if let (d,t)=closest([r.y,r.midY,r.maxY],ys) { r.y += d; lines.append(Guide(vertical:false,position:t)) }
        return (r,lines)
    }
}
