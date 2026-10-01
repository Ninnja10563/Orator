import Foundation
import AVFoundation
import PresentationCore

/// Called by background file operations. Read duration once per embedded asset, then
/// translate Office's tail offset into the editor's absolute trim end.
enum MediaMetadata {
    static func resolve(_ deck: inout Presentation) throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("OratorMetadata-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        var durations: [UUID:Double]=[:]
        let assets=deck.assets
        func resolveObjects(_ objects: inout [SlideObject]) throws {
            for index in objects.indices {
                if var media=objects[index].media {
                    if durations[media.assetID] == nil, let asset=assets[media.assetID] {
                        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                        let ext=(asset.name as NSString).pathExtension
                        let url=directory.appendingPathComponent(asset.id.uuidString).appendingPathExtension(ext)
                        try asset.data.write(to:url)
                        let duration=AVURLAsset(url:url).duration.seconds
                        if duration.isFinite && duration > 0 { durations[media.assetID]=duration }
                    }
                    if let duration=durations[media.assetID] {
                        media.sourceDuration=duration
                        if let tail=media.trimEndOffset { media.trimEnd=max(media.trimStart+0.001,duration-tail); media.trimEndOffset=nil }
                    }
                    objects[index].media=media
                }
                try resolveObjects(&objects[index].children)
            }
        }
        for i in deck.slides.indices { try resolveObjects(&deck.slides[i].objects) }
        if var masters=deck.masters { for i in masters.indices { try resolveObjects(&masters[i].objects); for j in masters[i].layouts.indices { try resolveObjects(&masters[i].layouts[j].objects) } }; deck.masters=masters }
    }
}
