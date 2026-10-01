import AppKit
import PresentationCore

final class AnimationPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    weak var editor: EditorWindowController?
    let slideID: UUID
    let table=NSTableView(), effect=NSPopUpButton(), trigger=NSPopUpButton(), direction=NSPopUpButton()
    let duration=NSTextField(string:"0.5"), delay=NSTextField(string:"0")
    let color=NSColorWell(), curved=NSButton(checkboxWithTitle:"Smooth motion path",target:nil,action:nil)
    init(editor: EditorWindowController) {
        self.editor=editor; slideID=editor.selectedSlideID
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:530),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.minSize=NSSize(width:760,height:530)
        window.title="Animation Timeline"; window.isReleasedWhenClosed=false
        super.init(window:window); window.center()
        let root=SurfaceView(frame:window.contentView!.bounds); root.autoresizingMask=[.width,.height]; window.contentView=root
        let scroll=NSScrollView(frame:NSRect(x:16,y:16,width:728,height:280)); scroll.autoresizingMask=[.width,.height]; scroll.hasVerticalScroller=true
        for (name,width) in [("Object",160.0),("Effect",120.0),("Trigger",120.0),("Start",90.0),("Duration",90.0)] { let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(name)); column.title=name; column.width=width; table.addTableColumn(column) }
        table.dataSource=self; table.delegate=self; scroll.documentView=table; root.addSubview(scroll)
        effect.addItems(withTitles:AnimationEffect.allCases.map(\.displayName)); trigger.addItems(withTitles:AnimationStart.allCases.map(\.displayName)); direction.addItems(withTitles:MotionDirection.allCases.map(\.displayName))
        let row=NSStackView(views:[effect,trigger,direction,NSTextField(labelWithString:"Seconds"),duration,NSTextField(labelWithString:"Delay"),delay]); row.frame=NSRect(x:16,y:310,width:728,height:30); row.autoresizingMask=[.width,.minYMargin]; root.addSubview(row)
        let buttons=NSStackView(views:[NSButton(title:"Add to Selection",target:self,action:#selector(add)),NSButton(title:"Update",target:self,action:#selector(update)),NSButton(title:"Move Up",target:self,action:#selector(up)),NSButton(title:"Move Down",target:self,action:#selector(down)),NSButton(title:"Remove",target:self,action:#selector(remove)),NSButton(title:"Preview",target:self,action:#selector(preview))]); buttons.frame=NSRect(x:16,y:360,width:728,height:32); buttons.autoresizingMask=[.width,.minYMargin]; root.addSubview(buttons)
        color.color=RGBA.accent.nsColor; color.widthAnchor.constraint(equalToConstant:44).isActive=true; color.setAccessibilityLabel("Emphasis color")
        let options=NSStackView(views:[NSTextField(labelWithString:"Emphasis color"),color,curved]); options.frame=NSRect(x:16,y:404,width:430,height:28); options.autoresizingMask=[.minYMargin]; root.addSubview(options)
        let help=NSTextField(wrappingLabelWithString:"Select an object on the slide, choose an effect, then Add. Clicks advance each On Click group during presentation. Select a motion-path row to show its points on the canvas. Drag points to adjust the path; Option-click to add a point. Escape hides the path.")
        help.frame=NSRect(x:16,y:452,width:720,height:60); help.autoresizingMask=[.width,.minYMargin]; help.textColor = .secondaryLabelColor; root.addSubview(help)
    }
    required init?(coder: NSCoder) { fatalError() }
    var slide: Slide? { editor?.presentation.deck.slides.first { $0.id == slideID } }
    var animations: [ObjectAnimation] { slide?.animations ?? [] }
    func numberOfRows(in tableView: NSTableView) -> Int { animations.count }
    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        guard animations.indices.contains(row) else { return nil }; let a=animations[row], schedule=AnimationEngine.schedule(animations)[row]
        switch column?.identifier.rawValue {
        case "Object":return slide?.objects.first { $0.id == a.objectID }?.name ?? "Object"
        case "Effect":return a.effect.displayName
        case "Trigger":return a.start.displayName
        case "Start":return "\(schedule.click): \(String(format:"%.2fs",schedule.start))"
        default:return String(format:"%.2fs",a.duration)
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard animations.indices.contains(table.selectedRow) else { return }; let a=animations[table.selectedRow]
        effect.selectItem(withTitle:a.effect.displayName); trigger.selectItem(withTitle:a.start.displayName); direction.selectItem(withTitle:a.direction.displayName); duration.doubleValue=a.duration; delay.doubleValue=a.delay; color.color=a.targetColor.nsColor; curved.state=a.curvedPath == true ? .on : .off
        if editor?.selectedSlideID == slideID { editor?.canvas.selected=[a.objectID]; editor?.canvas.motionPathID=a.effect == .motionPath ? a.id : nil }
    }
    func configured(_ animation: ObjectAnimation) -> ObjectAnimation {
        var a=animation; a.effect=AnimationEffect.allCases[effect.indexOfSelectedItem]; a.start=AnimationStart.allCases[trigger.indexOfSelectedItem]; a.direction=MotionDirection.allCases[direction.indexOfSelectedItem]
        a.targetColor=RGBA(color.color); a.curvedPath=curved.state == .on
        a.duration=min(60,max(0.01,duration.doubleValue.isFinite ? duration.doubleValue : 0.5)); a.delay=min(86400,max(0,delay.doubleValue.isFinite ? delay.doubleValue : 0)); return a
    }
    func save(_ animations: [ObjectAnimation]) { guard let editor=editor, var slide=slide else { return }; slide.animations=animations; editor.presentation.perform(.replaceSlide(slide),named:"Edit Animations"); table.reloadData() }
    @objc func add() {
        guard let editor=editor, editor.selectedSlideID == slideID else { return }
        let additions=editor.currentSlide.objects.filter { editor.canvas.selected.contains($0.id) }.map { object -> ObjectAnimation in
            var a=configured(ObjectAnimation(objectID:object.id,effect:.appear))
            if a.effect == .motionPath { a.path=[Point(object.frame.midX,object.frame.midY),Point(object.frame.midX+240,object.frame.midY)] }
            return a
        }; save(animations+additions)
    }
    @objc func update() { var list=animations; guard list.indices.contains(table.selectedRow) else { return }; list[table.selectedRow]=configured(list[table.selectedRow]); save(list) }
    @objc func remove() { var list=animations; guard list.indices.contains(table.selectedRow) else { return }; list.remove(at:table.selectedRow); save(list) }
    @objc func up() { move(-1) }; @objc func down() { move(1) }
    func move(_ offset: Int) { var list=animations; let index=table.selectedRow; guard list.indices.contains(index), list.indices.contains(index+offset) else { return }; list.swapAt(index,index+offset); save(list); table.selectRowIndexes(IndexSet(integer:index+offset),byExtendingSelection:false) }
    @objc func preview() { editor?.startPresentation(nil) }
}
extension EditorWindowController {
    @objc func showAnimations(_ sender: Any?) { let panel=AnimationPanel(editor:self); toolWindows.append(panel); panel.showWindow(nil) }
}
