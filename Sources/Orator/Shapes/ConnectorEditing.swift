import AppKit
import PresentationCore

extension SlideRenderer {
    func connectorPath(_ connector: Connector) -> NSBezierPath {
        let a=NSPoint(x:connector.start.point.x,y:connector.start.point.y), b=NSPoint(x:connector.end.point.x,y:connector.end.point.y), mid=(a.x+b.x)/2
        let path=NSBezierPath(); path.move(to:a); var tangent=a
        switch connector.kind {
        case .straight:path.line(to:b)
        case .elbow:path.line(to:NSPoint(x:mid,y:a.y)); path.line(to:NSPoint(x:mid,y:b.y)); path.line(to:b); tangent=NSPoint(x:mid,y:b.y)
        case .curved:path.curve(to:b,controlPoint1:NSPoint(x:mid,y:a.y),controlPoint2:NSPoint(x:mid,y:b.y)); tangent=NSPoint(x:mid,y:b.y)
        }
        if connector.arrow { let angle=atan2(b.y-tangent.y,b.x-tangent.x); path.move(to:NSPoint(x:b.x-14*cos(angle-0.5),y:b.y-14*sin(angle-0.5))); path.line(to:b); path.line(to:NSPoint(x:b.x-14*cos(angle+0.5),y:b.y-14*sin(angle+0.5))) }; return path
    }
}
extension EditorWindowController {
    @objc func insertConnector(_ sender: Any?) {
        let selected=currentSlide.objects.filter { canvas.selected.contains($0.id) && $0.connector == nil }
        let start=selected.first, end=selected.count > 1 ? selected[1] : nil
        let connector=Connector(start:ConnectorEndpoint(point:Point(160,260),objectID:start?.id,anchor:.right),end:ConnectorEndpoint(point:Point(640,420),objectID:end?.id,anchor:.left))
        var object=SlideObject(kind:.shape,name:"Connector",frame:connector.frame); object.shape = .line; object.connector=connector; object.style.stroke = .accent; object.style.strokeWidth=3; insert(object)
    }
    @objc func configureConnector(_ sender: Any?) {
        guard let object=currentSlide.objects.first(where: { canvas.selected.contains($0.id) }), let connector=object.connector else { return }; let slideID=currentSlide.id
        let targets=currentSlide.objects.filter { $0.id != object.id && $0.connector == nil }
        let alert=NSAlert(); alert.messageText="Connector"; let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=12; stack.frame=NSRect(x:0,y:0,width:460,height:140)
        let kind=NSPopUpButton(), start=NSPopUpButton(), end=NSPopUpButton(), startAnchor=NSPopUpButton(), endAnchor=NSPopUpButton()
        kind.addItems(withTitles:ConnectorKind.allCases.map(\.displayName)); kind.selectItem(withTitle:connector.kind.displayName)
        for popup in [start,end] { popup.addItems(withTitles:["Free endpoint"]+targets.map(\.name)) }
        for popup in [startAnchor,endAnchor] { popup.addItems(withTitles:ConnectionAnchor.allCases.map(\.displayName)) }
        start.selectItem(at:targets.firstIndex(where: { $0.id == connector.start.objectID }).map { $0+1 } ?? 0); end.selectItem(at:targets.firstIndex(where: { $0.id == connector.end.objectID }).map { $0+1 } ?? 0)
        startAnchor.selectItem(withTitle:connector.start.anchor.displayName); endAnchor.selectItem(withTitle:connector.end.anchor.displayName)
        let arrow=NSButton(checkboxWithTitle:"Arrowhead",target:nil,action:nil); arrow.state=connector.arrow ? .on : .off
        let rows: [[NSView]]=[[NSTextField(labelWithString:"Path"),kind,arrow],[NSTextField(labelWithString:"Start"),start,startAnchor],[NSTextField(labelWithString:"End"),end,endAnchor]]
        for views in rows { stack.addArrangedSubview(NSStackView(views:views)) }
        alert.accessoryView=stack; alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel"); guard alert.runModal() == .alertFirstButtonReturn else { return }
        modifyObject(object.id,on:slideID,name:"Configure Connector") { value in value.connector?.kind=ConnectorKind.allCases[kind.indexOfSelectedItem]; value.connector?.arrow=arrow.state == .on; value.connector?.start.objectID=start.indexOfSelectedItem == 0 ? nil : targets[start.indexOfSelectedItem-1].id; value.connector?.end.objectID=end.indexOfSelectedItem == 0 ? nil : targets[end.indexOfSelectedItem-1].id; value.connector?.start.anchor=ConnectionAnchor.allCases[startAnchor.indexOfSelectedItem]; value.connector?.end.anchor=ConnectionAnchor.allCases[endAnchor.indexOfSelectedItem] }
    }
}
