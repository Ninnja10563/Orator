import AppKit
import PresentationCore

extension EditorWindowController {
    @objc func objectAppearance(_ sender: Any?) {
        canvas.finishText(); guard let object=currentSlide.objects.first(where: { canvas.selected.contains($0.id) }) else { return }; let slideID=currentSlide.id
        let alert=NSAlert(); alert.messageText="Object Appearance"
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=10; stack.frame=NSRect(x:0,y:0,width:440,height:340)
        let fill=NSColorWell(), border=NSColorWell(), end=NSColorWell(), shadowColor=NSColorWell()
        fill.color=(object.style.fill ?? presentation.deck.theme.accent).nsColor; border.color=object.style.stroke.nsColor; end.color=(object.style.gradient?.end ?? .white).nsColor; shadowColor.color=(object.style.shadow?.color ?? RGBA(0,0,0,0.25)).nsColor
        let pattern=NSPopUpButton(); pattern.addItems(withTitles:BorderPattern.allCases.map(\.rawValue)); pattern.selectItem(withTitle:(object.style.borderPattern ?? .solid).rawValue)
        let gradient=NSButton(checkboxWithTitle:"Gradient fill",target:nil,action:nil), shadow=NSButton(checkboxWithTitle:"Shadow",target:nil,action:nil); gradient.state=object.style.gradient == nil ? .off : .on; shadow.state=object.style.shadow == nil ? .off : .on
        var fields: [String:NSTextField]=[:]
        func row(_ name: String,_ views: [NSView]) { let label=NSTextField(labelWithString:name); label.widthAnchor.constraint(equalToConstant:110).isActive=true; stack.addArrangedSubview(NSStackView(views:[label]+views)) }
        func field(_ name: String,_ value: Double) -> NSTextField { let field=NSTextField(string:String(value)); field.widthAnchor.constraint(equalToConstant:80).isActive=true; fields[name]=field; return field }
        row("Fill",[fill]); row("Border",[border,field("width",object.style.strokeWidth),pattern]); row("Corner radius",[field("radius",object.style.cornerRadius)])
        row("Gradient",[gradient,end,field("angle",object.style.gradient?.angle ?? 0)]); row("Shadow",[shadow,shadowColor]); row("Shadow blur",[field("blur",object.style.shadow?.blur ?? 8)]); row("Shadow offset",[field("x",object.style.shadow?.x ?? 0),field("y",object.style.shadow?.y ?? 4)])
        alert.accessoryView=stack; alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, fields.values.allSatisfy({ Double($0.stringValue)?.isFinite == true }) else { return }
        modifyObject(object.id,on:slideID,name:"Object Appearance") { value in
            value.style.fill=RGBA(fill.color); value.style.stroke=RGBA(border.color); value.style.strokeWidth=max(0,min(100,fields["width"]!.doubleValue)); value.style.cornerRadius=max(0,min(10000,fields["radius"]!.doubleValue)); value.style.borderPattern=BorderPattern.allCases[pattern.indexOfSelectedItem]
            value.style.gradient=gradient.state == .on ? GradientFill(end:RGBA(end.color),angle:fields["angle"]!.doubleValue.truncatingRemainder(dividingBy:360)) : nil
            if shadow.state == .on { var style=ObjectShadow(); style.color=RGBA(shadowColor.color); style.blur=max(0,min(1000,fields["blur"]!.doubleValue)); style.x=max(-1000,min(1000,fields["x"]!.doubleValue)); style.y=max(-1000,min(1000,fields["y"]!.doubleValue)); value.style.shadow=style } else { value.style.shadow=nil }
        }
    }
}
