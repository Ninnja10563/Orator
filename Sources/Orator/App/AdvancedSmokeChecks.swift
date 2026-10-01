import AppKit
import AVFoundation
import PDFKit
import AVKit
import PresentationCore

func checkAdvancedEditing(_ editor: EditorWindowController) throws {
    let document=editor.presentation, original=document.deck
    func grouped(_ body: () -> Void) { document.undoManager?.beginUndoGrouping(); body(); document.undoManager?.endUndoGrouping() }
    func capture(_ panel: NSWindowController,_ name: String) throws {
        panel.showWindow(nil); RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        guard !CommandLine.arguments.contains("--dark"), let output=ProcessInfo.processInfo.environment["ORATOR_SMOKE_OUTPUT"], let view=panel.window?.contentView else { return }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap); try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:output).deletingLastPathComponent().appendingPathComponent(name+".png")) }
    }
    let textObject=editor.currentSlide.objects[0]; editor.canvas.beginText(textObject)
    guard let inline=editor.canvas.subviews.compactMap({ $0 as? InlineTextView }).first else { fatalError("Rich text editor missing") }
    inline.setSelectedRange(NSRange(location:0,length:4)); inline.undoManager?.groupsByEvent=false; inline.undoManager?.beginUndoGrouping()
    _=editor.canvas.formatTextSelection("Italic") { $0.italic=true }
    inline.undoManager?.endUndoGrouping()
    guard NativeText.style(inline.textStorage!.attributes(at:0,effectiveRange:nil)).italic else { fatalError("Text selection formatting failed") }
    inline.undoManager?.undo(); guard !NativeText.style(inline.textStorage!.attributes(at:0,effectiveRange:nil)).italic else { fatalError("Inline formatting undo failed") }
    inline.undoManager?.redo(); guard NativeText.style(inline.textStorage!.attributes(at:0,effectiveRange:nil)).italic else { fatalError("Inline formatting redo failed") }
    guard NativeText.style(inline.textStorage!.attributes(at:0,effectiveRange:nil)).color == nil else { fatalError("Formatting broke theme inheritance") }
    grouped { editor.canvas.finishText() }; document.undoManager?.undo()
    var listObject=SlideObject(kind:.text,name:"List editing",frame:Rect(80,80,800,400)); listObject.text="First item"; var listStyle=ParagraphSettings(); listStyle.list = .numbered; listObject.textStyle.paragraph=listStyle
    grouped { editor.insert(listObject) }; editor.canvas.beginText(listObject)
    let listEditor=editor.canvas.subviews.compactMap { $0 as? InlineTextView }.first!
    listEditor.setSelectedRange(NSRange(location:listEditor.string.utf16.count,length:0)); listEditor.insertNewline(nil); listEditor.insertText("Second item",replacementRange:listEditor.selectedRange()); listEditor.insertTab(nil)
    guard listEditor.layoutManager is ListLayoutManager, NativeText.style(listEditor.typingAttributes).paragraph?.level == 1 else { fatalError("Nested list editing failed") }
    let listSaved=try PresentationFile.decode(document.data(ofType:"app.orator.presentation"))
    guard listSaved.slides[0].objects.last?.text == "First item\nSecond item", listSaved.slides[0].objects.last?.textRuns?.last?.style.paragraph?.level == 1 else { fatalError("List edit persistence failed") }
    grouped { editor.canvas.finishText() }; document.undoManager?.undo(); document.undoManager?.undo()
    let tableObject=editor.currentSlide.objects.first { $0.kind == .table }!
    let table=TableEditor(editor:editor,object:tableObject)
    grouped { table.tableView(table.grid,setObjectValue:"Edited in AppKit",for:table.grid.tableColumns[1],row:1) }
    guard editor.currentSlide.objects.first(where: { $0.id == tableObject.id })?.table?.cells[1][1] == "Edited in AppKit" else { fatalError("Native table cell edit failed") }
    document.undoManager?.undo()
    guard editor.currentSlide.objects.first(where: { $0.id == tableObject.id }) == tableObject else { fatalError("Table cell undo failed") }
    try capture(table,"table-editor"); table.close()
    grouped { editor.insertChart(nil) }
    let chartObject=editor.currentSlide.objects.last!
    let chart=ChartEditor(editor:editor,object:chartObject)
    grouped { chart.addSeries(); chart.tableView(chart.grid,setObjectValue:"42",for:chart.grid.tableColumns[2],row:0) }
    guard chart.content?.dataSeries.count == 2, chart.content?.dataSeries[1].values[0] == 42 else { fatalError("Native chart series editing failed") }
    try capture(chart,"chart-editor"); chart.close()
    let image=NSImage(size:NSSize(width:640,height:360)); image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x:0,y:0,width:640,height:360).fill(); NSColor.systemOrange.setFill(); NSRect(x:160,y:90,width:320,height:180).fill(); image.unlockFocus()
    let crop=CropEditor(image:image,content:ImageContent(assetID:UUID())) { _,_ in }
    crop.aspect.selectItem(at:1); crop.changeAspect()
    guard abs(crop.preview.crop.width*640-crop.preview.crop.height*360) < 0.01 else { fatalError("Crop aspect ratio failed") }
    try capture(crop,"crop-editor"); crop.close()
    editor.canvas.selected=[editor.currentSlide.objects[0].id]
    grouped { editor.saveAsMasterLayout(nil) }
    guard editor.editingLayoutID != nil else { fatalError("Master layout editor failed") }
    var layout=editor.currentSlide; layout.objects[0].frame.x=170
    grouped { editor.commit(layout,name:"Move Layout Placeholder") }
    guard editor.currentSlide.objects[0].frame.x == 170 else { fatalError("Master layout edit was not stored") }
    _=try PresentationFile.decode(document.data(ofType:"app.orator.presentation"))
    editor.editMaster(nil)
    editor.canvas.selected=Set(editor.currentSlide.objects.prefix(2).map(\.id)); grouped { editor.groupObjects(nil) }
    guard let groupID=editor.canvas.selected.first else { fatalError("Grouping failed") }; editor.editGroup(groupID)
    guard editor.currentSlide.id == groupID else { fatalError("Group isolation failed") }
    editor.canvas.selected=[editor.currentSlide.objects[0].id]; editor.copyObjects(nil)
    let childCount=editor.currentSlide.objects.count
    grouped { editor.pasteObjects(nil) }
    guard editor.currentSlide.objects.count == childCount+1 else { fatalError("Pasting into a group failed") }
    document.undoManager?.undo()
    guard editor.currentSlide.objects.count == childCount else { fatalError("Group paste undo failed") }
    let groupedText=editor.currentSlide.objects[0]; editor.canvas.beginText(groupedText)
    let groupedEditor=editor.canvas.subviews.compactMap { $0 as? InlineTextView }.first!; groupedEditor.string="Saved inside group"
    let savedGroup=try PresentationFile.decode(document.data(ofType:"app.orator.presentation"))
    guard savedGroup.slides[0].objects.first(where: { $0.id == groupID })?.children.first?.text == "Saved inside group" else { fatalError("Active group text was omitted from saving") }
    grouped { editor.canvas.finishText() }; document.undoManager?.undo(); editor.finishGroupEditing(nil)
    var notesDeck=document.deck; notesDeck.slides=Array(notesDeck.slides.prefix(1)); notesDeck.slides[0].notes=String(repeating:"Speaker notes must continue across printed pages.\n",count:100)+"FINAL NOTES MARKER"
    let notesPDF=try PDFExporter.data(notesDeck,includeNotes:true)
    guard let pdf=PDFDocument(data:notesPDF), pdf.pageCount > 1, pdf.string?.contains("FINAL NOTES MARKER") == true else { fatalError("Speaker notes PDF pagination lost text") }
    _=try document.printOperation(withSettings:[:])
    if let output=ProcessInfo.processInfo.environment["ORATOR_SMOKE_OUTPUT"] {
        var list=SlideObject(kind:.text,name:"Numbered list",frame:Rect(40,40,560,240)); list.text="First item\nSecond item\nThird item"; list.textStyle.size=32
        var paragraph=ParagraphSettings(); paragraph.list = .numbered; list.textStyle.paragraph=paragraph
        var slide=Slide(); slide.objects=[list]; var deck=Presentation(); deck.width=640; deck.height=320; deck.slides=[slide]
        let image=SlideRenderer.shared.thumbnail(slide:slide,deck:deck,size:NSSize(width:640,height:320))
        if let data=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:data) { try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:output).deletingLastPathComponent().appendingPathComponent("list-rendering.png")) }
    }
    var mediaGroup=SlideObject(kind:.group,name:"Media group",frame:Rect(0,0,100,100)); mediaGroup.rotation=90; mediaGroup.opacity=0.5
    mediaGroup.children=[SlideObject(kind:.video,name:"Nested movie",frame:Rect(60,40,20,20))]
    let flattened=MediaPlayback.playbackObjects([mediaGroup])
    guard flattened.count == 1, abs(flattened[0].frame.x-40) < 0.01, abs(flattened[0].frame.y-60) < 0.01, flattened[0].rotation == 90, flattened[0].opacity == 0.5 else { fatalError("Grouped media transforms failed") }
    try checkMediaPlayback()
    document.deck=original; document.undoManager?.removeAllActions(); editor.editingMasterID=nil; editor.editingLayoutID=nil; editor.editingGroupIDs=[]; editor.selectedSlideID=original.slides[0].id; editor.canvas.selected=[]; editor.refresh(); editor.window?.makeKeyAndOrderFront(nil)
    print("Advanced AppKit checks: table cells/undo, chart series, crop geometry, master layouts, and AVFoundation playback passed")
}
private func checkMediaPlayback() throws {
    var wav=Data()
    func word(_ value: UInt32,_ bytes: Int) { for i in 0..<bytes { wav.append(UInt8((value >> (8*i)) & 255)) } }
    let count=16000
    wav.append(Data("RIFF".utf8)); word(UInt32(36+count),4); wav.append(Data("WAVEfmt ".utf8)); word(16,4); word(1,2); word(1,2); word(8000,4); word(16000,4); word(2,2); word(16,2); wav.append(Data("data".utf8)); word(UInt32(count),4); wav.append(Data(repeating:0,count:count))
    var deck=Presentation(); let asset=Asset(name:"Playback.wav",data:wav); deck.assets[asset.id]=asset
    var object=SlideObject(kind:.audio,name:"Playback",frame:Rect(0,0,640,72)); object.media=MediaContent(assetID:asset.id); object.media?.volume=0; object.media?.trimEnd=0.8
    var slide=Slide(); slide.objects=[object]
    let parent=NSView(frame:NSRect(x:0,y:0,width:640,height:360)), playback=MediaPlayback()
    try playback.install(slide:slide,deck:deck,in:parent,rect:parent.bounds,forceAutoplay:true)
    guard let player=parent.subviews.compactMap({ $0 as? AVPlayerView }).first?.player else { fatalError("Media player view missing") }
    let deadline=Date().addingTimeInterval(5)
    while Date() < deadline && player.currentTime().seconds < 0.05 && player.status != .failed { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
    guard player.status == .readyToPlay, player.currentTime().seconds >= 0.05 else { fatalError("Embedded audio did not begin playback: \(String(describing:player.error))") }
    playback.pause(); guard player.rate == 0 else { fatalError("Media pause failed") }; playback.resume(); playback.stop()
    guard parent.subviews.isEmpty, player.rate == 0 else { fatalError("Media cleanup failed") }
}
