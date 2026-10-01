import Foundation

public struct Point: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double
    public init(_ x: Double = 0, _ y: Double = 0) { self.x = x; self.y = y }
}
public struct Rect: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }; public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }; public var midY: Double { y + height / 2 }
    public func contains(_ p: Point) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }
    public func intersects(_ r: Rect) -> Bool { x <= r.maxX && maxX >= r.x && y <= r.maxY && maxY >= r.y }
    public func union(_ r: Rect) -> Rect {
        Rect(min(x,r.x), min(y,r.y), max(maxX,r.maxX)-min(x,r.x), max(maxY,r.maxY)-min(y,r.y))
    }
}
public struct RGBA: Codable, Equatable, Sendable {
    public var red: Double; public var green: Double; public var blue: Double; public var alpha: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { red=r; green=g; blue=b; alpha=a }
    public static let ink = RGBA(0.09,0.11,0.14)
    public static let white = RGBA(1,1,1)
    public static let accent = RGBA(0.17,0.34,0.78)
}
public enum ShapeKind: String, Codable, CaseIterable, Sendable {
    case rectangle, roundedRectangle, circle, ellipse, triangle, diamond, polygon, star, line, arrow, doubleArrow, speechBubble
}
public enum ObjectKind: String, Codable, Sendable { case text, shape, image, table, chart, group, video, audio }
public enum TextAlignment: String, Codable, CaseIterable, Sendable { case left, center, right, justified }
public enum TextFit: String, Codable, CaseIterable, Sendable { case fixed, shrink, expand, clip }
public struct TextStyle: Codable, Equatable, Sendable {
    public var fontName = "Helvetica Neue"
    public var size: Double = 32
    public var bold = false; public var italic = false; public var underline = false
    public var strikethrough: Bool? = nil
    public var highlight: RGBA? = nil
    public var tracking: Double? = nil
    public var hyperlink: String? = nil
    public var paragraph: ParagraphSettings? = nil
    public var alignment: TextAlignment = .left
    public var color: RGBA? = nil
    public var lineSpacing: Double = 4
    public var fit: TextFit = .fixed
    public init() {}
}
public struct ObjectStyle: Codable, Equatable, Sendable {
    public var fill: RGBA? = nil
    public var stroke = RGBA(0,0,0,0)
    public var strokeWidth: Double = 0
    public var cornerRadius: Double = 16
    public var borderPattern: BorderPattern? = nil
    public var gradient: GradientFill? = nil
    public var shadow: ObjectShadow? = nil
    public init() {}
}
public enum ImageMask: String, Codable, CaseIterable, Sendable { case rectangle, roundedRectangle, ellipse }
public struct ImageContent: Codable, Equatable, Sendable {
    public var assetID: UUID
    /// Normalized source rectangle. Original bytes remain in the asset store.
    public var crop = Rect(0,0,1,1)
    public var flippedHorizontally = false
    public var flippedVertically: Bool? = nil
    public var mask: ImageMask? = nil
    public var originalAssetID: UUID? = nil
    public var fill = false
    public init(assetID: UUID) { self.assetID = assetID }
}
public struct TableContent: Codable, Equatable, Sendable {
    public var cells: [[String]]
    public var rowHeights: [Double]? = nil
    public var columnWidths: [Double]? = nil
    public var merges: [CellMerge]? = nil
    public var styles: [String:CellStyle]? = nil
    public init(rows: Int = 3, columns: Int = 3) { cells = (0..<rows).map { r in (0..<columns).map { c in r == 0 ? "Column \(c+1)" : "" } } }
}
public enum ChartKind: String, Codable, CaseIterable, Sendable { case bar, column, line, pie, area, scatter }
public struct ChartContent: Codable, Equatable, Sendable {
    public var kind: ChartKind = .column
    public var labels = ["Q1", "Q2", "Q3", "Q4"]
    public var values: [Double] = [24, 38, 31, 52]
    public var series: [ChartSeries]? = nil
    public var showLegend: Bool? = nil
    public var showGridlines: Bool? = nil
    public var showDataLabels: Bool? = nil
    public var categoryAxisTitle: String? = nil
    public var valueAxisTitle: String? = nil
    public var title = "Results"
    public init() {}
}
public struct SlideObject: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var kind: ObjectKind
    public var frame: Rect
    public var rotation: Double = 0
    public var opacity: Double = 1
    public var hidden = false; public var locked = false
    public var style = ObjectStyle()
    public var text = ""
    public var textStyle = TextStyle()
    public var textRuns: [TextRun]? = nil
    public var placeholderKey: String? = nil
    public var layoutLinked: Bool? = nil
    public var masterTextLinked: Bool? = nil
    public var motionID: UUID? = nil
    public var animationClip: Rect? = nil
    public var shape: ShapeKind = .rectangle
    public var image: ImageContent? = nil
    public var connector: Connector? = nil
    public var media: MediaContent? = nil
    public var table: TableContent? = nil
    public var chart: ChartContent? = nil
    /// Children use slide coordinates; transforms are applied recursively as one edit.
    public var children: [SlideObject] = []
    public init(kind: ObjectKind, name: String, frame: Rect) { self.kind=kind; self.name=name; self.frame=frame }
    public var descendantIDs: [UUID] { [id]+children.flatMap(\.descendantIDs) }
    public func duplicated(offset: Point = Point(24,24)) -> SlideObject {
        var copy = self; copy.motionID=motionID ?? id; copy.id = UUID(); copy.frame.x += offset.x; copy.frame.y += offset.y
        copy.children = children.map { $0.duplicated(offset: offset) }; return copy
    }
    public static func duplicateBatch(_ originals: [SlideObject],offset: Point = Point(24,24)) -> [SlideObject] {
        var copies=originals.map { $0.duplicated(offset:offset) }
        let mapping=Dictionary(uniqueKeysWithValues:zip(originals.flatMap(\.descendantIDs),copies.flatMap(\.descendantIDs)).map { ($0,$1) })
        func remap(_ object: inout SlideObject) {
            if let id=object.connector?.start.objectID, let mapped=mapping[id] { object.connector?.start.objectID=mapped }
            if let id=object.connector?.end.objectID, let mapped=mapping[id] { object.connector?.end.objectID=mapped }
            for i in object.children.indices { remap(&object.children[i]) }
        }
        for i in copies.indices { remap(&copies[i]) }; return copies
    }
    public mutating func transform(to newFrame: Rect) {
        let old = frame
        if old != newFrame { layoutLinked=false }
        let sx = newFrame.width / max(old.width,0.001), sy = newFrame.height / max(old.height,0.001)
        for i in children.indices {
            let f = children[i].frame
            children[i].transform(to: Rect(newFrame.x+(f.x-old.x)*sx, newFrame.y+(f.y-old.y)*sy, f.width*sx, f.height*sy))
        }
        if var c=connector {
            c.start.point=Point(newFrame.x+(c.start.point.x-old.x)*sx,newFrame.y+(c.start.point.y-old.y)*sy)
            c.end.point=Point(newFrame.x+(c.end.point.x-old.x)*sx,newFrame.y+(c.end.point.y-old.y)*sy); connector=c
        }
        frame = newFrame
    }
}
public enum TransitionKind: String, Codable, CaseIterable, Sendable { case none, fade, dissolve, push, wipe, slide, zoom, continuity }
public struct Transition: Codable, Equatable, Sendable {
    public var kind: TransitionKind = .none
    public var direction: MotionDirection? = nil
    public var advanceOnClick: Bool? = nil
    public var duration: Double = 0.4
    public var advanceAfter: Double? = nil
    public init() {}
}
public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID(); public var objectID: UUID?; public var author: String; public var text: String
    public var resolved = false; public var replies: [String] = []
    public init(text: String, author: String, objectID: UUID? = nil) { self.text=text; self.author=author; self.objectID=objectID }
}
public struct Guide: Codable, Equatable, Sendable {
    public var vertical: Bool; public var position: Double
    public init(vertical: Bool, position: Double) { self.vertical=vertical; self.position=position }
}
public struct Slide: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID(); public var title = "Untitled Slide"; public var section = ""
    public var layout: Layout = .blank
    public var masterID: UUID? = nil
    public var layoutID: UUID? = nil
    public var objects: [SlideObject] = []
    public var background: RGBA? = nil
    public var notes = ""; public var skipped = false
    public var transition = Transition()
    public var animations: [ObjectAnimation]? = nil
    public var guides: [Guide] = []
    public var comments: [Comment] = []
    public init() {}
    public func duplicated() -> Slide {
        var copy = self; copy.id = UUID(); copy.objects = SlideObject.duplicateBatch(objects,offset:Point())
        let mapping=Dictionary(uniqueKeysWithValues:zip(objects.flatMap(\.descendantIDs),copy.objects.flatMap(\.descendantIDs)).map { ($0,$1) })
        copy.animations=animations?.map { animation in var result=animation; result.id=UUID(); result.objectID=mapping[animation.objectID] ?? animation.objectID; return result }
        copy.comments = []; return copy
    }
}
public struct Theme: Codable, Equatable, Sendable {
    public var name: String; public var background: RGBA; public var foreground: RGBA; public var accent: RGBA
    public var fontName: String
    public init(name: String, background: RGBA, foreground: RGBA, accent: RGBA, fontName: String = "Helvetica Neue") {
        self.name=name; self.background=background; self.foreground=foreground; self.accent=accent; self.fontName=fontName
    }
    public static let studio = Theme(name: "Studio", background: .white, foreground: .ink, accent: .accent)
    public static let midnight = Theme(name: "Midnight", background: RGBA(0.08,0.10,0.14), foreground: .white, accent: RGBA(0.49,0.68,1))
    public static let paper = Theme(name: "Paper", background: RGBA(0.97,0.95,0.90), foreground: RGBA(0.19,0.20,0.16), accent: RGBA(0.32,0.43,0.29))
    public static let all = [studio, midnight, paper]
}
public struct Asset: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID(); public var name: String; public var data: Data
    public init(name: String, data: Data) { self.name=name; self.data=data }
}
public struct Presentation: Codable, Equatable, Sendable {
    public var formatVersion = 2
    public var id = UUID()
    public var title = "Untitled"
    public var width: Double = 1280; public var height: Double = 720
    public var theme = Theme.studio
    public var slides: [Slide] = [Layout.title.makeSlide()]
    public var assets: [UUID: Asset] = [:]
    public var masters: [SlideMaster]? = [SlideMaster()]
    public init() { slides[0].masterID=masters?.first?.id }
}
public enum Layout: String, Codable, CaseIterable, Sendable {
    case title = "Title", titleContent = "Title and Content", section = "Section", twoColumns = "Two Columns", comparison = "Comparison", titleOnly = "Title Only", imageText = "Image and Text", blank = "Blank"
    public func makeSlide() -> Slide {
        var slide = Slide(); slide.layout = self
        func text(_ name: String, _ value: String, _ rect: Rect, _ size: Double, _ bold: Bool = false) -> SlideObject {
            var o = SlideObject(kind: .text,name: name,frame: rect); o.text=value; o.textStyle.size=size; o.textStyle.bold=bold; return o
        }
        switch self {
        case .title:
            slide.title = "Your next great idea"
            slide.objects = [text("Title",slide.title,Rect(96,232,1088,150),72,true), text("Subtitle","A presentation by you",Rect(100,414,1000,72),30)]
        case .section:
            slide.title = "A new chapter"; slide.objects = [text("Title",slide.title,Rect(96,270,1088,180),64,true)]
        case .titleContent, .twoColumns, .comparison, .imageText, .titleOnly:
            slide.title = "Slide title"
            slide.objects = [text("Title",slide.title,Rect(80,56,1120,100),48,true),text("Content","Add your ideas here",Rect(80,190,[.twoColumns,.comparison,.imageText].contains(self) ? 520 : 1120,440),30)]
            if self == .twoColumns || self == .comparison { slide.objects.append(text("Content","A second perspective",Rect(680,190,520,440),30)) }
            if self == .titleOnly { slide.objects.removeLast() }
            if self == .imageText { var placeholder=SlideObject(kind:.shape,name:"Image Placeholder",frame:Rect(680,190,520,440)); placeholder.style.fill=RGBA(0.90,0.91,0.93); slide.objects.append(placeholder) }
        case .blank: slide.title = "Blank Slide"
        }
        return slide
    }
}
