import AppKit
import UniformTypeIdentifiers
import PresentationCore

extension EditorWindowController {
    @objc func exportPDF(_ sender: Any?) { savePDF(includeNotes:false) }
    @objc func exportPPTX(_ sender: Any?) {
        canvas.finishText(); let panel=NSSavePanel(); panel.allowedContentTypes=[UTType(filenameExtension:"pptx")!]; panel.nameFieldStringValue="\(presentation.displayName ?? "Presentation").pptx"
        panel.beginSheetModal(for:window!) { [weak self] response in
            guard response == .OK, let self=self, let url=panel.url else { return }
            do {
                var deck=self.presentation.deck
                // Rasterize groups explicitly; other objects remain editable in PowerPoint.
                var flattened=false
                for s in deck.slides.indices {
                    for i in deck.slides[s].objects.indices {
                        let object=deck.slides[s].objects[i]
                        if object.kind == .image, var content=object.image, let source=SlideRenderer.shared.image(content.assetID,in:deck) {
                            let crop=content.crop, sourceWidth=source.size.width*crop.width, sourceHeight=source.size.height*crop.height
                            let f=object.frame
                            if content.fill {
                                let ratio=max(f.width/sourceWidth,f.height/sourceHeight)
                                let width=f.width/ratio/source.size.width, height=f.height/ratio/source.size.height
                                content.crop=Rect(crop.midX-width/2,crop.midY-height/2,width,height)
                                deck.slides[s].objects[i].image=content
                            } else {
                                let ratio=min(f.width/sourceWidth,f.height/sourceHeight)
                                deck.slides[s].objects[i].frame=Rect(f.midX-sourceWidth*ratio/2,f.midY-sourceHeight*ratio/2,sourceWidth*ratio,sourceHeight*ratio)
                            }
                        }
                        if object.kind == .group {
                            let f=object.frame
                            let image=NSImage(size:NSSize(width:f.width,height:f.height)); image.lockFocusFlipped(true)
                            let t=NSAffineTransform(); t.translateX(by:-f.x,yBy:-f.y); t.concat(); SlideRenderer.shared.draw(object:object,deck:deck); image.unlockFocus()
                            guard let tiff=image.tiffRepresentation, let rep=NSBitmapImageRep(data:tiff), let png=rep.representation(using:.png,properties:[:]) else { continue }
                            let asset=Asset(name:"\(object.name).png",data:png); deck.assets[asset.id]=asset
                            var replacement=SlideObject(kind:.image,name:object.name,frame:f); replacement.id=object.id; replacement.image=ImageContent(assetID:asset.id); deck.slides[s].objects[i]=replacement; flattened=true
                        }
                    }
                }
                for id in Array(deck.assets.keys) {
                    if let asset=deck.assets[id], let image=NSImage(data:asset.data), let tiff=image.tiffRepresentation, let rep=NSBitmapImageRep(data:tiff), let png=rep.representation(using:.png,properties:[:]) { deck.assets[id]?.data=png }
                }
                var warnings=try PowerPoint.export(deck,to:url)
                if flattened { warnings.append("Groups were exported as images. They remain editable in your Orator document.") }
                if !warnings.isEmpty { let alert=NSAlert(); alert.messageText="PowerPoint export report"; alert.informativeText=warnings.joined(separator:"\n"); alert.beginSheetModal(for:self.window!) }
            } catch { self.presentation.presentError(error) }
        }
    }
}
