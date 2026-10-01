import AppKit
import PresentationCore

final class AccessibleSlideObject: NSAccessibilityElement {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { onPress?(); return onPress != nil }
}

final class InlineTextView: NSTextView {
    private let typingUndo=UndoManager()
    override var undoManager: UndoManager? { typingUndo }
}

final class CanvasView: NSView, NSTextViewDelegate {
    weak var editor: EditorWindowController?
    var deck: Presentation { editor?.presentation.deck ?? Presentation() }
    var slide: Slide { preview ?? editor?.currentSlide ?? Slide() }
    var selected=Set<UUID>() { didSet { needsDisplay=true; editor?.selectionChanged() } }
    var zoom: Double = 1 { didSet { needsDisplay=true } }
    var fit = true
    var pan=NSPoint.zero
    var showRulers=false { didSet { needsDisplay=true } }
    var showGuides = true
    var preview: Slide?
    private var origin=Point()
    private var original: Slide?
    private var originalBounds: Rect?
    private var mode: DragMode = .none
    private var guides: [Guide]=[]
    private var marquee: Rect?
    private var textEditor: NSTextView?
    private var editingID: UUID?
    enum DragMode { case none, move, resize(Int), rotate, marquee, guide(Bool) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame)
        registerForDraggedTypes([.fileURL,.tiff,.png])
        setAccessibilityRole(.group); setAccessibilityLabel("Slide canvas"); setAccessibilityHelp("Select objects with Tab. Use arrow keys to move selected objects; Shift moves ten points. Press Return to edit text.")
    }
    required init?(coder: NSCoder) { fatalError() }
    var scale: Double { fit ? max(0.05,min((bounds.width-80)/deck.width,(bounds.height-80)/deck.height)) : zoom }
    var slideRect: NSRect { NSRect(x:(Double(bounds.width)-deck.width*Double(scale))/2+Double(pan.x),y:(Double(bounds.height)-deck.height*Double(scale))/2+Double(pan.y),width:deck.width*scale,height:deck.height*scale) }
    func slidePoint(_ event: NSEvent) -> Point { let p=convert(event.locationInWindow,from:nil), r=slideRect; return Point((p.x-r.minX)/scale,(p.y-r.minY)/scale) }
    func viewRect(_ r: Rect) -> NSRect { NSRect(x:slideRect.minX+r.x*scale,y:slideRect.minY+r.y*scale,width:r.width*scale,height:r.height*scale) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        let r=slideRect
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow(); shadow.shadowColor=NSColor.black.withAlphaComponent(0.12); shadow.shadowBlurRadius=8; shadow.shadowOffset=NSSize(width:0,height:-2); shadow.set()
        NSColor.white.setFill(); r.fill(); NSGraphicsContext.restoreGraphicsState()
        SlideRenderer.shared.draw(slide:slide,deck:deck,in:r,excluding:editingID)
        if showRulers {
            NSColor.controlBackgroundColor.setFill()
            NSRect(x:0,y:0,width:bounds.width,height:20).fill(); NSRect(x:0,y:0,width:20,height:bounds.height).fill()
            let step=scale < 0.5 ? 200.0 : 100.0
            let attributes: [NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:9,weight:.regular),.foregroundColor:NSColor.secondaryLabelColor]
            for value in stride(from:0.0,through:deck.width,by:step) {
                let x=r.minX+value*scale
                if x >= 20 && x < bounds.width { (String(Int(value)) as NSString).draw(at:NSPoint(x:x+3,y:3),withAttributes:attributes) }
            }
            for value in stride(from:0.0,through:deck.height,by:step) {
                let y=r.minY+value*scale
                if y >= 20 && y < bounds.height { (String(Int(value)) as NSString).draw(at:NSPoint(x:1,y:y),withAttributes:attributes) }
            }
        }
        if showGuides {
            for guide in slide.guides+guides {
                NSColor.systemPink.withAlphaComponent(0.8).setStroke(); let path=NSBezierPath(); path.lineWidth=1
                if guide.vertical { let x=r.minX+guide.position*scale; path.move(to:NSPoint(x:x,y:r.minY)); path.line(to:NSPoint(x:x,y:r.maxY)) }
                else { let y=r.minY+guide.position*scale; path.move(to:NSPoint(x:r.minX,y:y)); path.line(to:NSPoint(x:r.maxX,y:y)) }; path.stroke()
            }
        }
        for object in slide.objects where selected.contains(object.id) {
            let rect=viewRect(object.frame)
            NSColor.controlAccentColor.setStroke(); let path=NSBezierPath(rect:rect); path.lineWidth=1.5; path.stroke()
            if object.rotation != 0 {
                NSGraphicsContext.saveGraphicsState(); let t=NSAffineTransform(); t.translateX(by:rect.midX,yBy:rect.midY); t.rotate(byDegrees:object.rotation); t.translateX(by:-rect.midX,yBy:-rect.midY); t.concat(); let outline=NSBezierPath(rect:rect); outline.lineWidth=1; outline.setLineDash([3,3],count:2,phase:0); outline.stroke(); NSGraphicsContext.restoreGraphicsState()
            }
        }
        if let selection=Geometry.bounds(slide.objects.filter { selected.contains($0.id) }), textEditor == nil {
            for handle in handles(selection) { NSColor.controlBackgroundColor.setFill(); NSColor.controlAccentColor.setStroke(); let p=NSBezierPath(ovalIn:handle); p.fill(); p.stroke() }
        }
        if let m=marquee { NSColor.controlAccentColor.withAlphaComponent(0.10).setFill(); viewRect(m).fill(); NSColor.controlAccentColor.setStroke(); NSBezierPath(rect:viewRect(m)).stroke() }
    }
    func handles(_ r: Rect) -> [NSRect] {
        let r=viewRect(r)
        return [NSPoint(x:r.minX,y:r.minY),NSPoint(x:r.midX,y:r.minY),NSPoint(x:r.maxX,y:r.minY),NSPoint(x:r.maxX,y:r.midY),NSPoint(x:r.maxX,y:r.maxY),NSPoint(x:r.midX,y:r.maxY),NSPoint(x:r.minX,y:r.maxY),NSPoint(x:r.minX,y:r.midY),NSPoint(x:r.midX,y:r.minY-24)].map { NSRect(x:$0.x-4,y:$0.y-4,width:8,height:8) }
    }
    override func mouseDown(with event: NSEvent) {
        finishText(); window?.makeFirstResponder(self)
        let p=slidePoint(event); origin=p; original=slide
        let location=convert(event.locationInWindow,from:nil)
        if showRulers && (location.x < 20 || location.y < 20) { mode = .guide(location.x < 20); return }
        let candidates=slide.objects.filter { selected.contains($0.id) && !$0.locked }; originalBounds=Geometry.bounds(candidates)
        if let b=originalBounds, let index=handles(b).firstIndex(where: { $0.insetBy(dx:-4,dy:-4).contains(convert(event.locationInWindow,from:nil)) }) {
            mode=index == 8 ? .rotate : .resize(index); return
        }
        if let object=slide.objects.reversed().first(where: { Geometry.hit(p,object:$0) }) {
            if event.modifierFlags.contains(.shift) { if selected.contains(object.id) { selected.remove(object.id) } else { selected.insert(object.id) } }
            else if !selected.contains(object.id) { selected=[object.id] }
            originalBounds=Geometry.bounds(slide.objects.filter { selected.contains($0.id) && !$0.locked })
            if event.clickCount == 2 { if object.kind == .text || object.kind == .shape { beginText(object) } else if object.kind == .table || object.kind == .chart { editor?.editData(nil) }; mode = .none; return }
            mode = .move
        } else { if !event.modifierFlags.contains(.shift) { selected=[] }; mode = .marquee; marquee=Rect(p.x,p.y,0,0) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard var draft=original else { return }
        let p=slidePoint(event), dx=p.x-origin.x, dy=p.y-origin.y
        switch mode {
        case .none: return
        case .guide(let vertical):
            draft.guides.append(Guide(vertical:vertical,position:vertical ? p.x : p.y)); preview=draft
        case .marquee:
            let r=Rect(min(origin.x,p.x),min(origin.y,p.y),abs(dx),abs(dy)); marquee=r
            selected=Set(draft.objects.filter { !$0.locked && !$0.hidden && r.intersects($0.frame) }.map(\.id))
        case .move:
            guard let b=originalBounds else { return }
            var moved=Rect(b.x+dx,b.y+dy,b.width,b.height)
            guides=[]
            if !event.modifierFlags.contains(.option) {
                let result=Geometry.snap(moved,others:draft.objects.filter { !selected.contains($0.id) && !$0.hidden }.map(\.frame),guides:draft.guides,width:deck.width,height:deck.height,tolerance:5/scale)
                moved=result.0; guides=result.1
            }
            for i in draft.objects.indices where selected.contains(draft.objects[i].id) && !draft.objects[i].locked {
                var f=draft.objects[i].frame; f.x += moved.x-b.x; f.y += moved.y-b.y; draft.objects[i].transform(to:f)
            }; preview=draft
        case .resize(let index):
            guard let b=originalBounds else { return }; var n=b
            if [0,6,7].contains(index) { n.x=min(b.maxX-8,b.x+dx); n.width=b.maxX-n.x }
            if [2,3,4].contains(index) { n.width=max(8,b.width+dx) }
            if [0,1,2].contains(index) { n.y=min(b.maxY-8,b.y+dy); n.height=b.maxY-n.y }
            if [4,5,6].contains(index) { n.height=max(8,b.height+dy) }
            if event.modifierFlags.contains(.shift) { n.height=n.width*b.height/b.width }
            for i in draft.objects.indices where selected.contains(draft.objects[i].id) && !draft.objects[i].locked {
                let f=draft.objects[i].frame
                draft.objects[i].transform(to:Rect(n.x+(f.x-b.x)*n.width/b.width,n.y+(f.y-b.y)*n.height/b.height,f.width*n.width/b.width,f.height*n.height/b.height))
            }; preview=draft
        case .rotate:
            guard let b=originalBounds else { return }
            var angle=(atan2(p.y-b.midY,p.x-b.midX)-atan2(origin.y-b.midY,origin.x-b.midX))*180 / .pi
            if event.modifierFlags.contains(.shift) { angle=(angle/15).rounded()*15 }
            for i in draft.objects.indices where selected.contains(draft.objects[i].id) && !draft.objects[i].locked { draft.objects[i].rotation += angle }; preview=draft
        }
        needsDisplay=true
    }
    override func mouseUp(with event: NSEvent) {
        let changed=preview; preview=nil; guides=[]; marquee=nil; mode = .none
        if let changed=changed, changed != original { editor?.commit(changed,name:"Transform Objects") }
        original=nil; needsDisplay=true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finishText(); preview=nil; original=nil; mode = .none; selected=[]; return }
        if event.keyCode == 36, let o=slide.objects.first(where: { selected.contains($0.id) && ($0.kind == .text || $0.kind == .shape) }) { beginText(o); return }
        if event.keyCode == 48 {
            let items=slide.objects.filter { !$0.hidden && !$0.locked }; guard !items.isEmpty else { return }
            let current=items.firstIndex(where: { selected.contains($0.id) }) ?? -1
            let next=(current+(event.modifierFlags.contains(.shift) ? -1 : 1)+items.count)%items.count
            selected=[items[next].id]; NSAccessibility.post(element:self,notification:.selectedChildrenChanged); return
        }
        if [51,117].contains(event.keyCode) { editor?.deleteObjects(nil); return }
        if [123,124,125,126].contains(event.keyCode) {
            let amount=event.modifierFlags.contains(.shift) ? 10.0 : 1.0; var changed=slide
            for i in changed.objects.indices where selected.contains(changed.objects[i].id) && !changed.objects[i].locked {
                var f=changed.objects[i].frame
                if event.keyCode == 123 { f.x -= amount }; if event.keyCode == 124 { f.x += amount }
                if event.keyCode == 125 { f.y += amount }; if event.keyCode == 126 { f.y -= amount }
                changed.objects[i].transform(to:f)
            }; editor?.commit(changed,name:"Nudge Objects"); return
        }
        super.keyDown(with:event)
    }
    override func scrollWheel(with event: NSEvent) {
        guard !fit else { return }
        finishText()
        pan.x -= event.scrollingDeltaX; pan.y -= event.scrollingDeltaY
        needsDisplay=true
    }
    override func magnify(with event: NSEvent) { finishText(); let current=scale; fit=false; zoom=min(4,max(0.1,current*(1+event.magnification))) }
    func beginText(_ object: SlideObject) {
        guard !object.locked else { return }
        editingID=object.id
        let view=InlineTextView(frame:viewRect(object.frame)); view.isRichText=true; view.drawsBackground=true; view.backgroundColor=(slide.background ?? deck.theme.background).nsColor
        view.textContainerInset=NSSize(width:0,height:0); view.textContainer?.lineFragmentPadding=0
        view.setBoundsSize(NSSize(width:object.frame.width,height:object.frame.height))
        view.textContainer?.containerSize=NSSize(width:object.frame.width,height:object.frame.height)
        view.textStorage?.setAttributedString(NativeText.attributed(object,theme:deck.theme))
        view.typingAttributes=object.textStyle.attributes(theme:deck.theme)
        view.usesFontPanel=true; view.importsGraphics=false
        view.isVerticallyResizable=false; view.isHorizontallyResizable=false; view.autoresizingMask=[]
        view.delegate=self; view.allowsUndo=true
        view.setAccessibilityLabel("Edit \(object.name)")
        addSubview(view); textEditor=view; window?.makeFirstResponder(view); needsDisplay=true
    }
    @discardableResult func formatTextSelection(_ name: String, mutate: (inout TextStyle) -> Void) -> Bool {
        guard let view=textEditor, let storage=view.textStorage else { return false }
        let selection=view.selectedRange()
        let before=NSAttributedString(attributedString:storage)
        if selection.length == 0 {
            var style=NativeText.style(view.typingAttributes); mutate(&style)
            view.typingAttributes=style.attributes(theme:deck.theme)
        } else {
            var replacements: [(NSRange,[NSAttributedString.Key:Any])]=[]
            storage.enumerateAttributes(in:selection) { attrs,range,_ in
                var style=NativeText.style(attrs); mutate(&style); replacements.append((range,style.attributes(theme:deck.theme)))
            }
            for (range,attributes) in replacements { storage.setAttributes(attributes,range:range) }
            view.undoManager?.registerUndo(withTarget:view) { target in target.textStorage?.setAttributedString(before); target.didChangeText() }
            view.undoManager?.setActionName(name); view.didChangeText()
        }
        window?.makeFirstResponder(view); view.setSelectedRange(selection); return true
    }
    var pendingTextSlide: Slide? {
        guard let view=textEditor, let id=editingID, var changed=editor?.currentSlide, let i=changed.objects.firstIndex(where: { $0.id == id }) else { return nil }
        NativeText.store(view.attributedString(),in:&changed.objects[i])
        if changed.objects[i].name == "Title" { changed.title=String(view.string.prefix(120)) }
        return changed
    }
    func textDidChange(_ notification: Notification) {
        // The document serializer includes the active editor, even before focus leaves it.
        editor?.presentation.updateChangeCount(.changeDone)
        editor?.presentation.scheduleRecovery()
    }
    func finishText() {
        guard let view=textEditor, let id=editingID else { return }
        var changed=editor?.currentSlide ?? Slide()
        if let i=changed.objects.firstIndex(where: { $0.id == id }) {
            NativeText.store(view.attributedString(),in:&changed.objects[i])
            if changed.objects[i].name == "Title" { changed.title=String(view.string.prefix(120)) }
            if changed.objects[i].textStyle.fit == .expand {
                let object=changed.objects[i]
                let size=(view.string as NSString).boundingRect(with:NSSize(width:object.frame.width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:object.textStyle.attributes(theme:deck.theme))
                changed.objects[i].frame.height=max(24,ceil(size.height)+4)
            }
        }
        textEditor=nil; editingID=nil; view.removeFromSuperview(); editor?.commit(changed,name:"Edit Text"); needsDisplay=true
    }
    override func resignFirstResponder() -> Bool { true }
    override func selectAll(_ sender: Any?) { selected=Set(slide.objects.filter { !$0.locked && !$0.hidden }.map(\.id)) }
    @objc func copy(_ sender: Any?) { editor?.copyObjects(sender) }
    @objc func cut(_ sender: Any?) { editor?.copyObjects(sender); editor?.deleteObjects(sender) }
    @objc func paste(_ sender: Any?) { editor?.pasteObjects(sender) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { editor?.insertImages(from:sender.draggingPasteboard) ?? false }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu=NSMenu()
        for (title,action) in [("Cut",#selector(cut(_:))),("Copy",#selector(copy(_:))),("Paste",#selector(paste(_:)))] { menu.addItem(withTitle:title,action:action,keyEquivalent:"") }
        for (title,action) in [("Duplicate",#selector(EditorWindowController.duplicateObjects(_:))),("Group",#selector(EditorWindowController.groupObjects(_:))),("Ungroup",#selector(EditorWindowController.ungroupObjects(_:))),("Lock / Unlock",#selector(EditorWindowController.toggleLock(_:))),("Bring to Front",#selector(EditorWindowController.bringToFront(_:))),("Delete",#selector(EditorWindowController.deleteObjects(_:)))] { let item=menu.addItem(withTitle:title,action:action,keyEquivalent:""); item.target=editor }
        return menu
    }
    override func accessibilityChildren() -> [Any]? {
        slide.objects.filter { !$0.hidden }.map { object in
            let element=AccessibleSlideObject(); element.setAccessibilityRole(.button)
            element.onPress = { [weak self] in self?.selected=[object.id]; self?.window?.makeFirstResponder(self) }
            element.setAccessibilityLabel(object.name+(object.text.isEmpty ? "" : ": "+object.text)); element.setAccessibilityParent(self)
            if let window=window { element.setAccessibilityFrame(window.convertToScreen(convert(viewRect(object.frame),to:nil))) }
            element.setAccessibilityValue(selected.contains(object.id) ? "Selected" : "")
            return element
        }
    }
}
