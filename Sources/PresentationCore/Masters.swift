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
    func resolvedContent(_ slide: Slide) -> Slide {
        guard let master=master(for:slide) else { return slide }
        let layout=master.layouts.first { $0.id == slide.layoutID }; var result=slide
        for i in result.objects.indices {
            if result.objects[i].layoutLinked == true, let key=result.objects[i].placeholderKey, let template=layout?.objects.first(where: { $0.placeholderKey == key }) { result.objects[i].transform(to:template.frame); result.objects[i].layoutLinked=true }
            if result.objects[i].masterTextLinked == true { result.objects[i].textStyle=result.objects[i].placeholderKey == "title" ? master.titleFont : master.bodyFont }
        }; return result
    }
    func resolved(_ original: Slide) -> Slide {
        let slide=resolvedContent(original)
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
