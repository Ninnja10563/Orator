import AppKit
import PresentationCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--dark") { NSApp.appearance=NSAppearance(named:.darkAqua) }
        buildMenus(); NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--smoke-test") {
            do {
                let type=NSDocumentController.shared.defaultType ?? "app.orator.presentation"
                guard let document=try NSDocumentController.shared.makeUntitledDocument(ofType:type) as? PresentationDocument else { fatalError("Document registration failed") }
                NSDocumentController.shared.addDocument(document); document.makeWindowControllers(); document.showWindows()
                let editor=document.windowControllers[0] as! EditorWindowController
                document.undoManager?.groupsByEvent=false
                document.undoManager?.beginUndoGrouping()
                editor.insertTable(nil)
                document.undoManager?.endUndoGrouping()
                guard document.deck.slides[0].objects.count == 3 else { fatalError("Insertion failed") }
                document.undoManager?.undo()
                guard document.deck.slides[0].objects.count == 2 else { fatalError("Undo failed") }
                document.undoManager?.redo()
                guard document.deck.slides[0].objects.count == 3 else { fatalError("Redo failed") }
                document.deck.slides[0].objects[0].frame=Rect(80,64,1120,100)
                document.deck.slides[0].objects[0].textStyle.size=56
                document.deck.slides[0].objects[1].frame=Rect(80,600,1120,64)
                document.deck.slides[0].objects[1].text="A clear view of the quarter ahead."
                document.deck.slides[0].objects[2].frame=Rect(80,210,1120,320)
                document.deck.slides[0].objects[2].table?.cells=[["Quarter","Revenue","Growth"],["Q1","$24 million","12%"],["Q2","$38 million","18%"]]
                document.deck.slides[0].notes="Smoke test notes"
                editor.refresh()
                try checkEditingInteractions(editor)
                try checkAdvancedEditing(editor)
                RunLoop.current.run(until:Date().addingTimeInterval(0.3))
                let data=try document.data(ofType:"app.orator.presentation"); _ = try PresentationFile.decode(data)
                let nativeURL=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".orator")
                try document.write(to:nativeURL,ofType:type)
                let reopened=try PresentationDocument(contentsOf:nativeURL,ofType:type)
                guard reopened.deck == document.deck else { fatalError("Native save/open failed") }
                try FileManager.default.removeItem(at:nativeURL)
                let image=SlideRenderer.shared.thumbnail(slide:document.deck.slides[0],deck:document.deck,size:NSSize(width:640,height:360))
                guard image.isValid else { fatalError("Rendering failed") }
                if let output=ProcessInfo.processInfo.environment["ORATOR_SMOKE_OUTPUT"] {
                    let url=URL(fileURLWithPath:output)
                    try image.tiffRepresentation?.write(to:url)
                    _=try PowerPoint.export(document.deck,to:url.deletingLastPathComponent().appendingPathComponent("smoke.pptx"))
                    var compatibility=document.deck
                    for kind in ChartKind.allCases { var slide=Slide(); var object=SlideObject(kind:.chart,name:"Chart",frame:Rect(80,80,1000,560)); var chart=ChartContent(); chart.kind=kind; chart.labels=["1","2","3","4"]; chart.setSeries([ChartSeries(name:"Revenue",values:[24,38,31,52]),ChartSeries(name:"Costs",values:[20,25,23,30])]); object.chart=chart; slide.objects=[object]; compatibility.slides.append(slide) }
                    var shapes=Slide()
                    for (i,kind) in ShapeKind.allCases.enumerated() { var object=SlideObject(kind:.shape,name:kind.displayName,frame:Rect(Double(i%4)*280+40,Double(i/4)*160+30,220,100)); object.shape=kind; object.style.gradient=GradientFill(end:RGBA(0.8,0.2,0.1),angle:30); object.style.shadow=ObjectShadow(); object.style.strokeWidth=2; object.style.stroke = .ink; object.opacity=0.7; shapes.objects.append(object) }
                    var connector=SlideObject(kind:.shape,name:"Attached",frame:Rect(0,0,1,1)); connector.shape = .line; connector.connector=Connector(start:ConnectorEndpoint(point:Point(),objectID:shapes.objects[0].id,anchor:.right),end:ConnectorEndpoint(point:Point(),objectID:shapes.objects[1].id,anchor:.left)); shapes.objects.append(connector); compatibility.slides.append(shapes)
                    for kind in TransitionKind.allCases { var slide=Slide(); slide.transition.kind=kind; slide.transition.direction = .up; slide.transition.duration=1.25; slide.transition.advanceAfter=4.5; slide.transition.advanceOnClick=false; compatibility.slides.append(slide) }
                    var grouped=Slide(); var group=SlideObject(kind:.group,name:"Editable group",frame:Rect(40,30,500,300)); group.rotation=12; group.children=Array(shapes.objects.prefix(2)); grouped.objects=[group]; compatibility.slides.append(grouped)
                    _=try PowerPoint.export(compatibility,to:url.deletingLastPathComponent().appendingPathComponent("compatibility.pptx"))
                    if let view=editor.window?.contentView?.superview {
                        view.layoutSubtreeIfNeeded()
                        func redraw(_ node: NSView) { node.needsDisplay=true; for child in node.subviews { redraw(child) } }
                        redraw(view); view.displayIfNeeded()
                        print("Canvas rendering: objects=\(editor.canvas.slide.objects.count), scale=\(editor.canvas.scale), selected=\(editor.canvas.selected.count)")
                        print("Workspace frames: root=\(view.frame), main=\(editor.split.frame), canvas=\(editor.canvas.frame), notes=\(editor.notesPane.frame)")
                        guard editor.canvas.bounds.height >= 360, editor.canvas.bounds.width >= 400 else { fatalError("Canvas collapsed during workspace layout") }
                        if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                            view.cacheDisplay(in:view.bounds,to:bitmap)
                            let screenshotName=CommandLine.arguments.contains("--dark") ? "workspace-dark.png" : "workspace.png"
                            try bitmap.representation(using:.png,properties:[:])?.write(to:url.deletingLastPathComponent().appendingPathComponent(screenshotName))
                        }
                    }
                }
                document.updateChangeCount(.changeCleared)
                print("Orator smoke test: document, editor window, serialization, and rendering passed")
                DispatchQueue.main.asyncAfter(deadline:.now()+2) { NSApp.terminate(nil) }
            } catch { fputs("Smoke test failed: \(error)\n",stderr); exit(1) }
        } else {
            restoreRecoveryCopies()
            if NSDocumentController.shared.documents.isEmpty { NSDocumentController.shared.newDocument(nil) }
        }
        NSApp.activate(ignoringOtherApps:true)
    }
    func restoreRecoveryCopies() {
        guard let records=try? PresentationDocument.recoveryStore.records() else { return }
        for record in records {
            let document=PresentationDocument(); document.deck=record.presentation
            document.deck.title="Recovered — "+(record.originalPath.map { URL(fileURLWithPath:$0).deletingPathExtension().lastPathComponent } ?? record.presentation.title)
            document.recoverySession=record.sessionID
            NSDocumentController.shared.addDocument(document); document.makeWindowControllers(); document.showWindows(); document.updateChangeCount(.changeDone)
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func buildMenus() {
        let main=NSMenu(); NSApp.mainMenu=main
        func menu(_ title: String) -> NSMenu { let item=NSMenuItem(title:title,action:nil,keyEquivalent:""); let submenu=NSMenu(title:title); item.submenu=submenu; main.addItem(item); return submenu }
        func item(_ menu: NSMenu,_ title: String,_ action: Selector,_ key: String = "",_ modifiers: NSEvent.ModifierFlags = .command) { let i=menu.addItem(withTitle:title,action:action,keyEquivalent:key); i.keyEquivalentModifierMask=modifiers }
        let app=menu("Orator"); item(app,"About Orator",#selector(NSApplication.orderFrontStandardAboutPanel(_:))); app.addItem(.separator()); item(app,"Hide Orator",#selector(NSApplication.hide(_:)),"h"); item(app,"Quit Orator",#selector(NSApplication.terminate(_:)),"q")
        let file=menu("File"); item(file,"New",#selector(NSDocumentController.newDocument(_:)),"n"); item(file,"Open…",#selector(NSDocumentController.openDocument(_:)),"o")
        item(file,"Import PowerPoint…",#selector(importPPTX(_:))); file.items.last?.target=self
        file.addItem(.separator()); item(file,"Close",#selector(NSWindow.performClose(_:)),"w"); item(file,"Save",#selector(NSDocument.save(_:)),"s"); item(file,"Save As…",#selector(NSDocument.saveAs(_:)),"s",[.command,.shift]); file.addItem(.separator())
        item(file,"Export PDF…",#selector(EditorWindowController.exportPDF(_:))); item(file,"Export PowerPoint…",#selector(EditorWindowController.exportPPTX(_:)))
        item(file,"Export Speaker Notes PDF…",#selector(EditorWindowController.exportNotesPDF(_:)))
        item(file,"Print…",#selector(NSDocument.printDocument(_:)),"p")
        let edit=menu("Edit"); item(edit,"Undo",Selector(("undo:")),"z"); item(edit,"Redo",Selector(("redo:")),"z",[.command,.shift]); edit.addItem(.separator())
        for (title,selector,key) in [("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] { item(edit,title,Selector(selector),key) }
        item(edit,"Duplicate Objects",#selector(EditorWindowController.duplicateObjects(_:)),"d"); item(edit,"Delete Objects",#selector(EditorWindowController.deleteObjects(_:)))
        let view=menu("View"); item(view,"Toggle Slide Navigator",#selector(EditorWindowController.toggleNavigator(_:))); item(view,"Toggle Inspector",#selector(EditorWindowController.toggleInspector(_:)),"i",[.command,.option]); item(view,"Toggle Speaker Notes",#selector(EditorWindowController.toggleNotes(_:))); item(view,"Fit Slide",#selector(EditorWindowController.fitSlide(_:)),"0")
        item(view,"Fit Width",#selector(EditorWindowController.fitWidth(_:)))
        item(view,"Zoom to Selection",#selector(EditorWindowController.zoomSelection(_:)))
        item(view,"Show / Hide Rulers",#selector(EditorWindowController.toggleRulers(_:)))
        for percent in [25,50,75,100,125,150,200,400] { item(view,"\(percent)%",#selector(EditorWindowController.setZoom(_:))); view.items.last?.tag=percent }
        item(view,"Toggle Guides",#selector(EditorWindowController.toggleGuides(_:))); item(view,"Add Vertical Center Guide",#selector(EditorWindowController.addGuide(_:))); item(view,"Add Horizontal Center Guide",#selector(EditorWindowController.addGuide(_:))); view.items.last?.tag=1; item(view,"Clear Guides",#selector(EditorWindowController.clearGuides(_:)))
        item(view,"Edit Guides…",#selector(EditorWindowController.editGuides(_:)))
        item(view,"Enter Full Screen",#selector(NSWindow.toggleFullScreen(_:)),"f",[.command,.control])
        let insert=menu("Insert")
        for (title,selector) in [("Text",#selector(EditorWindowController.addText(_:))),("Shape",#selector(EditorWindowController.insertShape(_:))),("Image…",#selector(EditorWindowController.insertImage(_:))),("Table",#selector(EditorWindowController.insertTable(_:))),("Chart",#selector(EditorWindowController.insertChart(_:)))] { item(insert,title,selector) }
        item(insert,"Connector",#selector(EditorWindowController.insertConnector(_:)))
        item(insert,"Video / Audio…",#selector(EditorWindowController.insertMedia(_:)))
        let slide=menu("Slide"); item(slide,"Add Slide…",#selector(EditorWindowController.addSlide(_:)),"n",[.command,.shift]); item(slide,"Duplicate Slides",#selector(EditorWindowController.duplicateSlides(_:))); item(slide,"Delete Slides",#selector(EditorWindowController.deleteSlides(_:))); item(slide,"Skip / Include Slide",#selector(EditorWindowController.skipSlide(_:)))
        item(slide,"Copy Slides",#selector(EditorWindowController.copySlides(_:)))
        item(slide,"Paste Slides",#selector(EditorWindowController.pasteSlides(_:)))
        item(slide,"Edit / Finish Editing Master",#selector(EditorWindowController.editMaster(_:)))
        item(slide,"Add Master",#selector(EditorWindowController.addMaster(_:)))
        item(slide,"Apply Master…",#selector(EditorWindowController.assignMaster(_:)))
        item(slide,"Background…",#selector(EditorWindowController.changeBackground(_:)))
        item(slide,"Save as Master Layout",#selector(EditorWindowController.saveAsMasterLayout(_:)))
        item(slide,"Apply Master Layout…",#selector(EditorWindowController.applyMasterLayout(_:)))
        item(slide,"Edit Master Layout…",#selector(EditorWindowController.editMasterLayout(_:)))
        item(slide,"Master Typography…",#selector(EditorWindowController.masterTypography(_:)))
        item(slide,"Use Master Typography for Selection",#selector(EditorWindowController.linkMasterTypography(_:)))
        item(slide,"Add Master Footer",#selector(EditorWindowController.addFooter(_:)))
        item(slide,"Animation Timeline…",#selector(EditorWindowController.showAnimations(_:)))
        item(slide,"Comments…",#selector(EditorWindowController.showComments(_:)))
        item(slide,"Configure Connector…",#selector(EditorWindowController.configureConnector(_:)))
        item(slide,"Object Appearance…",#selector(EditorWindowController.objectAppearance(_:)))
        let arrange=menu("Arrange"); item(arrange,"Group",#selector(EditorWindowController.groupObjects(_:)),"g",[.command,.option]); item(arrange,"Ungroup",#selector(EditorWindowController.ungroupObjects(_:)),"g",[.command,.option,.shift]); item(arrange,"Bring to Front",#selector(EditorWindowController.bringToFront(_:))); item(arrange,"Send to Back",#selector(EditorWindowController.sendToBack(_:))); item(arrange,"Lock / Unlock Selection",#selector(EditorWindowController.toggleLock(_:))); item(arrange,"Unlock All",#selector(EditorWindowController.unlockAll(_:))); arrange.addItem(.separator())
        item(arrange,"Bring Forward",#selector(EditorWindowController.bringForward(_:)))
        item(arrange,"Send Backward",#selector(EditorWindowController.sendBackward(_:)))
        item(arrange,"Edit Group",#selector(EditorWindowController.editSelectedGroup(_:)))
        item(arrange,"Finish Editing Group",#selector(EditorWindowController.finishGroupEditing(_:)))
        for (i,title) in ["Align Left","Align Center","Align Right","Align Top","Align Middle","Align Bottom","Distribute Horizontally","Distribute Vertically"].enumerated() { item(arrange,title,#selector(EditorWindowController.alignObjects(_:))); arrange.items.last?.tag=i }
        let present=menu("Present"); item(present,"Present from Current Slide",#selector(EditorWindowController.startPresentation(_:)),"p",[.command,.shift])
        item(present,"Rehearse Timings",#selector(EditorWindowController.rehearsePresentation(_:)))
        let window=menu("Window"); NSApp.windowsMenu=window; item(window,"Minimize",#selector(NSWindow.performMiniaturize(_:)),"m"); item(window,"Zoom",#selector(NSWindow.performZoom(_:)))
        let help=menu("Help"); item(help,"Orator Keyboard Shortcuts",#selector(showHelp)); help.items.last?.target=self
    }
    @objc func showHelp() { let alert=NSAlert(); alert.messageText="Work with Orator"; alert.informativeText="Double-click text to edit. Click the canvas to finish.\n\nShift-click adds to selection. Drag empty space to select. Tab cycles objects. Arrow keys nudge; Shift nudges by 10 points. Hold Option while dragging to bypass snapping. Shift constrains resize or rotation.\n\nDouble-click a table or chart to edit its data.\n\nPresent: arrows or Space navigate, B blacks the screen, P pauses, L toggles the laser pointer, D toggles the pen, H toggles the highlighter, E clears ink, J jumps to a slide, Escape ends. A second display shows the audience slide while your main display shows notes.\n\nOrator 0.1.0 — Foundation preview"; alert.runModal() }
    @objc func importPPTX(_ sender: Any?) {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.init(filenameExtension:"pptx")!]
        guard panel.runModal() == .OK, let url=panel.url else { return }
        do { let result=try PowerPoint.importDeck(from:url); let document=PresentationDocument(); document.deck=result.deck; NSDocumentController.shared.addDocument(document); document.makeWindowControllers(); document.showWindows(); document.updateChangeCount(.changeDone)
            if !result.warnings.isEmpty { let alert=NSAlert(); alert.messageText="PowerPoint import report"; alert.informativeText=result.warnings.joined(separator:"\n"); alert.runModal() }
        } catch { NSApp.presentError(error) }
    }
}
let application=NSApplication.shared
application.setActivationPolicy(.regular)
let delegate=AppDelegate()
application.delegate=delegate
application.run()
