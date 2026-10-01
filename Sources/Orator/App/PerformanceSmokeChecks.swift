import AppKit
import PresentationCore

func checkLargeDeckEditing(_ editor: EditorWindowController) throws {
    let document=editor.presentation, saved=document.deck
    var deck=saved; deck.slides=[]
    for index in 0..<500 {
        var slide=Slide(); slide.title="Scale check \(index+1)"
        for number in 0..<24 {
            var object=SlideObject(kind:number%2 == 0 ? .text : .shape,name:"Object \(number+1)",frame:Rect(Double(number%4)*280+40,Double(number/4)*100+40,240,70))
            object.text="Slide \(index+1), item \(number+1)"; object.textStyle.size=20; slide.objects.append(object)
        }
        deck.slides.append(slide)
    }
    document.deck=deck; editor.selectedSlideID=deck.slides[0].id; editor.canvas.selected=[]
    let started=Date(); editor.refresh(); editor.window?.contentView?.layoutSubtreeIfNeeded()
    let canvas=editor.canvas
    func event(_ type: NSEvent.EventType,_ point: Point) -> NSEvent {
        let local=NSPoint(x:canvas.slideRect.minX+point.x*canvas.scale,y:canvas.slideRect.minY+point.y*canvas.scale)
        return NSEvent.mouseEvent(with:type,location:canvas.convert(local,to:nil),modifierFlags:[.option],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:editor.window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
    }
    document.undoManager?.beginUndoGrouping()
    canvas.mouseDown(with:event(.leftMouseDown,Point(80,65)))
    let dragStarted=Date()
    for step in 1...60 { canvas.mouseDragged(with:event(.leftMouseDragged,Point(80+Double(step),65+Double(step)/2))); canvas.displayIfNeeded() }
    let frameMilliseconds=Date().timeIntervalSince(dragStarted)*1000/60
    canvas.mouseUp(with:event(.leftMouseUp,Point(140,95)))
    document.undoManager?.endUndoGrouping()
    guard document.deck.slides[0].objects[0].frame.x == 100 else { fatalError("Large-deck drag lost geometry") }
    document.undoManager?.undo()
    guard document.deck.slides[0] == deck.slides[0] else { fatalError("Large-deck drag undo failed") }
    let elapsed=Date().timeIntervalSince(started)
    // A coarse hang guard, not a claim about latency across all Mac hardware.
    guard elapsed < 20 else { fatalError("Large-deck editing exceeded the responsiveness guard") }
    print(String(format:"500-slide / 12,000-object native edit: %.2fs; 60 synchronous drag draws averaged %.2fms",elapsed,frameMilliseconds))
    document.deck=saved; document.undoManager?.removeAllActions(); editor.selectedSlideID=saved.slides[0].id; canvas.selected=[]; editor.refresh()
}
