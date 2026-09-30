import AppKit
import PresentationCore

@objc(PresentationDocument)
final class PresentationDocument: NSDocument {
    var deck=Presentation()
    var didChange: (() -> Void)?
    override class var autosavesInPlace: Bool { true }
    override class var autosavesDrafts: Bool { true }
    override init() { super.init(); hasUndoManager=true }
    override func makeWindowControllers() { let editor=EditorWindowController(document:self); addWindowController(editor) }
    override func data(ofType typeName: String) throws -> Data {
        var snapshot=deck
        if let editor=windowControllers.first as? EditorWindowController, let pending=editor.canvas.pendingTextSlide, let i=snapshot.slides.firstIndex(where: { $0.id == pending.id }) { snapshot.slides[i]=pending }
        return try PresentationFile.encode(snapshot)
    }
    override func read(from data: Data, ofType typeName: String) throws { deck=try PresentationFile.decode(data) }
    func perform(_ edit: Edit, named name: String) {
        do {
            let inverse=try edit.apply(to:&deck)
            undoManager?.registerUndo(withTarget:self) { target in target.perform(inverse,named:name) }
            undoManager?.setActionName(name)
            didChange?()
        } catch { presentError(error) }
    }
}
