import AppKit
import AVFoundation
import AVKit
import PresentationCore

final class MediaForegroundView: NSView {
    var object: SlideObject
    var deck: Presentation
    var slideRect: NSRect
    init(object: SlideObject, deck: Presentation, rect: NSRect, frame: NSRect) { self.object=object; self.deck=deck; slideRect=rect; super.init(frame:frame); autoresizingMask=[.width,.height] }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        slideRect.clip(); let transform=NSAffineTransform(); transform.translateX(by:slideRect.minX,yBy:slideRect.minY); transform.scaleX(by:slideRect.width/deck.width,yBy:slideRect.height/deck.height); transform.concat()
        SlideRenderer.shared.draw(object:object,deck:deck)
    }
}
final class MediaPlayback {
    struct Entry {
        var objectID: UUID
        var settings: MediaContent
        var player: AVPlayer
        var view: AVPlayerView
        var endToken: NSObjectProtocol?
        var boundaryToken: Any?
        var fadeToken: Any?
        var wasPlaying=false
    }
    private var entries: [Entry]=[]
    private var foreground: [MediaForegroundView]=[]
    private let directory=FileManager.default.temporaryDirectory.appendingPathComponent("OratorMedia-"+UUID().uuidString)
    func assetURL(_ id: UUID, deck: Presentation) throws -> URL {
        guard let asset=deck.assets[id] else { throw FormatError.invalid("missing media asset") }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let ext=URL(fileURLWithPath:asset.name).pathExtension
        let url=directory.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath:url.path) { try asset.data.write(to:url,options:.atomic) }
        return url
    }
    func install(slide: Slide, deck: Presentation, in parent: NSView, rect: NSRect, forceAutoplay: Bool = false) throws {
        stop(keepingBackground:true)
        var aboveVideo=false
        for object in deck.resolved(slide).objects where !object.hidden {
            guard let content=object.media else {
                if aboveVideo { let overlay=MediaForegroundView(object:object,deck:deck,rect:rect,frame:parent.bounds); parent.addSubview(overlay); foreground.append(overlay) }; continue
            }
            aboveVideo = aboveVideo || object.kind == .video
            if entries.contains(where: { $0.objectID == object.id }) { continue }
            let player=AVPlayer(url:try assetURL(content.assetID,deck:deck)); player.volume=Float(content.volume)
            let view=AVPlayerView(); view.player=player; view.controlsStyle = .inline; view.showsFullScreenToggleButton=false
            view.wantsLayer=true; view.layer?.opacity=Float(object.opacity); view.setAccessibilityLabel(object.name)
            view.frame=NSRect(x:rect.minX+object.frame.x*rect.width/deck.width,y:rect.minY+object.frame.y*rect.height/deck.height,width:object.frame.width*rect.width/deck.width,height:object.frame.height*rect.height/deck.height)
            if object.kind == .video || !content.autoplay { parent.addSubview(view) }
            func atEnd() {
                player.pause()
                if content.loop { player.seek(to:CMTime(seconds:content.trimStart,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) { complete in if complete { player.play() } } }
            }
            let token=NotificationCenter.default.addObserver(forName:AVPlayerItem.didPlayToEndTimeNotification,object:player.currentItem,queue:.main) { _ in atEnd() }
            var entry=Entry(objectID:object.id,settings:content,player:player,view:view,endToken:token)
            if let end=content.trimEnd { entry.boundaryToken=player.addBoundaryTimeObserver(forTimes:[NSValue(time:CMTime(seconds:end,preferredTimescale:600))],queue:.main,using:atEnd) }
            if content.fadeIn > 0 || content.fadeOut > 0 {
                entry.fadeToken=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.05,preferredTimescale:600),queue:.main) { time in
                    let elapsed=max(0,time.seconds-content.trimStart)
                    let startGain=content.fadeIn > 0 ? min(1,elapsed/content.fadeIn) : 1
                    let end=content.trimEnd ?? player.currentItem?.duration.seconds ?? .infinity
                    let endGain=content.fadeOut > 0 ? max(0,min(1,(end-time.seconds)/content.fadeOut)) : 1
                    player.volume=Float(content.volume*min(startGain,endGain))
                }
            }
            entries.append(entry)
            player.seek(to:CMTime(seconds:content.trimStart,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) { complete in if complete && (content.autoplay || forceAutoplay) { player.play() } }
        }
    }
    func layout(slide: Slide, deck: Presentation, rect: NSRect) {
        let objects=deck.resolved(slide).objects
        for entry in entries {
            guard let o=objects.first(where: { $0.id == entry.objectID }) else { continue }
            entry.view.frame=NSRect(x:rect.minX+o.frame.x*rect.width/deck.width,y:rect.minY+o.frame.y*rect.height/deck.height,width:o.frame.width*rect.width/deck.width,height:o.frame.height*rect.height/deck.height)
            entry.view.alphaValue=o.hidden ? 0 : o.opacity
        }
        for overlay in foreground { if let object=objects.first(where: { $0.id == overlay.object.id }) { if overlay.object != object || overlay.slideRect != rect { overlay.object=object; overlay.slideRect=rect; overlay.needsDisplay=true } } }
    }
    func pause() { for i in entries.indices { entries[i].wasPlaying=entries[i].player.rate > 0; entries[i].player.pause() } }
    func resume() { for entry in entries where entry.wasPlaying { entry.player.play() } }
    func stop(keepingBackground: Bool = false) {
        for view in foreground { view.removeFromSuperview() }; foreground=[]
        entries=entries.filter { entry in
            if keepingBackground && entry.settings.acrossSlides { return true }
            entry.player.pause(); entry.view.removeFromSuperview()
            if let token=entry.endToken { NotificationCenter.default.removeObserver(token) }
            if let token=entry.boundaryToken { entry.player.removeTimeObserver(token) }
            if let token=entry.fadeToken { entry.player.removeTimeObserver(token) }
            return false
        }
    }
    deinit { stop(); try? FileManager.default.removeItem(at:directory) }
}
