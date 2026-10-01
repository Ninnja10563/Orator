import AppKit
import UniformTypeIdentifiers
import PresentationCore

extension EditorWindowController {
    @objc func exportPDF(_ sender: Any?) { savePDF(includeNotes:false) }
    @objc func exportPPTX(_ sender: Any?) {
        canvas.finishText(); let panel=NSSavePanel(); panel.allowedContentTypes=[UTType(filenameExtension:"pptx")!]; panel.nameFieldStringValue="\(presentation.displayName ?? "Presentation").pptx"
        panel.beginSheetModal(for:window!) { [weak self] response in
            guard response == .OK, let self=self, let url=panel.url else { return }
            let snapshot=self.presentation.snapshot
            DocumentTask.run(title:"Exporting PowerPoint…",window:self.window,operation: { () throws -> [String] in
                try PowerPointExporter.export(snapshot,to:url)
            },completion: { [weak self] (result: Result<[String],Error>) in
                guard let self else { return }
                switch result {
                case .success(let warnings):
                    if !warnings.isEmpty { let alert=NSAlert(); alert.messageText="PowerPoint export report"; alert.informativeText=warnings.joined(separator:"\n"); if let window=self.window { alert.beginSheetModal(for:window) } }
                case .failure(let error):self.presentation.presentError(error)
                }
            })
        }
    }
}

/// Converts platform image formats and visual fit geometry before writing Office XML.
enum PowerPointExporter {
    static func export(_ snapshot: Presentation,to url: URL) throws -> [String] {
        var deck=snapshot
        try MediaMetadata.resolve(&deck)
        let renderer=SlideRenderer()
        func prepare(_ originals: [SlideObject]) -> [SlideObject] {
            originals.map { sourceObject in
                var object=sourceObject
                if object.kind == .image, var content=object.image, let source=renderer.image(content.assetID,in:deck) {
                    let crop=content.crop, sourceWidth=source.size.width*crop.width, sourceHeight=source.size.height*crop.height, f=object.frame
                    if content.fill { let ratio=max(f.width/sourceWidth,f.height/sourceHeight); let width=f.width/ratio/source.size.width, height=f.height/ratio/source.size.height; content.crop=Rect(crop.midX-width/2,crop.midY-height/2,width,height); object.image=content }
                    else { let ratio=min(f.width/sourceWidth,f.height/sourceHeight); object.frame=Rect(f.midX-sourceWidth*ratio/2,f.midY-sourceHeight*ratio/2,sourceWidth*ratio,sourceHeight*ratio); object.layoutLinked=false }
                }
                object.children=prepare(object.children); return object
            }
        }
        for i in deck.slides.indices { let originals=deck.resolvedContent(deck.slides[i]).objects; let prepared=prepare(originals); deck.slides[i].objects=prepared }
        if var masters=deck.masters { for i in masters.indices { masters[i].objects=prepare(masters[i].objects); for j in masters[i].layouts.indices { masters[i].layouts[j].objects=prepare(masters[i].layouts[j].objects) } }; deck.masters=masters }
        for id in Array(deck.assets.keys) {
            if let asset=deck.assets[id], let image=NSImage(data:asset.data), let tiff=image.tiffRepresentation, let rep=NSBitmapImageRep(data:tiff), let png=rep.representation(using:.png,properties:[:]) { deck.assets[id]?.data=png }
        }
        return try PowerPoint.export(deck,to:url)
    }
}
