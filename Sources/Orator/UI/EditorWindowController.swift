import AppKit
import UniformTypeIdentifiers
import PresentationCore

final class EditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate, NSTextViewDelegate {
    let presentation: PresentationDocument
    let canvas=CanvasView(frame:.zero)
    let navigator=SlideTableView()
    let notes=NSTextView()
    let inspector=InspectorView()
    let status=NSTextField(labelWithString:"")
    let split=NSSplitView()
    let vertical=NSSplitView()
    let navigationPane=SurfaceView()
    let notesPane=SurfaceView()
    var editingMasterID: UUID?
    var editingLayoutID: UUID?
    var editingGroupIDs: [UUID]=[]
    var selectedSlideID: UUID
    var currentSlide: Slide {
        var slide=baseSlide
        for id in editingGroupIDs { guard let group=slide.objects.first(where: { $0.id == id && $0.kind == .group }) else { break }; slide.id=group.id; slide.title=group.name; slide.objects=group.children; slide.animations=nil; slide.guides=[] }
        return slide
    }
    var baseSlide: Slide {
        if let id=editingMasterID, let master=presentation.deck.masters?.first(where: { $0.id == id }) {
            if let layout=master.layouts.first(where: { $0.id == editingLayoutID }) { var slide=Slide(); slide.id=layout.id; slide.title=layout.name; slide.objects=layout.objects; slide.masterID=master.id; return slide }
            return master.slide
        }
        return presentation.deck.resolvedContent(presentation.deck.slides.first { $0.id == selectedSlideID } ?? presentation.deck.slides[0])
    }
    var presenter: PresenterController?
    var toolWindows: [NSWindowController]=[]
    private var refreshing=false
    private let thumbnailService=ThumbnailService()
    private var thumbnailOrder: [UUID]=[]
    private var thumbnails: [UUID:(Slide,Theme,NSImage)]=[:]
    private let slideDrag=NSPasteboard.PasteboardType("app.orator.slide-indices")
    static let slidePasteboard=NSPasteboard.PasteboardType("app.orator.slides")
    static let objectPasteboard=NSPasteboard.PasteboardType("app.orator.objects")

    init(document: PresentationDocument) {
        presentation=document; selectedSlideID=document.deck.slides[0].id
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1380,height:880),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        super.init(window:window); window.title="Orator"; window.minSize=NSSize(width:920,height:640); window.center(); window.tabbingMode = .preferred
        window.setFrameAutosaveName("OratorEditor"); window.isReleasedWhenClosed=false
        canvas.editor=self; inspector.editor=self; navigator.editor=self
        buildWorkspace(); buildToolbar()
        document.didChange = { [weak self] in self?.refresh() }
        refresh()
        window.makeFirstResponder(canvas)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.contentView?.layoutSubtreeIfNeeded()
        vertical.setPosition(max(360,vertical.bounds.height-150),ofDividerAt:0)
        split.setPosition(210,ofDividerAt:0)
        split.setPosition(max(610,split.bounds.width-300),ofDividerAt:1)
    }
    func buildWorkspace() {
        guard let root=window?.contentView else { return }
        vertical.isVertical=false; vertical.dividerStyle = .thin; vertical.frame=root.bounds; vertical.autoresizingMask=[.width,.height]; root.addSubview(vertical)
        split.isVertical=true; split.dividerStyle = .thin
        split.frame=NSRect(x:0,y:0,width:root.bounds.width,height:max(400,root.bounds.height-150))
        notesPane.frame=NSRect(x:0,y:0,width:root.bounds.width,height:150)
        navigationPane.frame=NSRect(x:0,y:0,width:210,height:split.bounds.height)
        canvas.frame=NSRect(x:0,y:0,width:max(400,root.bounds.width-510),height:split.bounds.height)
        inspector.frame=NSRect(x:0,y:0,width:300,height:split.bounds.height)
        vertical.addArrangedSubview(split); vertical.addArrangedSubview(notesPane)
        split.addArrangedSubview(navigationPane); split.addArrangedSubview(canvas); split.addArrangedSubview(inspector)
        split.heightAnchor.constraint(greaterThanOrEqualToConstant:360).isActive=true
        notesPane.heightAnchor.constraint(greaterThanOrEqualToConstant:90).isActive=true
        notesPane.heightAnchor.constraint(lessThanOrEqualToConstant:300).isActive=true
        vertical.setHoldingPriority(.defaultHigh,forSubviewAt:1)
        split.setHoldingPriority(.defaultHigh,forSubviewAt:0)
        split.setHoldingPriority(.defaultHigh,forSubviewAt:2)
        let scroll=NSScrollView(); scroll.hasVerticalScroller=true; scroll.drawsBackground=false; scroll.translatesAutoresizingMaskIntoConstraints=false
        let heading=NSTextField(labelWithString:"SLIDES"); heading.font = .systemFont(ofSize:11,weight:.semibold); heading.textColor = .secondaryLabelColor; heading.translatesAutoresizingMaskIntoConstraints=false
        navigationPane.addSubview(heading); navigationPane.addSubview(scroll)
        NSLayoutConstraint.activate([heading.topAnchor.constraint(equalTo:navigationPane.topAnchor,constant:16),heading.leadingAnchor.constraint(equalTo:navigationPane.leadingAnchor,constant:18),scroll.topAnchor.constraint(equalTo:heading.bottomAnchor,constant:12),scroll.leadingAnchor.constraint(equalTo:navigationPane.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:navigationPane.trailingAnchor),scroll.bottomAnchor.constraint(equalTo:navigationPane.bottomAnchor),navigationPane.widthAnchor.constraint(greaterThanOrEqualToConstant:150),inspector.widthAnchor.constraint(greaterThanOrEqualToConstant:240),canvas.widthAnchor.constraint(greaterThanOrEqualToConstant:400)])
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("slide")); navigator.addTableColumn(column); navigator.headerView=nil
        navigator.rowHeight=130; navigator.intercellSpacing=NSSize(width:0,height:6); navigator.allowsMultipleSelection=true; navigator.style = .sourceList
        navigator.dataSource=self; navigator.delegate=self; navigator.setAccessibilityLabel("Slides")
        navigator.registerForDraggedTypes([slideDrag]); navigator.setDraggingSourceOperationMask(.move,forLocal:true)
        navigator.menu=slideMenu(); scroll.documentView=navigator
        let notesScroll=NSScrollView(); notesScroll.hasVerticalScroller=true; notesScroll.borderType = .noBorder; notesScroll.translatesAutoresizingMaskIntoConstraints=false
        notes.minSize=NSSize(width:0,height:60); notes.maxSize=NSSize(width:100000,height:100000); notes.isVerticallyResizable=true; notes.isHorizontallyResizable=false; notes.autoresizingMask=[.width]; notes.textContainer?.widthTracksTextView=true
        notes.isRichText=false; notes.font = .systemFont(ofSize:13); notes.textContainerInset=NSSize(width:18,height:8); notes.delegate=self; notes.setAccessibilityLabel("Speaker notes")
        notesScroll.documentView=notes
        let label=NSTextField(labelWithString:"SPEAKER NOTES"); label.font = .systemFont(ofSize:11,weight:.semibold); label.textColor = .secondaryLabelColor; label.translatesAutoresizingMaskIntoConstraints=false
        status.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); status.textColor = .secondaryLabelColor; status.translatesAutoresizingMaskIntoConstraints=false
        notesPane.addSubview(label); notesPane.addSubview(notesScroll); notesPane.addSubview(status)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:notesPane.leadingAnchor,constant:18),label.topAnchor.constraint(equalTo:notesPane.topAnchor,constant:10),status.trailingAnchor.constraint(equalTo:notesPane.trailingAnchor,constant:-16),status.centerYAnchor.constraint(equalTo:label.centerYAnchor),notesScroll.topAnchor.constraint(equalTo:label.bottomAnchor,constant:4),notesScroll.leadingAnchor.constraint(equalTo:notesPane.leadingAnchor),notesScroll.trailingAnchor.constraint(equalTo:notesPane.trailingAnchor),notesScroll.bottomAnchor.constraint(equalTo:notesPane.bottomAnchor)])
        vertical.setPosition(690,ofDividerAt:0); split.setPosition(210,ofDividerAt:0); split.setPosition(1080,ofDividerAt:1)
    }
    func buildToolbar() {
        let toolbar=NSToolbar(identifier:"OratorEditing"); toolbar.delegate=self; toolbar.displayMode = .iconAndLabel; toolbar.allowsUserCustomization=true
        window?.toolbar=toolbar; window?.toolbarStyle = .unified
    }
    let toolbarItems: [(String,String,String,Selector)] = [
        ("slide","Add Slide","plus.rectangle.on.rectangle",#selector(addSlide(_:))),
        ("text","Text","textformat",#selector(addText(_:))),
        ("shape","Shape","square.on.circle",#selector(insertShape(_:))),
        ("image","Image","photo",#selector(insertImage(_:))),
        ("table","Table","tablecells",#selector(insertTable(_:))),
        ("chart","Chart","chart.bar",#selector(insertChart(_:))),
        ("zoom","Fit Slide","arrow.up.left.and.arrow.down.right",#selector(fitSlide(_:))),
        ("present","Present","play",#selector(startPresentation(_:)))
    ]
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarItems.map { NSToolbarItem.Identifier($0.0) }+[.flexibleSpace,.space] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarItems.prefix(6).map { NSToolbarItem.Identifier($0.0) }+[.flexibleSpace,NSToolbarItem.Identifier("zoom"),NSToolbarItem.Identifier("present")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let spec=toolbarItems.first(where: { $0.0 == id.rawValue }) else { return nil }
        let item=NSToolbarItem(itemIdentifier:id); item.label=spec.1; item.paletteLabel=spec.1; item.toolTip=spec.1; item.image=NSImage(systemSymbolName:spec.2,accessibilityDescription:spec.1); item.target=self; item.action=spec.3; return item
    }
    func refresh() {
        refreshing=true; defer { refreshing=false }
        if !presentation.deck.slides.contains(where: { $0.id == selectedSlideID }) { selectedSlideID=presentation.deck.slides[0].id }
        var groupObjects=baseSlide.objects, validGroups: [UUID]=[]
        for id in editingGroupIDs { guard let group=groupObjects.first(where: { $0.id == id && $0.kind == .group }) else { break }; validGroups.append(id); groupObjects=group.children }; editingGroupIDs=validGroups
        canvas.selected.formIntersection(Set(currentSlide.objects.map(\.id)))
        if editingMasterID != nil { thumbnails.removeAll() }
        navigator.reloadData()
        if let row=presentation.deck.slides.firstIndex(where: { $0.id == selectedSlideID }), !navigator.selectedRowIndexes.contains(row) { navigator.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }
        if notes.string != currentSlide.notes {
            let insertion=notes.selectedRange().location
            notes.string=currentSlide.notes
            notes.setSelectedRange(NSRange(location:min(insertion,(notes.string as NSString).length),length:0))
        }
        status.stringValue="Slide \((presentation.deck.slides.firstIndex { $0.id == selectedSlideID } ?? 0)+1) of \(presentation.deck.slides.count)   ·   \(Int(canvas.scale*100))%"
        if editingMasterID != nil { status.stringValue="EDITING MASTER — "+currentSlide.title+" · Slide → Finish Editing Master to return" }
        if !editingGroupIDs.isEmpty { status.stringValue="EDITING GROUP — "+currentSlide.title+" · Escape to return" }
        canvas.needsDisplay=true; inspector.refresh()
        thumbnails=thumbnails.filter { id,_ in presentation.deck.slides.contains { $0.id == id } }
    }
    func selectionChanged() { inspector.refresh() }
    func commit(_ slide: Slide, name: String) {
        guard slide != currentSlide, let edit=replacementEdit(slide) else { return }
        presentation.perform(edit,named:name)
    }
    func mutateSelection(_ name: String, _ action: (inout SlideObject) -> Void) {
        canvas.finishText(); var slide=currentSlide
        for i in slide.objects.indices where canvas.selected.contains(slide.objects[i].id) && !slide.objects[i].locked { action(&slide.objects[i]) }
        commit(slide,name:name)
    }
    func formatText(_ name: String, _ mutate: (inout TextStyle) -> Void) {
        if canvas.formatTextSelection(name,mutate:mutate) { return }
        mutateSelection(name) { object in
            object.masterTextLinked=false; mutate(&object.textStyle)
            if var runs=object.textRuns { for i in runs.indices { mutate(&runs[i].style) }; object.textRuns=runs }
        }
    }
    func textDidChange(_ notification: Notification) {
        guard !refreshing else { return }; var slide=editingGroupIDs.isEmpty ? currentSlide : baseSlide; slide.notes=notes.string; commit(slide,name:"Edit Speaker Notes")
    }
    func numberOfRows(in tableView: NSTableView) -> Int { presentation.deck.slides.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let slide=presentation.deck.slides[row], cell=NSTableCellView(); let image=NSImageView(); image.imageScaling = .scaleProportionallyUpOrDown
        let rendered=presentation.deck.resolved(slide)
        if let cached=thumbnails[slide.id], cached.0 == rendered, cached.1 == presentation.deck.theme { image.image=cached.2 }
        else {
            image.image=thumbnails[slide.id]?.2
            let snapshot=presentation.deck, theme=snapshot.theme
            thumbnailService.request(slide:slide,deck:snapshot) { [weak self,weak image] thumbnail in
                guard let self=self, let current=self.presentation.deck.slides.first(where: { $0.id == slide.id }), self.presentation.deck.resolved(current) == rendered, self.presentation.deck.theme == theme else { return }
                self.thumbnails[slide.id]=(rendered,theme,thumbnail); self.thumbnailOrder.removeAll { $0 == slide.id }; self.thumbnailOrder.append(slide.id)
                while self.thumbnailOrder.count > 160 { self.thumbnails.removeValue(forKey:self.thumbnailOrder.removeFirst()) }
                image?.image=thumbnail
            }
        }
        image.translatesAutoresizingMaskIntoConstraints=false
        let section=(row == 0 || presentation.deck.slides[row-1].section != slide.section) && !slide.section.isEmpty ? slide.section.uppercased()+" · " : ""
        let title=NSTextField(labelWithString:"\(section)\(row+1)  \(slide.skipped ? "[Skipped] " : "")\(slide.title)"); title.font = .systemFont(ofSize:11); title.lineBreakMode = .byTruncatingTail; title.translatesAutoresizingMaskIntoConstraints=false
        cell.addSubview(image); cell.addSubview(title); cell.imageView=image; cell.textField=title
        NSLayoutConstraint.activate([image.topAnchor.constraint(equalTo:cell.topAnchor,constant:6),image.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:14),image.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-14),image.heightAnchor.constraint(equalToConstant:96),title.topAnchor.constraint(equalTo:image.bottomAnchor,constant:4),title.leadingAnchor.constraint(equalTo:image.leadingAnchor),title.trailingAnchor.constraint(equalTo:image.trailingAnchor)])
        cell.setAccessibilityLabel("Slide \(row+1): \(slide.title)"); return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !refreshing, navigator.selectedRow >= 0 else { return }
        let nextID=presentation.deck.slides[navigator.selectedRow].id
        canvas.finishText(); editingMasterID=nil; editingLayoutID=nil; editingGroupIDs=[]; selectedSlideID=nextID; canvas.selected=[]; notes.string=currentSlide.notes; refresh()
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item=NSPasteboardItem(); item.setString(presentation.deck.slides[row].id.uuidString,forType:slideDrag); return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation { tableView.setDropRow(row,dropOperation:.above); return .move }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard info.draggingSource as? NSTableView === navigator else { return false }
        let ids=info.draggingPasteboard.pasteboardItems?.compactMap { $0.string(forType:slideDrag).flatMap(UUID.init(uuidString:)) } ?? []
        let old=presentation.deck.slides.map(\.id); let moving=old.filter { ids.contains($0) }; var order=old.filter { !ids.contains($0) }
        let offset=old.prefix(max(0,row)).filter { ids.contains($0) }.count
        order.insert(contentsOf:moving,at:min(order.count,max(0,row-offset))); presentation.perform(.orderSlides(order),named:"Reorder Slides"); return true
    }
    func slideMenu() -> NSMenu {
        let menu=NSMenu()
        for (title,action) in [("Add Slide",#selector(addSlide(_:))),("Duplicate Slides",#selector(duplicateSlides(_:))),("Skip / Include",#selector(skipSlide(_:))),("Delete Slides",#selector(deleteSlides(_:)))] { let item=menu.addItem(withTitle:title,action:action,keyEquivalent:""); item.target=self }; return menu
    }
    @objc func addSlide(_ sender: Any?) {
        canvas.finishText(); let menu=NSMenu()
        for layout in Layout.allCases { let item=menu.addItem(withTitle:layout.displayName,action:#selector(addLayout(_:)),keyEquivalent:""); item.target=self; item.representedObject=layout.rawValue }
        menu.popUp(positioning:nil,at:NSPoint(x:20,y:split.bounds.height-20),in:split)
    }
    @objc func addLayout(_ sender: NSMenuItem) {
        var slide=(Layout(rawValue:sender.representedObject as? String ?? "Blank") ?? .blank).makeSlide()
        slide.masterID=currentSlide.masterID ?? presentation.deck.masters?.first?.id
        let index=(presentation.deck.slides.firstIndex { $0.id == selectedSlideID } ?? 0)+1
        presentation.perform(.insertSlide(slide,index),named:"Add Slide"); selectedSlideID=slide.id; canvas.selected=[]; refresh()
    }
    @objc func copySlides(_ sender: Any?) {
        canvas.finishText()
        let slides=navigator.selectedRowIndexes.map { index -> Slide in
            var slide=presentation.deck.resolved(presentation.deck.slides[index]); slide.masterID=nil; slide.layoutID=nil; return slide
        }
        guard !slides.isEmpty, let data=try? JSONEncoder().encode(SlideClipboard(slides:slides,assets:presentation.deck.assets)) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data,forType:Self.slidePasteboard)
    }
    @objc func pasteSlides(_ sender: Any?) {
        canvas.finishText()
        guard let data=NSPasteboard.general.data(forType:Self.slidePasteboard), let payload=try? JSONDecoder().decode(SlideClipboard.self,from:data) else { return }
        let slides=payload.slides.map { $0.duplicated() }
        let position=(presentation.deck.slides.firstIndex { $0.id == selectedSlideID } ?? 0)+1
        let edits=payload.assets.values.map(Edit.putAsset)+slides.enumerated().map { Edit.insertSlide($0.element,position+$0.offset) }
        var candidate=presentation.deck
        do { try Edit.batch(edits).apply(to:&candidate); try PresentationFile.validate(candidate) }
        catch { presentation.presentError(error); return }
        presentation.perform(.batch(edits),named:"Paste Slides")
        if let first=slides.first { selectedSlideID=first.id; refresh() }
    }
    @objc func duplicateSlides(_ sender: Any?) {
        canvas.finishText(); let indices=navigator.selectedRowIndexes.sorted(); var edits: [Edit]=[]
        for i in indices.reversed() { edits.append(.insertSlide(presentation.deck.slides[i].duplicated(),i+1)) }
        presentation.perform(.batch(edits),named:"Duplicate Slides")
    }
    @objc func deleteSlides(_ sender: Any?) {
        canvas.finishText(); let ids=navigator.selectedRowIndexes.map { presentation.deck.slides[$0].id }
        guard ids.count < presentation.deck.slides.count else { NSSound.beep(); return }
        presentation.perform(.batch(ids.map(Edit.removeSlide)),named:"Delete Slides")
    }
    @objc func skipSlide(_ sender: Any?) { var slide=currentSlide; slide.skipped.toggle(); commit(slide,name:"Skip Slide") }
    func insert(_ object: SlideObject) { canvas.finishText(); var slide=currentSlide; slide.objects.append(object); commit(slide,name:"Insert \(object.name)"); canvas.selected=[object.id]; window?.makeFirstResponder(canvas) }
    @objc func addText(_ sender: Any?) { var o=SlideObject(kind:.text,name:"Text",frame:Rect(160,200,600,100)); o.text="Type your text"; insert(o); canvas.beginText(o) }
    @objc func insertShape(_ sender: Any?) {
        let menu=NSMenu()
        for shape in ShapeKind.allCases { let item=menu.addItem(withTitle:shape.displayName,action:#selector(addShape(_:)),keyEquivalent:""); item.target=self; item.representedObject=shape.rawValue }
        menu.popUp(positioning:nil,at:NSPoint(x:300,y:split.bounds.height-20),in:split)
    }
    @objc func addShape(_ sender: NSMenuItem) { var o=SlideObject(kind:.shape,name:"Shape",frame:Rect(300,220,320,220)); o.shape=ShapeKind(rawValue:sender.representedObject as? String ?? "rectangle") ?? .rectangle; o.name=o.shape.displayName; if o.shape == .circle { o.frame.height=o.frame.width }; insert(o) }
    @objc func insertImage(_ sender: Any?) {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.image]; panel.allowsMultipleSelection=true
        panel.beginSheetModal(for:window!) { [weak self] result in guard result == .OK else { return }; for url in panel.urls { self?.loadImage(url) } }
    }
    func loadImage(_ url: URL) {
        do { let data=try Data(contentsOf:url); guard let image=NSImage(data:data), image.size.width > 0, image.size.height > 0 else { throw FormatError.invalid("unsupported image") }
            let asset=Asset(name:url.lastPathComponent,data:data); let scale=min(1,800/image.size.width,500/image.size.height)
            var object=SlideObject(kind:.image,name:url.deletingPathExtension().lastPathComponent,frame:Rect(160,120,image.size.width*scale,image.size.height*scale)); object.image=ImageContent(assetID:asset.id)
            insertObject(object,assets:[asset],on:currentSlide.id,name:"Insert Image")
        } catch { presentation.presentError(error) }
    }
    func insertImages(from pasteboard: NSPasteboard) -> Bool {
        if let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty { for url in urls { loadImage(url) }; return true }
        if let image=NSImage(pasteboard:pasteboard), let data=image.tiffRepresentation {
            let asset=Asset(name:"Pasted Image",data:data); var o=SlideObject(kind:.image,name:"Image",frame:Rect(160,120,600,400)); o.image=ImageContent(assetID:asset.id)
            insertObject(o,assets:[asset],on:currentSlide.id,name:"Paste Image"); return true
        }; return false
    }
    @objc func insertTable(_ sender: Any?) { var o=SlideObject(kind:.table,name:"Table",frame:Rect(140,180,1000,360)); o.table=TableContent(); insert(o) }
    @objc func insertChart(_ sender: Any?) { var o=SlideObject(kind:.chart,name:"Chart",frame:Rect(160,120,960,500)); o.chart=ChartContent(); insert(o) }
    @objc func deleteObjects(_ sender: Any?) { canvas.finishText(); var slide=currentSlide; let removed=Set(slide.objects.filter { canvas.selected.contains($0.id) && !$0.locked }.flatMap(\.descendantIDs)); slide.objects.removeAll { removed.contains($0.id) }; slide.animations?.removeAll { removed.contains($0.objectID) }; commit(slide,name:"Delete Objects"); canvas.selected=[] }
    @objc func duplicateObjects(_ sender: Any?) { canvas.finishText(); var slide=currentSlide; let copies=SlideObject.duplicateBatch(slide.objects.filter { canvas.selected.contains($0.id) }); slide.objects += copies; commit(slide,name:"Duplicate Objects"); canvas.selected=Set(copies.map(\.id)) }
    @objc func copyObjects(_ sender: Any?) {
        canvas.finishText(); let objects=currentSlide.objects.filter { canvas.selected.contains($0.id) }; guard !objects.isEmpty else { return }
        let payload=ObjectClipboard(objects:objects,assets:presentation.deck.assets)
        guard let data=try? JSONEncoder().encode(payload) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data,forType:Self.objectPasteboard)
        NSPasteboard.general.setString(objects.map(\.text).joined(separator:"\n"),forType:.string)
    }
    @objc func pasteObjects(_ sender: Any?) {
        canvas.finishText()
        if let data=NSPasteboard.general.data(forType:Self.objectPasteboard), let payload=try? JSONDecoder().decode(ObjectClipboard.self,from:data) {
            var slide=currentSlide; let objects=SlideObject.duplicateBatch(payload.objects); slide.objects += objects
            guard let replacement=replacementEdit(slide) else { return }
            let edit=Edit.batch(payload.assets.values.map(Edit.putAsset)+[replacement])
            var candidate=presentation.deck
            do { try edit.apply(to:&candidate); try PresentationFile.validate(candidate) }
            catch { presentation.presentError(error); return }
            presentation.perform(edit,named:"Paste Objects"); canvas.selected=Set(objects.map(\.id)); return
        }
        if insertImages(from:NSPasteboard.general) { return }
        if let text=NSPasteboard.general.string(forType:.string) { var object=SlideObject(kind:.text,name:"Text",frame:Rect(160,200,700,200)); object.text=text; insert(object) }
    }
    @objc func groupObjects(_ sender: Any?) {
        canvas.finishText(); var slide=currentSlide; let objects=slide.objects.filter { canvas.selected.contains($0.id) && !$0.locked }
        guard objects.count > 1, let frame=Geometry.bounds(objects) else { return }
        var group=SlideObject(kind:.group,name:"Group",frame:frame); group.children=objects
        let ids=Set(objects.map(\.id)); slide.objects.removeAll { ids.contains($0.id) }; slide.objects.append(group); commit(slide,name:"Group Objects"); canvas.selected=[group.id]
    }
    @objc func ungroupObjects(_ sender: Any?) {
        canvas.finishText(); var slide=currentSlide; var ids=Set<UUID>()
        slide.objects=slide.objects.flatMap { object -> [SlideObject] in
            guard canvas.selected.contains(object.id), object.kind == .group, !object.locked else { return [object] }
            let radians=object.rotation * .pi / 180
            return object.children.map { child in var copy=child; let dx=copy.frame.midX-object.frame.midX,dy=copy.frame.midY-object.frame.midY
                var frame=copy.frame; frame.x=object.frame.midX+dx*cos(radians)-dy*sin(radians)-frame.width/2; frame.y=object.frame.midY+dx*sin(radians)+dy*cos(radians)-frame.height/2
                copy.transform(to:frame); copy.rotation += object.rotation; copy.opacity *= object.opacity; ids.insert(copy.id); return copy }
        }; commit(slide,name:"Ungroup Objects"); canvas.selected=ids
    }
    @objc func toggleLock(_ sender: Any?) { canvas.finishText(); var slide=currentSlide; for i in slide.objects.indices where canvas.selected.contains(slide.objects[i].id) { slide.objects[i].locked.toggle() }; commit(slide,name:"Lock Objects") }
    @objc func toggleVisibility(_ sender: Any?) {
        canvas.finishText(); var slide=currentSlide
        for i in slide.objects.indices where canvas.selected.contains(slide.objects[i].id) { slide.objects[i].hidden.toggle() }
        commit(slide,name:"Show / Hide Objects")
    }
    @objc func unlockAll(_ sender: Any?) { var slide=currentSlide; for i in slide.objects.indices { slide.objects[i].locked=false }; commit(slide,name:"Unlock All") }
    @objc func bringToFront(_ sender: Any?) { var slide=currentSlide; let objects=slide.objects.filter { canvas.selected.contains($0.id) }; slide.objects.removeAll { canvas.selected.contains($0.id) }; slide.objects += objects; commit(slide,name:"Bring to Front") }
    @objc func sendToBack(_ sender: Any?) { var slide=currentSlide; let objects=slide.objects.filter { canvas.selected.contains($0.id) }; slide.objects.removeAll { canvas.selected.contains($0.id) }; slide.objects.insert(contentsOf:objects,at:0); commit(slide,name:"Send to Back") }
    @objc func alignObjects(_ sender: NSMenuItem) {
        let commands: [Alignment]=[.left,.center,.right,.top,.middle,.bottom,.horizontal,.vertical]
        guard commands.indices.contains(sender.tag) else { return }; var slide=currentSlide
        let objects=Geometry.aligned(slide.objects.filter { canvas.selected.contains($0.id) && !$0.locked },command:commands[sender.tag]); let map=Dictionary(uniqueKeysWithValues:objects.map { ($0.id,$0) })
        slide.objects=slide.objects.map { map[$0.id] ?? $0 }; commit(slide,name:"Align Objects")
    }
    @objc func fitSlide(_ sender: Any?) { canvas.finishText(); canvas.fit=true; canvas.pan = .zero; canvas.needsDisplay=true; refresh() }
    @objc func fitWidth(_ sender: Any?) {
        canvas.finishText(); canvas.fit=false; canvas.zoom=max(0.1,(Double(canvas.bounds.width)-80)/presentation.deck.width); canvas.pan = .zero; refresh()
    }
    @objc func zoomSelection(_ sender: Any?) {
        canvas.finishText()
        guard let b=Geometry.bounds(currentSlide.objects.filter { canvas.selected.contains($0.id) }) else { return }
        canvas.fit=false; canvas.zoom=min(4,max(0.1,min((Double(canvas.bounds.width)-80)/b.width,(Double(canvas.bounds.height)-80)/b.height)))
        canvas.pan=NSPoint(x:(presentation.deck.width/2-b.midX)*canvas.zoom,y:(presentation.deck.height/2-b.midY)*canvas.zoom); refresh()
    }
    @objc func toggleRulers(_ sender: Any?) { canvas.showRulers.toggle() }
    @objc func setZoom(_ sender: NSMenuItem) { canvas.finishText(); canvas.fit=false; canvas.zoom=Double(sender.tag)/100; refresh() }
    @objc func toggleNavigator(_ sender: Any?) { navigationPane.isHidden.toggle(); split.adjustSubviews() }
    @objc func toggleInspector(_ sender: Any?) { inspector.isHidden.toggle(); split.adjustSubviews() }
    @objc func toggleNotes(_ sender: Any?) { notesPane.isHidden.toggle(); vertical.adjustSubviews() }
    @objc func toggleGuides(_ sender: Any?) { canvas.showGuides.toggle(); canvas.needsDisplay=true }
    @objc func addGuide(_ sender: NSMenuItem) { var slide=currentSlide; slide.guides.append(Guide(vertical:sender.tag == 0,position:sender.tag == 0 ? presentation.deck.width/2 : presentation.deck.height/2)); commit(slide,name:"Add Guide") }
    @objc func clearGuides(_ sender: Any?) { var slide=currentSlide; slide.guides=[]; commit(slide,name:"Clear Guides") }
    @objc func startPresentation(_ sender: Any?) { canvas.finishText(); presenter?.end(); presenter=PresenterController(deck:presentation.deck,startID:selectedSlideID); presenter?.start() }
    @objc func editData(_ sender: Any?) {
        guard let object=currentSlide.objects.first(where: { canvas.selected.contains($0.id) }), object.kind == .table || object.kind == .chart else { return }
        if object.kind == .table { let panel=TableEditor(editor:self,object:object); toolWindows.append(panel); panel.showWindow(nil); return }
        let panel=ChartEditor(editor:self,object:object); toolWindows.append(panel); panel.showWindow(nil)
    }
}
