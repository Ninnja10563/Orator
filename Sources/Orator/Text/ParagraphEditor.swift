import AppKit
import PresentationCore

extension EditorWindowController {
    @objc func showParagraphSettings(_ sender: Any?) {
        guard let object=currentSlide.objects.first(where: { canvas.selected.contains($0.id) }) else { return }
        let alert=NSAlert(); alert.messageText="Paragraph and character spacing"
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=8; stack.frame=NSRect(x:0,y:0,width:350,height:250)
        var fields: [String:NSTextField]=[:]
        let p=object.textStyle.paragraph ?? ParagraphSettings()
        for (title,value) in [("Line spacing",object.textStyle.lineSpacing),("Before paragraph",p.before),("After paragraph",p.after),("Indent",p.indent),("First line indent",p.firstLineIndent),("List level",Double(p.level)),("Character spacing",object.textStyle.tracking ?? 0)] {
            let field=NSTextField(string:String(value)); field.widthAnchor.constraint(equalToConstant:100).isActive=true; fields[title]=field
            stack.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:title),field]))
        }
        let list=NSPopUpButton(); list.addItems(withTitles:ListKind.allCases.map(\.displayName)); list.selectItem(withTitle:p.list.displayName); stack.addArrangedSubview(list)
        alert.accessoryView=stack; alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window!) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self=self else { return }
            let values=fields.mapValues { Double($0.stringValue) }
            guard values.values.allSatisfy({ $0?.isFinite == true }) else { return }
            func value(_ key: String) -> Double { min(1000,max(0,values[key]!!)) }
            self.formatText("Format Paragraph") { style in
                var paragraph=ParagraphSettings(); paragraph.before=value("Before paragraph"); paragraph.after=value("After paragraph")
                paragraph.indent=value("Indent"); paragraph.firstLineIndent=value("First line indent"); paragraph.level=Int(min(8,value("List level"))); paragraph.list=ListKind.allCases[list.indexOfSelectedItem]
                style.paragraph=paragraph; style.lineSpacing=value("Line spacing"); style.tracking=value("Character spacing")
            }
        }
    }
}
