import AppKit
import PresentationCore

extension EditorWindowController {
    @objc func editMaster(_ sender: Any?) {
        canvas.finishText()
        if editingMasterID != nil { editingMasterID=nil; canvas.selected=[]; refresh(); return }
        if presentation.deck.masters?.isEmpty != false { presentation.perform(.setMasters([SlideMaster()]),named:"Create Master") }
        editingMasterID=currentSlide.masterID ?? presentation.deck.masters?.first?.id
        canvas.selected=[]; refresh()
    }
    @objc func addMaster(_ sender: Any?) {
        canvas.finishText(); var master=SlideMaster(); master.name="Master \((presentation.deck.masters?.count ?? 0)+1)"
        presentation.perform(.setMasters((presentation.deck.masters ?? [])+[master]),named:"Add Master")
        editingMasterID=master.id; canvas.selected=[]; refresh()
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
