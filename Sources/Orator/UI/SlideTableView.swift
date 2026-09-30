import AppKit

final class SlideTableView: NSTableView {
    weak var editor: EditorWindowController?
    @objc func copy(_ sender: Any?) { editor?.copySlides(sender) }
    @objc func cut(_ sender: Any?) { editor?.copySlides(sender); editor?.deleteSlides(sender) }
    @objc func paste(_ sender: Any?) { editor?.pasteSlides(sender) }
    override func keyDown(with event: NSEvent) {
        if [51,117].contains(event.keyCode) { editor?.deleteSlides(nil); return }
        if event.keyCode == 36 { window?.makeFirstResponder(editor?.canvas); return }
        super.keyDown(with:event)
    }
}
