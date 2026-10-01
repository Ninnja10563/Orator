import AppKit
import PresentationCore

final class CommentsPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    weak var editor: EditorWindowController?
    let slideID: UUID
    let objectID: UUID?
    let table=NSTableView(), detail=NSTextView()
    init(editor: EditorWindowController) {
        self.editor=editor; slideID=editor.selectedSlideID; objectID=editor.canvas.selected.count == 1 ? editor.canvas.selected.first : nil
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:480),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="Comments — "+editor.currentSlide.title; window.isReleasedWhenClosed=false
        super.init(window:window); window.center()
        let root=NSStackView(); root.orientation = .vertical; root.spacing=12; root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16); root.frame=window.contentView!.bounds; root.autoresizingMask=[.width,.height]; window.contentView=root
        let scroll=NSScrollView(); scroll.hasVerticalScroller=true; scroll.borderType = .bezelBorder
        let column=NSTableColumn(identifier:.init("thread")); column.title="Discussion"; column.width=590; table.addTableColumn(column); table.headerView=nil; table.dataSource=self; table.delegate=self; table.rowHeight=30; scroll.documentView=table; root.addArrangedSubview(scroll); scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:160).isActive=true
        let details=NSScrollView(); details.hasVerticalScroller=true; details.documentView=detail; detail.isEditable=false; detail.isSelectable=true; detail.font = .systemFont(ofSize:13); detail.autoresizingMask=[.width]; detail.textContainer?.widthTracksTextView=true; detail.isVerticallyResizable=true; root.addArrangedSubview(details); details.heightAnchor.constraint(greaterThanOrEqualToConstant:140).isActive=true
        let buttons=NSStackView(views:[NSButton(title:objectID == nil ? "Add Slide Comment…" : "Comment on Object…",target:self,action:#selector(add)),NSButton(title:"Reply…",target:self,action:#selector(reply)),NSButton(title:"Resolve / Reopen",target:self,action:#selector(resolve)),NSButton(title:"Delete",target:self,action:#selector(delete))]); root.addArrangedSubview(buttons)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    var slide: Slide? { editor?.presentation.deck.slides.first { $0.id == slideID } }
    var comments: [Comment] { slide?.comments ?? [] }
    var selection: Int? { comments.indices.contains(table.selectedRow) ? table.selectedRow : nil }
    func numberOfRows(in tableView: NSTableView) -> Int { comments.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard comments.indices.contains(row) else { return nil }; let c=comments[row]
        let label=NSTextField(labelWithString:(c.resolved ? "Resolved · " : "")+c.author+" — "+c.text.replacingOccurrences(of:"\n",with:" ")); label.lineBreakMode = .byTruncatingTail; label.textColor=c.resolved ? .secondaryLabelColor : .labelColor; return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) { showDetail() }
    func showDetail() {
        guard let i=selection else { detail.string="Select a discussion to read it. Comments are saved in this presentation."; return }
        let c=comments[i]; let target=c.objectID.flatMap { id in slide?.objects.first { $0.id == id }?.name } ?? "Slide"
        detail.string="\(target) · \(c.author)\n\n\(c.text)"+(c.replies.isEmpty ? "" : "\n\n"+c.replies.joined(separator:"\n\n"))
    }
    func refresh() { let row=table.selectedRow; table.reloadData(); if comments.indices.contains(row) { table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }; showDetail() }
    func change(_ name: String,_ edit: (inout Slide) -> Void) { guard var slide=slide else { return }; edit(&slide); editor?.presentation.perform(.replaceSlide(slide),named:name); refresh() }
    func input(_ title: String) -> String? {
        let alert=NSAlert(); alert.messageText=title; alert.addButton(withTitle:"Save"); alert.addButton(withTitle:"Cancel")
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:420,height:140)); scroll.hasVerticalScroller=true; scroll.borderType = .bezelBorder
        let text=NSTextView(frame:scroll.bounds); text.isRichText=false; text.font = .systemFont(ofSize:13); text.autoresizingMask=[.width]; text.textContainer?.widthTracksTextView=true; scroll.documentView=text; alert.accessoryView=scroll; alert.window.initialFirstResponder=text
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }; let value=text.string.trimmingCharacters(in:.whitespacesAndNewlines); return value.isEmpty ? nil : value
    }
    @objc func add() { guard let text=input("Add Comment") else { return }; change("Add Comment") { $0.comments.append(Comment(text:text,author:NSFullUserName(),objectID:objectID)) }; table.selectRowIndexes(IndexSet(integer:max(0,comments.count-1)),byExtendingSelection:false) }
    @objc func reply() { guard let i=selection, let text=input("Reply") else { return }; let id=comments[i].id; change("Reply to Comment") { slide in if let index=slide.comments.firstIndex(where: { $0.id == id }) { slide.comments[index].replies.append(NSFullUserName()+": "+text) } } }
    @objc func resolve() { guard let i=selection else { return }; change(comments[i].resolved ? "Reopen Comment" : "Resolve Comment") { $0.comments[i].resolved.toggle() } }
    @objc func delete() { guard let i=selection else { return }; change("Delete Comment") { $0.comments.remove(at:i) } }
}
extension EditorWindowController {
    @objc func showComments(_ sender: Any?) { canvas.finishText(); guard editingMasterID == nil else { NSSound.beep(); return }; let panel=CommentsPanel(editor:self); toolWindows.append(panel); panel.showWindow(nil) }
}
