import AppKit
import PresentationCore

extension EditorWindowController {
    @objc func editGuides(_ sender: Any?) {
        canvas.finishText(); let slideID=currentSlide.id, guides=currentSlide.guides
        let alert=NSAlert(); alert.messageText="Guides"; alert.informativeText="One guide per line: V or H, followed by its position in slide points. Delete a line to remove a guide."
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:360,height:220)); scroll.hasVerticalScroller=true; scroll.borderType = .bezelBorder
        let text=NSTextView(frame:scroll.bounds); text.isRichText=false; text.font = .monospacedSystemFont(ofSize:13,weight:.regular); text.string=guides.map { "\($0.vertical ? "V" : "H") \(String(format:"%.1f",$0.position))" }.joined(separator:"\n"); scroll.documentView=text; alert.accessoryView=scroll
        alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel"); guard alert.runModal() == .alertFirstButtonReturn else { return }
        var values: [Guide]=[]
        for line in text.string.split(separator:"\n") {
            let parts=line.split(whereSeparator: { $0.isWhitespace }); guard parts.count == 2, ["V","H"].contains(parts[0].uppercased()), let value=Double(parts[1]), value.isFinite, abs(value) <= 1_000_000 else { presentation.presentError(FormatError.invalid("each guide needs V or H and a finite position")); return }
            values.append(Guide(vertical:parts[0].uppercased() == "V",position:value))
        }
        guard var slide=editableSlide(slideID) else { return }; slide.guides=values; if let edit=replacementEdit(slide) { presentation.perform(edit,named:"Edit Guides") }
    }
    @objc func bringForward(_ sender: Any?) { reorderOneStep(forward:true) }
    @objc func sendBackward(_ sender: Any?) { reorderOneStep(forward:false) }
    private func reorderOneStep(forward: Bool) {
        canvas.finishText(); var slide=currentSlide
        let indices=forward ? Array(slide.objects.indices.reversed()) : Array(slide.objects.indices)
        for i in indices where canvas.selected.contains(slide.objects[i].id) {
            let target=i+(forward ? 1 : -1)
            if slide.objects.indices.contains(target), !canvas.selected.contains(slide.objects[target].id) { slide.objects.swapAt(i,target) }
        }; commit(slide,name:forward ? "Bring Forward" : "Send Backward")
    }
}
