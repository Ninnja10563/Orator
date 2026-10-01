import AppKit
import PDFKit
import PresentationCore

enum PDFExporter {
    static func data(_ deck: Presentation,includeNotes: Bool = false) throws -> Data {
        let renderer=SlideRenderer()
        let output=NSMutableData(); guard let consumer=CGDataConsumer(data:output) else { throw FormatError.invalid("could not create PDF") }
        var box=CGRect(x:0,y:0,width:deck.width,height:deck.height)
        guard let context=CGContext(consumer:consumer,mediaBox:&box,nil) else { throw FormatError.invalid("could not create PDF context") }
        func page(_ draw: () -> Void) {
            context.beginPDFPage(nil); context.saveGState(); context.translateBy(x:0,y:box.height); context.scaleBy(x:1,y:-1)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:true)
            NSColor.white.setFill(); box.fill(); draw()
            NSGraphicsContext.restoreGraphicsState(); context.restoreGState(); context.endPDFPage()
        }
        for (index,slide) in deck.slides.enumerated() {
            if !includeNotes { page { renderer.draw(slide:slide,deck:deck,in:box) }; continue }
            let fontSize=max(10,min(22,deck.width/58)), margin=max(16,deck.width*0.045)
            let text=NSTextStorage(string:slide.notes,attributes:[.font:NSFont.systemFont(ofSize:fontSize),.foregroundColor:NSColor.black])
            let layout=NSLayoutManager(); layout.backgroundLayoutEnabled=false; text.addLayoutManager(layout)
            var end=0, first=true
            repeat {
                let headerHeight=fontSize*2, previewHeight=first ? max(1,deck.height*0.43) : 0
                let y=margin+headerHeight+previewHeight+(first ? fontSize : 0), height=max(1,deck.height-margin-y)
                let container=NSTextContainer(containerSize:NSSize(width:max(1,deck.width-margin*2),height:height)); container.lineFragmentPadding=0; layout.addTextContainer(container); layout.ensureLayout(for:container)
                let range=layout.glyphRange(for:container)
                page {
                    ("\(index+1)  \(slide.title)"+(first ? "" : " — Notes continued") as NSString).draw(at:NSPoint(x:margin,y:margin),withAttributes:[.font:NSFont.boldSystemFont(ofSize:fontSize),.foregroundColor:NSColor.black])
                    if first { let width=previewHeight*deck.width/deck.height; renderer.draw(slide:slide,deck:deck,in:NSRect(x:(deck.width-width)/2,y:margin+headerHeight,width:width,height:previewHeight)) }
                    layout.drawGlyphs(forGlyphRange:range,at:NSPoint(x:margin,y:y))
                }
                first=false; let previous=end; end=NSMaxRange(range)
                guard end > previous || text.length == 0 else { throw FormatError.invalid("speaker notes could not be paginated at this slide size") }
            } while end < layout.numberOfGlyphs
        }
        context.closePDF(); return output as Data
    }
}
extension EditorWindowController {
    @objc func exportNotesPDF(_ sender: Any?) { savePDF(includeNotes:true) }
    func savePDF(includeNotes: Bool) {
        canvas.finishText(); let deck=presentation.snapshot, panel=NSSavePanel(); panel.allowedContentTypes=[.pdf]; panel.nameFieldStringValue=(presentation.displayName ?? "Presentation")+(includeNotes ? " — Notes.pdf" : ".pdf")
        panel.beginSheetModal(for:window!) { [weak self] response in
            guard response == .OK, let url=panel.url else { return }
            DocumentTask.run(title:includeNotes ? "Exporting Speaker Notes…" : "Exporting PDF…",window:self?.window,operation: { try PDFExporter.data(deck,includeNotes:includeNotes).write(to:url,options:.atomic) },completion: { [weak self] result in if case .failure(let error)=result { self?.presentation.presentError(error) } })
        }
    }
}
