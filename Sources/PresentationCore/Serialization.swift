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
        guard (1...2).contains(header.formatVersion) else { throw FormatError.unsupportedVersion(header.formatVersion) }
        var deck=try JSONDecoder().decode(Presentation.self,from:data); deck.formatVersion=2; try validate(deck); return deck
    }
    public static func validate(_ deck: Presentation) throws {
        guard deck.width.isFinite, deck.height.isFinite, (100...16384).contains(deck.width), (100...16384).contains(deck.height) else { throw FormatError.invalid("invalid slide dimensions") }
        guard !deck.slides.isEmpty, deck.slides.count <= 10000 else { throw FormatError.invalid("invalid slide count") }
        guard deck.formatVersion == 2 else { throw FormatError.unsupportedVersion(deck.formatVersion) }
        func validColor(_ color: RGBA) -> Bool { [color.red,color.green,color.blue,color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
        guard [deck.theme.background,deck.theme.foreground,deck.theme.accent].allSatisfy(validColor) else { throw FormatError.invalid("invalid theme colors") }
        for (id,asset) in deck.assets { guard id == asset.id, asset.data.count <= 100*1024*1024 else { throw FormatError.invalid("invalid asset identifier or size") } }
        var ids=Set<UUID>()
        func unique(_ id: UUID) throws { guard ids.insert(id).inserted else { throw FormatError.invalid("duplicate identifier") } }
        func objects(_ list: [SlideObject], depth: Int) throws {
            guard depth < 32 else { throw FormatError.invalid("groups are nested too deeply") }
            for o in list {
                try unique(o.id)
                guard [o.frame.x,o.frame.y,o.frame.width,o.frame.height,o.rotation,o.opacity,o.textStyle.size].allSatisfy(\.isFinite), o.frame.width > 0, o.frame.height > 0, (0...1).contains(o.opacity), (1...1000).contains(o.textStyle.size) else { throw FormatError.invalid("invalid object geometry or style") }
                guard abs(o.frame.x) <= 1_000_000, abs(o.frame.y) <= 1_000_000, o.frame.width <= 1_000_000, o.frame.height <= 1_000_000,
                      abs(o.rotation) <= 360_000, o.style.strokeWidth.isFinite, (0...10000).contains(o.style.strokeWidth),
                      o.style.cornerRadius.isFinite, (0...1_000_000).contains(o.style.cornerRadius),
                      o.textStyle.lineSpacing.isFinite, (0...10000).contains(o.textStyle.lineSpacing),
                      validColor(o.style.stroke), o.style.fill.map(validColor) ?? true, o.textStyle.color.map(validColor) ?? true else { throw FormatError.invalid("object style is outside supported bounds") }
                if o.kind == .image && o.image == nil { throw FormatError.invalid("image object has no asset reference") }
                if let gradient=o.style.gradient { guard validColor(gradient.end), gradient.angle.isFinite, abs(gradient.angle) <= 360000 else { throw FormatError.invalid("invalid gradient") } }
                if let shadow=o.style.shadow { guard validColor(shadow.color), [shadow.blur,shadow.x,shadow.y].allSatisfy({ $0.isFinite && abs($0) <= 10000 }), shadow.blur >= 0 else { throw FormatError.invalid("invalid shadow") } }
                try RichText.validateStyle(o.textStyle)
                if let runs=o.textRuns { try RichText.validate(runs,text:o.text) }
                if let table=o.table {
                    guard !table.cells.isEmpty, table.cells.count <= 1000, let columns=table.cells.first?.count, (1...100).contains(columns), table.cells.allSatisfy({ $0.count == columns }) else { throw FormatError.invalid("invalid table dimensions") }
                    for weights in [table.rowHeights,table.columnWidths] { if let weights=weights { guard weights.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw FormatError.invalid("invalid table weights") } } }
                    guard table.rowHeights.map({ $0.count == table.cells.count }) ?? true, table.columnWidths.map({ $0.count == columns }) ?? true else { throw FormatError.invalid("table weight count mismatch") }
                    for (key,style) in table.styles ?? [:] {
                        let coordinates=key.split(separator:":").compactMap { Int($0) }
                        guard coordinates.count == 2, table.cells.indices.contains(coordinates[0]), (0..<columns).contains(coordinates[1]), style.padding.isFinite, (0...10000).contains(style.padding), style.borderWidth.isFinite, (0...10000).contains(style.borderWidth), style.fill.map(validColor) ?? true, style.border.map(validColor) ?? true else { throw FormatError.invalid("invalid table cell style") }
                        if let text=style.textStyle { try RichText.validateStyle(text) }
                    }
                    var checked=TableContent(rows:table.cells.count,columns:columns)
                    for merge in table.merges ?? [] { try checked.merge(merge) }
                }
                if let media=o.media {
                    guard deck.assets[media.assetID] != nil, media.trimStart.isFinite, media.trimStart >= 0, media.trimEnd.map({ $0.isFinite && $0 > media.trimStart }) ?? true, media.volume.isFinite, (0...1).contains(media.volume), media.fadeIn.isFinite, media.fadeOut.isFinite, media.fadeIn >= 0, media.fadeOut >= 0 else { throw FormatError.invalid("invalid media settings") }
                }
                if let image=o.image {
                    guard deck.assets[image.assetID] != nil, image.originalAssetID.map({ deck.assets[$0] != nil }) ?? true else { throw FormatError.invalid("missing image asset") }
                    let c=image.crop
                    guard [c.x,c.y,c.width,c.height].allSatisfy(\.isFinite), c.x >= 0, c.y >= 0, c.width > 0, c.height > 0, c.maxX <= 1.00001, c.maxY <= 1.00001 else { throw FormatError.invalid("invalid image crop") }
                }
                if let chart=o.chart {
                    guard chart.labels.count == chart.values.count, chart.values.count <= 10000, chart.dataSeries.count <= 32, chart.values.allSatisfy({ $0.isFinite && abs($0) <= 1e12 }), chart.dataSeries.allSatisfy({ $0.values.count == chart.labels.count && $0.values.allSatisfy({ $0.isFinite && abs($0) <= 1e12 }) && ($0.color.map(validColor) ?? true) }) else { throw FormatError.invalid("invalid chart data") }
                }
                try objects(o.children,depth:depth+1)
            }
        }
        for master in deck.masters ?? [] { try unique(master.id); try objects(master.objects,depth:0); for layout in master.layouts { try unique(layout.id); try objects(layout.objects,depth:0) } }
        for slide in deck.slides {
            try unique(slide.id)
            guard slide.background.map(validColor) ?? true, slide.transition.duration.isFinite, (0...60).contains(slide.transition.duration),
                  slide.transition.advanceAfter.map({ $0.isFinite && $0 > 0 && $0 <= 86400 }) ?? true,
                  slide.guides.allSatisfy({ $0.position.isFinite && abs($0.position) <= 1_000_000 }) else { throw FormatError.invalid("invalid slide style or timing") }
            let objectIDs=Set(slide.objects.flatMap(\.descendantIDs))
            for animation in slide.animations ?? [] {
                guard objectIDs.contains(animation.objectID), animation.duration.isFinite, (0...60).contains(animation.duration), animation.delay.isFinite, (0...86400).contains(animation.delay), animation.path.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw FormatError.invalid("invalid animation") }
            }
            try objects(slide.objects,depth:0)
        }
    }
}
public struct ObjectClipboard: Codable {
    public var objects: [SlideObject]; public var assets: [UUID: Asset]
    public init(objects: [SlideObject], assets: [UUID: Asset]) {
        self.objects=objects
        func assetIDs(_ objects: [SlideObject]) -> [UUID] {
            var result: [UUID]=[]
            for object in objects {
                if let image=object.image { result.append(image.assetID); if let original=image.originalAssetID { result.append(original) } }
                if let media=object.media { result.append(media.assetID); if let poster=media.posterAssetID { result.append(poster) } }
                result += assetIDs(object.children)
            }; return result
        }
        let used=Set(assetIDs(objects)); self.assets=assets.filter { used.contains($0.key) }
    }
}

public struct SlideClipboard: Codable {
    public var slides: [Slide]
    public var assets: [UUID: Asset]
    public init(slides: [Slide], assets: [UUID: Asset]) {
        self.slides=slides
        self.assets=ObjectClipboard(objects:slides.flatMap(\.objects),assets:assets).assets
    }
}
