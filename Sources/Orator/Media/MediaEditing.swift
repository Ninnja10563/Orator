import AppKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import PresentationCore

extension EditorWindowController {
    @objc func insertMedia(_ sender: Any?) {
        canvas.finishText()
        let slideID=currentSlide.id
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.movie,.audio]
        panel.beginSheetModal(for:window!) { [weak self] response in
            guard response == .OK, let url=panel.url, let self=self else { return }
            Task { @MainActor in
                do {
                    let data=try Data(contentsOf:url); guard data.count <= 100*1024*1024 else { throw FormatError.invalid("embedded media must be under 100 MB") }
                    let avAsset=AVURLAsset(url:url)
                    let tracks=try await avAsset.loadTracks(withMediaType:.video)
                    let asset=Asset(name:url.lastPathComponent,data:data)
                    var object=SlideObject(kind:tracks.isEmpty ? .audio : .video,name:url.deletingPathExtension().lastPathComponent,frame:tracks.isEmpty ? Rect(160,500,480,72) : Rect(160,120,960,540))
                    object.media=MediaContent(assetID:asset.id)
                    let duration=try await avAsset.load(.duration).seconds
                    if duration.isFinite && duration > 0 { object.media?.sourceDuration=duration }
                    var assets=[asset]
                    if !tracks.isEmpty {
                        let generator=AVAssetImageGenerator(asset:avAsset); generator.appliesPreferredTrackTransform=true
                        if let (image,_)=try? await generator.image(at:.zero), let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) {
                            let poster=Asset(name:"Poster.png",data:png); assets.append(poster); object.media?.posterAssetID=poster.id
                        }
                    }
                    self.insertObject(object,assets:assets,on:slideID,name:"Insert Media")
                } catch { self.presentation.presentError(error) }
            }
        }
    }
    @objc func mediaSettings(_ sender: Any?) {
        guard let object=currentSlide.objects.first(where: { canvas.selected.contains($0.id) }), let media=object.media else { return }
        let slideID=currentSlide.id
        let alert=NSAlert(); alert.messageText="Playback settings"
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=8; stack.frame=NSRect(x:0,y:0,width:360,height:300)
        var fields: [String:NSTextField]=[:]
        for (label,value) in [("Trim start (seconds)",media.trimStart),("Trim end (0 = end)",media.trimEnd ?? 0),("Volume (%)",media.volume*100),("Fade in (seconds)",media.fadeIn),("Fade out (seconds)",media.fadeOut)] {
            let field=NSTextField(string:String(value)); field.widthAnchor.constraint(equalToConstant:100).isActive=true; fields[label]=field; stack.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:label),field]))
        }
        let autoplay=NSButton(checkboxWithTitle:"Play automatically",target:nil,action:nil); autoplay.state=media.autoplay ? .on : .off
        let loop=NSButton(checkboxWithTitle:"Loop",target:nil,action:nil); loop.state=media.loop ? .on : .off
        let background=NSButton(checkboxWithTitle:"Continue audio across slides",target:nil,action:nil); background.state=media.acrossSlides ? .on : .off; background.isEnabled=object.kind == .audio
        for button in [autoplay,loop,background] { stack.addArrangedSubview(button) }
        alert.accessoryView=stack; alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window!) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self=self else { return }
            guard fields.values.allSatisfy({ Double($0.stringValue)?.isFinite == true }) else { return }
            let start=max(0,fields["Trim start (seconds)"]!.doubleValue), end=fields["Trim end (0 = end)"]!.doubleValue
            guard end <= 0 || end > start else { self.presentation.presentError(FormatError.invalid("trim end must follow trim start")); return }
            self.modifyObject(object.id,on:slideID,name:"Media Settings") { object in
                object.media?.trimEndOffset=nil; object.media?.trimStart=start; object.media?.trimEnd=end > 0 ? end : nil
                object.media?.volume=min(1,max(0,fields["Volume (%)"]!.doubleValue/100))
                object.media?.fadeIn=max(0,fields["Fade in (seconds)"]!.doubleValue); object.media?.fadeOut=max(0,fields["Fade out (seconds)"]!.doubleValue)
                object.media?.autoplay=autoplay.state == .on; object.media?.loop=loop.state == .on; object.media?.acrossSlides=background.state == .on && object.kind == .audio
            }
        }
    }
    @objc func previewMedia(_ sender: Any?) {
        guard let object=currentSlide.objects.first(where: { canvas.selected.contains($0.id) }), object.media != nil else { return }
        var slide=Slide(); slide.objects=[object]; slide.objects[0].frame=Rect(0,0,presentation.deck.width,presentation.deck.height)
        let controller=MediaPreviewController(slide:slide,deck:presentation.deck); toolWindows.append(controller); controller.showWindow(nil)
    }
}
final class MediaPreviewController: NSWindowController, NSWindowDelegate {
    let playback=MediaPlayback()
    init(slide: Slide,deck: Presentation) {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:540),styleMask:[.titled,.closable],backing:.buffered,defer:false); window.title="Media Preview"; window.isReleasedWhenClosed=false
        super.init(window:window); window.delegate=self; window.center()
        let view=FlippedView(frame:window.contentView!.bounds); window.contentView=view
        do { try playback.install(slide:slide,deck:deck,in:view,rect:view.bounds,forceAutoplay:true) } catch { NSApp.presentError(error) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func windowWillClose(_ notification: Notification) { playback.stop() }
}
