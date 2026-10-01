import AppKit
import PresentationCore

extension EditorWindowController {
    @objc func editMaster(_ sender: Any?) {
        canvas.finishText(); editingGroupIDs=[]
        if editingMasterID != nil { editingMasterID=nil; editingLayoutID=nil; canvas.selected=[]; refresh(); return }
        if presentation.deck.masters?.isEmpty != false { presentation.perform(.setMasters([SlideMaster()]),named:"Create Master") }
        editingMasterID=currentSlide.masterID ?? presentation.deck.masters?.first?.id
        canvas.selected=[]; refresh()
    }
    @objc func addMaster(_ sender: Any?) {
        canvas.finishText(); editingGroupIDs=[]; var master=SlideMaster(); master.name="Master \((presentation.deck.masters?.count ?? 0)+1)"
        presentation.perform(.setMasters((presentation.deck.masters ?? [])+[master]),named:"Add Master")
        editingLayoutID=nil; editingMasterID=master.id; canvas.selected=[]; refresh()
    }
    @objc func assignMaster(_ sender: Any?) {
        guard editingMasterID == nil else { return }
        let menu=NSMenu()
        let none=menu.addItem(withTitle:"No Master",action:#selector(setSlideMaster(_:)),keyEquivalent:""); none.target=self
        for master in presentation.deck.masters ?? [] { let item=menu.addItem(withTitle:master.name,action:#selector(setSlideMaster(_:)),keyEquivalent:""); item.target=self; item.representedObject=master.id.uuidString }
        menu.popUp(positioning:nil,at:NSPoint(x:80,y:80),in:canvas)
    }
    @objc func setSlideMaster(_ sender: NSMenuItem) {
        var slide=currentSlide; slide.masterID=(sender.representedObject as? String).flatMap(UUID.init(uuidString:)); slide.layoutID=nil; commit(slide,name:"Apply Master")
    }
    @objc func changeBackground(_ sender: Any?) {
        let alert=NSAlert(); alert.messageText="Slide background"
        let well=NSColorWell(frame:NSRect(x:0,y:0,width:160,height:40)); well.color=(currentSlide.background ?? presentation.deck.theme.background).nsColor
        alert.accessoryView=well; alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Use Theme / Master"); alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window!) { [weak self] response in
            guard let self=self, response != .alertThirdButtonReturn else { return }
            var slide=self.currentSlide; slide.background=response == .alertSecondButtonReturn ? nil : RGBA(well.color); self.commit(slide,name:"Change Background")
        }
    }
    @objc func addFooter(_ sender: Any?) {
        guard editingMasterID != nil else { return }
        var footer=SlideObject(kind:.text,name:"Footer",frame:Rect(60,presentation.deck.height-52,presentation.deck.width-120,32))
        footer.text="Your organization"; footer.textStyle.size=16; insert(footer)
    }
}

extension EditorWindowController {
    @objc func saveAsMasterLayout(_ sender: Any?) {
        canvas.finishText(); editingGroupIDs=[]; guard editingMasterID == nil, let masterID=currentSlide.masterID, var masters=presentation.deck.masters, let m=masters.firstIndex(where: { $0.id == masterID }) else { NSSound.beep(); return }
        var objects=currentSlide.objects.map { $0.duplicated(offset:Point()) }
        for i in objects.indices { objects[i].placeholderKey=objects[i].name == "Title" ? "title" : "content\(i)"; objects[i].layoutLinked=nil }
        let layout=MasterLayout(name:currentSlide.title,objects:objects); masters[m].layouts.append(layout)
        presentation.perform(.setMasters(masters),named:"Create Master Layout"); editingMasterID=masterID; editingLayoutID=layout.id; canvas.selected=[]; refresh()
    }
    @objc func applyMasterLayout(_ sender: Any?) { layoutMenu(edit:false) }
    @objc func editMasterLayout(_ sender: Any?) { layoutMenu(edit:true) }
    private func layoutMenu(edit: Bool) {
        canvas.finishText(); editingGroupIDs=[]; let masterID=editingMasterID ?? currentSlide.masterID
        guard let master=presentation.deck.masters?.first(where: { $0.id == masterID }), !master.layouts.isEmpty else { let alert=NSAlert(); alert.messageText="No custom layouts yet"; alert.informativeText="Create a slide with the placeholders you need, then choose Slide → Save as Master Layout."; alert.runModal(); return }
        let menu=NSMenu()
        for layout in master.layouts { let item=menu.addItem(withTitle:layout.name,action:edit ? #selector(beginLayoutEditing(_:)) : #selector(assignLayout(_:)),keyEquivalent:""); item.target=self; item.representedObject=[master.id.uuidString,layout.id.uuidString] }
        menu.popUp(positioning:nil,at:NSPoint(x:80,y:80),in:canvas)
    }
    @objc func beginLayoutEditing(_ sender: NSMenuItem) { guard let ids=sender.representedObject as? [String] else { return }; editingMasterID=UUID(uuidString:ids[0]); editingLayoutID=UUID(uuidString:ids[1]); canvas.selected=[]; refresh() }
    @objc func assignLayout(_ sender: NSMenuItem) {
        guard editingMasterID == nil, let ids=sender.representedObject as? [String], let master=presentation.deck.masters?.first(where: { $0.id.uuidString == ids[0] }), let layout=master.layouts.first(where: { $0.id.uuidString == ids[1] }) else { return }
        var slide=currentSlide; slide.masterID=master.id; slide.layoutID=layout.id
        for template in layout.objects {
            if let key=template.placeholderKey, let existing=slide.objects.firstIndex(where: { $0.placeholderKey == key || (key == "title" && $0.name == "Title") }) { slide.objects[existing].placeholderKey=key; slide.objects[existing].layoutLinked=true }
            else { var copy=template.duplicated(offset:Point()); copy.layoutLinked=true; slide.objects.append(copy) }
        }; commit(slide,name:"Apply Layout")
    }
    @objc func masterTypography(_ sender: Any?) {
        let masterID=editingMasterID ?? currentSlide.masterID
        guard let master=presentation.deck.masters?.first(where: { $0.id == masterID }) else { return }
        let alert=NSAlert(); alert.messageText="Master Typography"
        let title=NSPopUpButton(), body=NSPopUpButton(); for popup in [title,body] { popup.addItems(withTitles:NSFontManager.shared.availableFontFamilies.sorted()) }
        title.selectItem(withTitle:master.titleFont.fontName); body.selectItem(withTitle:master.bodyFont.fontName)
        let titleSize=NSTextField(string:String(master.titleFont.size)), bodySize=NSTextField(string:String(master.bodyFont.size))
        let stack=NSStackView(views:[NSStackView(views:[NSTextField(labelWithString:"Title"),title,titleSize]),NSStackView(views:[NSTextField(labelWithString:"Body"),body,bodySize])]); stack.orientation = .vertical; stack.frame=NSRect(x:0,y:0,width:440,height:80); alert.accessoryView=stack; alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let ts=Double(titleSize.stringValue), let bs=Double(bodySize.stringValue), ts.isFinite, bs.isFinite else { return }
        guard var masters=presentation.deck.masters, let i=masters.firstIndex(where: { $0.id == masterID }) else { return }
        masters[i].titleFont.fontName=title.titleOfSelectedItem ?? "Helvetica Neue"; masters[i].titleFont.size=max(1,min(1000,ts)); masters[i].bodyFont.fontName=body.titleOfSelectedItem ?? "Helvetica Neue"; masters[i].bodyFont.size=max(1,min(1000,bs)); presentation.perform(.setMasters(masters),named:"Master Typography")
    }
    @objc func linkMasterTypography(_ sender: Any?) { mutateSelection("Use Master Typography") { object in object.masterTextLinked=true; if object.name == "Title" { object.placeholderKey="title" } } }
}
