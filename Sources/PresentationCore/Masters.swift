import Foundation

public struct MasterLayout: Codable, Equatable, Identifiable, Sendable {
    public var id=UUID()
    public var name: String
    public var objects: [SlideObject]
    public init(name: String, objects: [SlideObject]) { self.name=name; self.objects=objects }
}
public struct SlideMaster: Codable, Equatable, Identifiable, Sendable {
    public var id=UUID()
    public var name="Default Master"
    public var background: RGBA? = nil
    public var objects: [SlideObject]=[]
    public var layouts: [MasterLayout]=[]
    public var titleFont=TextStyle()
    public var bodyFont=TextStyle()
    public init() { titleFont.size=48; titleFont.bold=true; bodyFont.size=30 }
    public var slide: Slide {
        var slide=Slide(); slide.id=id; slide.title=name; slide.background=background; slide.objects=objects; return slide
    }
}
public extension Presentation {
    func master(for slide: Slide) -> SlideMaster? { masters?.first { $0.id == slide.masterID } }
    func resolved(_ slide: Slide) -> Slide {
        guard let master=master(for:slide) else { return slide }
        var resolved=slide
        resolved.background=slide.background ?? master.background
        var inherited=master.objects
        if let layout=master.layouts.first(where: { $0.id == slide.layoutID }) { inherited += layout.objects }
        let overrides=Set(slide.objects.compactMap(\.placeholderKey))
        inherited.removeAll { $0.placeholderKey.map(overrides.contains) ?? false }
        resolved.objects=inherited+slide.objects
        return resolved
    }
}
