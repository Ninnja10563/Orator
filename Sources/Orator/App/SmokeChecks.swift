import AppKit
import PresentationCore

/// Run real AppKit input paths on the macOS CI runner, in addition to core unit tests.
func checkEditingInteractions(_ editor: EditorWindowController) throws {
    let document=editor.presentation, canvas=editor.canvas
    guard let window=editor.window else { fatalError("Editor window missing") }
    let original=editor.currentSlide
    canvas.selected=[]
    let accessible=canvas.accessibilityChildren()?.compactMap { $0 as? AccessibleSlideObject } ?? []
    guard accessible.count == original.objects.filter({ !$0.hidden }).count, let first=accessible.first,
          first === canvas.accessibilityChildren()?.first as? AccessibleSlideObject,
          first.accessibilityPerformPress(), canvas.selected.contains(original.objects[0].id) else { fatalError("Accessible slide selection failed or its identity changed") }
    canvas.selected=[]
    let backwards=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.shift],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48)!
    canvas.keyDown(with:backwards)
    guard canvas.selected == Set([original.objects.last!.id]) else { fatalError("Shift-Tab did not begin at the last object") }
    canvas.selected=[]
    func event(_ type: NSEvent.EventType,_ point: Point,_ modifiers: NSEvent.ModifierFlags = [.option]) -> NSEvent {
        let local=NSPoint(x:canvas.slideRect.minX+point.x*canvas.scale,y:canvas.slideRect.minY+point.y*canvas.scale)
        return NSEvent.mouseEvent(with:type,location:canvas.convert(local,to:nil),modifierFlags:modifiers,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
    }
    document.undoManager?.beginUndoGrouping()
    canvas.mouseDown(with:event(.leftMouseDown,Point(100,90)))
    canvas.mouseDragged(with:event(.leftMouseDragged,Point(130,110)))
    canvas.mouseUp(with:event(.leftMouseUp,Point(130,110)))
    document.undoManager?.endUndoGrouping()
    guard abs(editor.currentSlide.objects[0].frame.x-original.objects[0].frame.x-30) < 0.01 else { fatalError("Mouse drag did not move selected object") }
    document.undoManager?.undo()
    guard editor.currentSlide == original else { fatalError("Mouse drag undo failed") }

    canvas.beginText(original.objects[0])
    guard let text=canvas.subviews.compactMap({ $0 as? NSTextView }).first else { fatalError("Inline editor missing") }
    text.string="Uncommitted text is safe"
    let saved=try PresentationFile.decode(document.data(ofType:"app.orator.presentation"))
    guard saved.slides[0].objects[0].text == text.string else { fatalError("Save omitted active text") }
    document.undoManager?.beginUndoGrouping(); canvas.finishText(); document.undoManager?.endUndoGrouping()
    document.undoManager?.undo()
    guard editor.currentSlide == original else { fatalError("Inline text undo failed") }

    window.makeFirstResponder(editor.notes)
    document.undoManager?.beginUndoGrouping()
    editor.notes.string="Updated notes"
    editor.textDidChange(Notification(name:NSText.didChangeNotification,object:editor.notes))
    document.undoManager?.endUndoGrouping()
    document.undoManager?.undo()
    guard editor.notes.string == original.notes else { fatalError("Notes undo did not update the focused editor") }
    window.makeFirstResponder(canvas)

    let width=canvas.bounds.width
    editor.toggleInspector(nil); window.contentView?.layoutSubtreeIfNeeded()
    guard editor.inspector.isHidden else { fatalError("Inspector did not hide") }
    editor.toggleInspector(nil); window.contentView?.layoutSubtreeIfNeeded()
    guard !editor.inspector.isHidden, canvas.bounds.width > 0, width > 0 else { fatalError("Inspector did not restore") }
    editor.toggleNotes(nil); editor.toggleNotes(nil)
    editor.fitSlide(nil)
    canvas.selected=[]

    var connector=SlideObject(kind:.shape,name:"Connector interaction",frame:Rect(100,500,500,1)); connector.connector=Connector(start:ConnectorEndpoint(point:Point(100,500)),end:ConnectorEndpoint(point:Point(600,500)))
    document.undoManager?.beginUndoGrouping(); editor.insert(connector); document.undoManager?.endUndoGrouping()
    document.undoManager?.beginUndoGrouping()
    canvas.mouseDown(with:event(.leftMouseDown,Point(100,500))); canvas.mouseDragged(with:event(.leftMouseDragged,Point(130,530))); canvas.mouseUp(with:event(.leftMouseUp,Point(130,530)))
    document.undoManager?.endUndoGrouping()
    guard editor.currentSlide.objects.last?.connector?.start.point == Point(130,530) else { fatalError("Connector endpoint drag failed") }
    document.undoManager?.undo()
    guard editor.currentSlide.objects.last?.connector?.start.point == Point(100,500) else { fatalError("Connector endpoint undo failed") }
    let target=original.objects[0], anchor=ConnectionAnchor.right.point(on:original.objects[0])
    document.undoManager?.beginUndoGrouping()
    canvas.mouseDown(with:event(.leftMouseDown,Point(600,500),[])); canvas.mouseDragged(with:event(.leftMouseDragged,anchor,[])); canvas.mouseUp(with:event(.leftMouseUp,anchor,[]))
    document.undoManager?.endUndoGrouping()
    guard editor.currentSlide.objects.last?.connector?.end.objectID == target.id else { fatalError("Connector attachment snapping failed") }
    document.undoManager?.undo(); document.undoManager?.undo(); canvas.selected=[]

    var deck=document.deck
    let second=Layout.section.makeSlide(); deck.slides.append(second)
    deck.slides[0].transition.advanceOnClick=false
    let presenter=PresenterController(deck:deck,startID:deck.slides[0].id)
    presenter.rehearse=true
    let annotations=PresenterAnnotationView(audience:presenter.audience)
    guard annotations.hitTest(.zero) == nil else { fatalError("Annotation overlay blocked normal presentation input") }
    presenter.audience.inkTool = .pen
    guard annotations.hitTest(.zero) === annotations else { fatalError("Pen overlay did not receive input") }
    presenter.audience.inkTool = .none
    presenter.start(); presenter.advanceByClick(); guard presenter.index == 0 else { fatalError("Click advance ignored slide settings") }; presenter.slideStarted=Date().addingTimeInterval(-2); presenter.next()
    guard presenter.index == 1 else { fatalError("Presenter advance failed") }
    presenter.black(); guard presenter.audience.black else { fatalError("Black screen failed") }
    presenter.pause(); guard presenter.paused else { fatalError("Presenter pause failed") }
    presenter.previous(); guard presenter.audience.playbackSlide?.id == deck.slides[0].id else { fatalError("Paused navigation retained the wrong slide") }; guard presenter.index == 0 else { fatalError("Presenter previous failed") }
    presenter.end()
    guard (presenter.rehearsed[deck.slides[0].id] ?? 0) >= 2 else { fatalError("Rehearsal omitted slide timing") }
    guard presenter.audienceWindow == nil else { fatalError("Presenter did not end") }
    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas)
    print("Orator interaction checks: drag/undo, active-text save/undo, panels, and presenter passed")
}
