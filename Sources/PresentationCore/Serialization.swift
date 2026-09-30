import Foundation
public enum FormatError: LocalizedError {
    case unsupportedVersion(Int), invalid(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "This presentation uses format version \(version). Update Orator to open it."
        case .invalid(let reason): return "The presentation could not be opened: \(reason)"
        }
    }
}
public enum PresentationFile {
    public static func encode(_ deck: Presentation) throws -> Data {
        try validate(deck)
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]; return try encoder.encode(deck)
    }
    public static func decode(_ data: Data) throws -> Presentation {
        struct Header: Decodable { var formatVersion: Int }
        let header=try JSONDecoder().decode(Header.self,from:data)
        guard header.formatVersion == 1 else { throw FormatError.unsupportedVersion(header.formatVersion) }
        let deck=try JSONDecoder().decode(Presentation.self,from:data); try validate(deck); return deck
    }
    public static func validate(_ deck: Presentation) throws {
        guard deck.width.isFinite, deck.height.isFinite, (100...16384).contains(deck.width), (100...16384).contains(deck.height) else { throw FormatError.invalid("invalid slide dimensions") }
        guard !deck.slides.isEmpty, deck.slides.count <= 10000 else { throw FormatError.invalid("invalid slide count") }
        var ids=Set<UUID>()
        func unique(_ id: UUID) throws { guard ids.insert(id).inserted else { throw FormatError.invalid("duplicate identifier") } }
        func objects(_ list: [SlideObject], depth: Int) throws {
            guard depth < 32 else { throw FormatError.invalid("groups are nested too deeply") }
            for o in list {
                try unique(o.id)
                guard [o.frame.x,o.frame.y,o.frame.width,o.frame.height,o.rotation,o.opacity,o.textStyle.size].allSatisfy(\.isFinite), o.frame.width > 0, o.frame.height > 0, (0...1).contains(o.opacity), (1...1000).contains(o.textStyle.size) else { throw FormatError.invalid("invalid object geometry or style") }
                if let image=o.image {
                    guard deck.assets[image.assetID] != nil else { throw FormatError.invalid("missing image asset") }
                    let c=image.crop
                    guard [c.x,c.y,c.width,c.height].allSatisfy(\.isFinite), c.x >= 0, c.y >= 0, c.width > 0, c.height > 0, c.maxX <= 1.00001, c.maxY <= 1.00001 else { throw FormatError.invalid("invalid image crop") }
                }
                if let chart=o.chart { guard chart.labels.count == chart.values.count, chart.values.allSatisfy(\.isFinite) else { throw FormatError.invalid("invalid chart data") } }
                try objects(o.children,depth:depth+1)
            }
        }
        for slide in deck.slides { try unique(slide.id); try objects(slide.objects,depth:0) }
    }
}
public struct ObjectClipboard: Codable {
    public var objects: [SlideObject]; public var assets: [UUID: Asset]
    public init(objects: [SlideObject], assets: [UUID: Asset]) {
        self.objects=objects
        func assetIDs(_ objects: [SlideObject]) -> [UUID] { objects.flatMap { ($0.image.map { [$0.assetID] } ?? []) + assetIDs($0.children) } }
        let used=Set(assetIDs(objects)); self.assets=assets.filter { used.contains($0.key) }
    }
}
