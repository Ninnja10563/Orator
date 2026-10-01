import Foundation
public enum ConnectorKind: String, Codable, CaseIterable, Sendable { case straight, elbow, curved }
public enum ConnectionAnchor: String, Codable, CaseIterable, Sendable { case left, right, top, bottom, center }
public struct ConnectorEndpoint: Codable, Equatable, Sendable {
    public var point: Point
    public var objectID: UUID?
    public var anchor: ConnectionAnchor
    public init(point: Point,objectID: UUID? = nil,anchor: ConnectionAnchor = .center) { self.point=point; self.objectID=objectID; self.anchor=anchor }
}
public struct Connector: Codable, Equatable, Sendable {
    public var kind: ConnectorKind = .straight
    public var start: ConnectorEndpoint
    public var end: ConnectorEndpoint
    public var arrow=true
    public init(start: ConnectorEndpoint,end: ConnectorEndpoint) { self.start=start; self.end=end }
    public var frame: Rect { Rect(min(start.point.x,end.point.x),min(start.point.y,end.point.y),max(1,abs(end.point.x-start.point.x)),max(1,abs(end.point.y-start.point.y))) }
}
public extension Slide {
    func resolvingConnectors() -> Slide {
        var objects: [UUID:SlideObject]=[:]
        func collect(_ list: [SlideObject]) { for object in list { if object.connector == nil { objects[object.id]=object }; collect(object.children) } }; collect(self.objects)
        func endpoint(_ value: ConnectorEndpoint) -> ConnectorEndpoint {
            guard let id=value.objectID, let target=objects[id] else { return value }
            let f=target.frame; var result=value
            switch value.anchor { case .left:result.point=Point(f.x,f.midY); case .right:result.point=Point(f.maxX,f.midY); case .top:result.point=Point(f.midX,f.y); case .bottom:result.point=Point(f.midX,f.maxY); case .center:result.point=Point(f.midX,f.midY) }
            let a=target.rotation * .pi/180, dx=result.point.x-f.midX, dy=result.point.y-f.midY
            result.point=Point(f.midX+dx*cos(a)-dy*sin(a),f.midY+dx*sin(a)+dy*cos(a)); return result
        }
        func resolve(_ list: [SlideObject]) -> [SlideObject] { list.map { original in var object=original; if var c=object.connector { c.start=endpoint(c.start); c.end=endpoint(c.end); object.connector=c; object.frame=c.frame }; object.children=resolve(object.children); return object } }
        var result=self; result.objects=resolve(self.objects); return result
    }
}

public extension ConnectionAnchor {
    func point(on object: SlideObject) -> Point {
        let f=object.frame, value: Point
        switch self { case .left:value=Point(f.x,f.midY); case .right:value=Point(f.maxX,f.midY); case .top:value=Point(f.midX,f.y); case .bottom:value=Point(f.midX,f.maxY); case .center:value=Point(f.midX,f.midY) }
        let angle=object.rotation * .pi/180, dx=value.x-f.midX, dy=value.y-f.midY
        return Point(f.midX+dx*cos(angle)-dy*sin(angle),f.midY+dx*sin(angle)+dy*cos(angle))
    }
}
public extension Connector {
    func hit(_ point: Point,tolerance: Double) -> Bool {
        let a=start.point, b=end.point, mid=(a.x+b.x)/2
        let points: [Point]
        switch kind {
        case .straight:points=[a,b]
        case .elbow:points=[a,Point(mid,a.y),Point(mid,b.y),b]
        case .curved:
            points=(0...48).map { i in
                let t=Double(i)/48, u=1-t
                return Point(u*u*u*a.x+3*u*u*t*mid+3*u*t*t*mid+t*t*t*b.x,u*u*u*a.y+3*u*u*t*a.y+3*u*t*t*b.y+t*t*t*b.y)
            }
        }
        return zip(points,points.dropFirst()).contains { a,b in
            let dx=b.x-a.x, dy=b.y-a.y, length=dx*dx+dy*dy
            let t=length == 0 ? 0 : min(1,max(0,((point.x-a.x)*dx+(point.y-a.y)*dy)/length))
            return hypot(point.x-a.x-t*dx,point.y-a.y-t*dy) <= tolerance
        }
    }
}
