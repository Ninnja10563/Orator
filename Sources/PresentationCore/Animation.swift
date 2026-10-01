import Foundation

public enum AnimationEffect: String, Codable, CaseIterable, Sendable {
    case appear, fadeIn, flyIn, zoomIn, wipeIn, pulse, grow, spin, colorChange, disappear, fadeOut, flyOut, zoomOut, motionPath
    public var entrance: Bool { [.appear,.fadeIn,.flyIn,.zoomIn,.wipeIn].contains(self) }
    public var exit: Bool { [.disappear,.fadeOut,.flyOut,.zoomOut].contains(self) }
}
public enum AnimationStart: String, Codable, CaseIterable, Sendable { case onClick, withPrevious, afterPrevious }
public enum MotionDirection: String, Codable, CaseIterable, Sendable { case left, right, up, down }
public struct ObjectAnimation: Codable, Equatable, Identifiable, Sendable {
    public var id=UUID()
    public var objectID: UUID
    public var effect: AnimationEffect
    public var start: AnimationStart = .onClick
    public var delay: Double = 0
    public var duration: Double = 0.5
    public var direction: MotionDirection = .left
    public var targetColor: RGBA = .accent
    /// Absolute slide positions for the object's center, linearly interpolated between points.
    public var path: [Point] = []
    public init(objectID: UUID, effect: AnimationEffect) { self.objectID=objectID; self.effect=effect }
}
public struct ScheduledAnimation: Equatable, Sendable {
    public var animation: ObjectAnimation
    public var click: Int
    public var start: Double
    public var end: Double { start+animation.duration }
}
public enum AnimationEngine {
    public static func schedule(_ animations: [ObjectAnimation]) -> [ScheduledAnimation] {
        var result: [ScheduledAnimation]=[], click=0
        for animation in animations {
            let previous=result.last
            if animation.start == .onClick { click += 1 }
            let base: Double
            if animation.start == .onClick { base=0 }
            else if animation.start == .withPrevious { base=previous?.start ?? 0 }
            else { base=previous?.end ?? 0 }
            result.append(ScheduledAnimation(animation:animation,click:click,start:base+animation.delay))
        }
        return result
    }
    public static func frame(slide: Slide, click: Int, elapsed: Double, width: Double, height: Double, reducedMotion: Bool = false) -> Slide {
        var result=slide
        for item in schedule(slide.animations ?? []) {
            guard let i=result.objects.firstIndex(where: { $0.id == item.animation.objectID }) else { continue }
            let a=item.animation
            let progress: Double
            if item.click > click { progress=0 }
            else if item.click < click { progress=1 }
            else { progress=min(1,max(0,(elapsed-item.start)/max(0.001,a.duration))) }
            let started=item.click < click || (item.click == click && elapsed >= item.start)
            let t=progress*progress*(3-2*progress)
            var object=result.objects[i]
            if a.effect.entrance && !started { object.opacity=0; result.objects[i]=object; continue }
            if !started { continue }
            switch a.effect {
            case .appear: break
            case .fadeIn: object.opacity *= t
            case .wipeIn:
                let f=object.frame
                switch a.direction {
                case .left: object.animationClip=Rect(f.x,f.y,f.width*t,f.height)
                case .right: object.animationClip=Rect(f.maxX-f.width*t,f.y,f.width*t,f.height)
                case .up: object.animationClip=Rect(f.x,f.y,f.width,f.height*t)
                case .down: object.animationClip=Rect(f.x,f.maxY-f.height*t,f.width,f.height*t)
                }
            case .fadeOut: object.opacity *= 1-t
            case .disappear: object.opacity=0
            case .flyIn, .flyOut:
                if !reducedMotion {
                    let distance=a.effect == .flyIn ? 1-t : t
                    let dx=a.direction == .left ? -width : a.direction == .right ? width : 0
                    let dy=a.direction == .up ? -height : a.direction == .down ? height : 0
                    var frame=object.frame; frame.x += dx*distance; frame.y += dy*distance; object.transform(to:frame)
                }
                object.opacity *= a.effect == .flyIn ? t : 1-t
            case .zoomIn, .zoomOut, .grow, .pulse:
                let scale: Double
                if reducedMotion { scale=1 }
                else if a.effect == .zoomIn { scale=max(0.01,t) }
                else if a.effect == .zoomOut { scale=max(0.01,1-t) }
                else if a.effect == .grow { scale=1+0.25*t }
                else { scale=1+0.12*sin(t * .pi) }
                let f=object.frame; object.transform(to:Rect(f.midX-f.width*scale/2,f.midY-f.height*scale/2,f.width*scale,f.height*scale))
                if a.effect == .zoomOut { object.opacity *= 1-t }
            case .spin: if !reducedMotion { object.rotation += 360*t }
            case .colorChange:
                let from=object.style.fill ?? .accent, to=a.targetColor
                object.style.fill=RGBA(from.red+(to.red-from.red)*t,from.green+(to.green-from.green)*t,from.blue+(to.blue-from.blue)*t)
            case .motionPath:
                if !reducedMotion, a.path.count > 1 {
                    let position=t*Double(a.path.count-1), segment=min(a.path.count-2,Int(position)), fraction=position-Double(segment)
                    let p=a.path[segment], q=a.path[segment+1], f=object.frame
                    object.transform(to:Rect(p.x+(q.x-p.x)*fraction-f.width/2,p.y+(q.y-p.y)*fraction-f.height/2,f.width,f.height))
                }
            }
            result.objects[i]=object
        }
        return result
    }
    /// Continuity matches persistent motion identities, leaving copied object IDs unique.
    public static func interpolate(from: Slide, to: Slide, progress: Double) -> Slide {
        let t=min(1,max(0,progress)); var result=to; result.masterID=nil
        let old=Dictionary(from.objects.map { ($0.motionID ?? $0.id,$0) },uniquingKeysWith:{ first,_ in first })
        for i in result.objects.indices {
            let target=result.objects[i]
            guard let source=old[target.motionID ?? target.id] else { result.objects[i].opacity *= t; continue }
            func mix(_ a: Double,_ b: Double) -> Double { a+(b-a)*t }
            let a=source.frame,b=target.frame
            result.objects[i].transform(to:Rect(mix(a.x,b.x),mix(a.y,b.y),mix(a.width,b.width),mix(a.height,b.height)))
            result.objects[i].rotation=mix(source.rotation,target.rotation); result.objects[i].opacity=mix(source.opacity,target.opacity)
        }
        let matched=Set(to.objects.map { $0.motionID ?? $0.id })
        result.objects += from.objects.filter { !matched.contains($0.motionID ?? $0.id) }.map { var o=$0; o.opacity *= 1-t; return o }
        return result
    }
}
