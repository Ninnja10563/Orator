import AppKit
import PresentationCore

final class InspectorView: SurfaceView {
    weak var editor: EditorWindowController?
    private let stack=NSStackView()
    private var fields: [String:NSTextField]=[:]
    private let selectionLabel=NSTextField(labelWithString:"Slide")
    private var updating=false
    private var currentSection=""
    private var sections: [String:[NSView]]=[:]
    private var labeledViews: [String:NSView]=[:]
    private let fill=NSColorWell(), textColor=NSColorWell()
    private let layers=NSPopUpButton()
    private let theme=NSPopUpButton(), transition=NSPopUpButton(), font=NSPopUpButton(), alignment=NSPopUpButton(), chart=NSPopUpButton(), fit=NSPopUpButton()
    private let bold=NSButton(checkboxWithTitle:"Bold",target:nil,action:nil), italic=NSButton(checkboxWithTitle:"Italic",target:nil,action:nil), underline=NSButton(checkboxWithTitle:"Underline",target:nil,action:nil)
    override init(frame: NSRect) {
        super.init(frame:frame)
        let scroll=NSScrollView(); scroll.hasVerticalScroller=true; scroll.drawsBackground=false; scroll.translatesAutoresizingMaskIntoConstraints=false; addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:leadingAnchor),scroll.trailingAnchor.constraint(equalTo:trailingAnchor),scroll.topAnchor.constraint(equalTo:topAnchor),scroll.bottomAnchor.constraint(equalTo:bottomAnchor)])
        let body=FlippedView(); body.translatesAutoresizingMaskIntoConstraints=false; scroll.documentView=body
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=10; stack.translatesAutoresizingMaskIntoConstraints=false; body.addSubview(stack)
        NSLayoutConstraint.activate([body.widthAnchor.constraint(equalTo:scroll.widthAnchor),stack.leadingAnchor.constraint(equalTo:body.leadingAnchor,constant:18),stack.trailingAnchor.constraint(equalTo:body.trailingAnchor,constant:-18),stack.topAnchor.constraint(equalTo:body.topAnchor,constant:18),stack.bottomAnchor.constraint(equalTo:body.bottomAnchor,constant:-22)])
        selectionLabel.font = .systemFont(ofSize:16,weight:.semibold); stack.addArrangedSubview(selectionLabel)
        heading("LAYERS")
        layers.target=self; layers.action=#selector(selectLayer); row("Object",layers)
        button("Show / Hide Selection",#selector(visibility))
        button("Bring to Front",#selector(front)); button("Send to Back",#selector(back)); button("Lock / Unlock Selection",#selector(lock)); button("Unlock All Objects",#selector(unlock))
        heading("SLIDE")
        field("Title",key:"slideTitle"); field("Section",key:"section")
        heading("PRESENTATION")
        theme.addItems(withTitles:Theme.all.map(\.name)); theme.target=self; theme.action=#selector(changeTheme); row("Theme",theme)
        transition.addItems(withTitles:TransitionKind.allCases.map(\.rawValue)); transition.target=self; transition.action=#selector(changeTransition); row("Transition",transition)
        field("Duration",key:"duration"); field("Advance (s)",key:"advance")
        heading("ARRANGE")
        for (title,key) in [("Name","name"),("X","x"),("Y","y"),("Width","width"),("Height","height"),("Rotation","rotation"),("Opacity %","opacity")] { field(title,key:key) }
        heading("STYLE")
        fill.target=self; fill.action=#selector(changeFill); row("Fill",fill)
        font.addItems(withTitles:NSFontManager.shared.availableFontFamilies.sorted()); font.target=self; font.action=#selector(changeFont); row("Font",font)
        field("Size",key:"size")
        let traits=NSStackView(views:[bold,italic,underline]); traits.spacing=8; add(traits)
        for button in [bold,italic,underline] { button.target=self; button.action=#selector(changeTraits); button.font = .systemFont(ofSize:11) }
        textColor.target=self; textColor.action=#selector(changeTextColor); row("Text color",textColor)
        alignment.addItems(withTitles:TextAlignment.allCases.map(\.rawValue)); alignment.target=self; alignment.action=#selector(changeAlignment); row("Alignment",alignment)
        fit.addItems(withTitles:TextFit.allCases.map(\.rawValue)); fit.target=self; fit.action=#selector(changeFit); row("Text fit",fit)
        button("Paragraph and Lists…",#selector(paragraphSettings))
        button("Highlight Selection",#selector(highlightText))
        button("Strikethrough",#selector(strikeText))
        heading("CONTENT")
        chart.addItems(withTitles:ChartKind.allCases.map(\.rawValue)); chart.target=self; chart.action=#selector(changeChart); row("Chart type",chart)
        button("Edit table / chart data…",#selector(editData))
        button("Image: Fit / Fill",#selector(toggleImageFill))
        button("Flip Image Horizontally",#selector(flipImage))
        button("Crop Image…",#selector(cropImage))
        button("Reset Image Crop",#selector(resetCrop))
        button("Reset Theme Colors",#selector(resetColors))
        button("Playback Settings…",#selector(playbackSettings))
        button("Preview Media",#selector(previewMedia))

    }
    required init?(coder: NSCoder) { fatalError() }
    func add(_ view: NSView) { stack.addArrangedSubview(view); sections[currentSection,default:[]].append(view) }
    func heading(_ title: String) { currentSection=title; let label=NSTextField(labelWithString:title); label.font = .systemFont(ofSize:10,weight:.semibold); label.textColor = .secondaryLabelColor; add(label); stack.setCustomSpacing(6,after:label) }
    func row(_ title: String, _ control: NSView) {
        let label=NSTextField(labelWithString:title); label.font = .systemFont(ofSize:12); label.widthAnchor.constraint(equalToConstant:82).isActive=true
        let row=NSStackView(views:[label,control]); row.spacing=8; row.alignment = .centerY; add(row); labeledViews[title]=row; row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        control.setAccessibilityLabel(title)
    }
    func field(_ title: String,key: String) { let field=NSTextField(); field.target=self; field.action=#selector(changeField(_:)); field.identifier=NSUserInterfaceItemIdentifier(key); field.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular); fields[key]=field; row(title,field) }
    func button(_ title: String,_ selector: Selector) { let button=NSButton(title:title,target:self,action:selector); button.bezelStyle = .rounded; button.controlSize = .small; add(button); labeledViews[title]=button }
    func refresh() {
        guard let editor=editor else { return }; updating=true; defer { updating=false }
        let objects=editor.currentSlide.objects.filter { editor.canvas.selected.contains($0.id) }, object=objects.first
        for (name,views) in sections {
            let visible: Bool
            switch name {
            case "SLIDE","PRESENTATION": visible=object == nil
            case "ARRANGE": visible=object != nil
            case "STYLE": visible=object.map { [.text,.shape,.table].contains($0.kind) } ?? false
            case "CONTENT": visible=object.map { [.image,.chart,.table,.video,.audio].contains($0.kind) } ?? false
            default: visible=true
            }
            for view in views { view.isHidden = !visible }
        }
        for title in ["Show / Hide Selection","Bring to Front","Send to Back","Lock / Unlock Selection"] { (labeledViews[title] as? NSControl)?.isEnabled=object != nil }
        if let o=object {
            for title in ["Playback Settings…","Preview Media"] { labeledViews[title]?.isHidden = ![.video,.audio].contains(o.kind) }
            labeledViews["Chart type"]?.isHidden=o.kind != .chart
            labeledViews["Edit table / chart data…"]?.isHidden = ![.chart,.table].contains(o.kind)
            for title in ["Image: Fit / Fill","Flip Image Horizontally","Crop Image…","Reset Image Crop"] { labeledViews[title]?.isHidden=o.kind != .image }
            labeledViews["Reset Theme Colors"]?.isHidden=o.kind == .image
            labeledViews["Fill"]?.isHidden=o.kind != .shape
        }
        selectionLabel.stringValue=objects.count > 1 ? "\(objects.count) objects" : object?.name ?? "Slide"
        layers.removeAllItems(); layers.addItem(withTitle:"Choose an object")
        for object in editor.currentSlide.objects.reversed() {
            layers.addItem(withTitle:object.name+(object.hidden ? " (hidden)" : "")+(object.locked ? " (locked)" : ""))
            layers.lastItem?.representedObject=object.id.uuidString
            if editor.canvas.selected.contains(object.id) { layers.select(layers.lastItem) }
        }
        fields["slideTitle"]?.stringValue=editor.currentSlide.title; fields["section"]?.stringValue=editor.currentSlide.section
        theme.selectItem(withTitle:editor.presentation.deck.theme.name); transition.selectItem(withTitle:editor.currentSlide.transition.kind.rawValue)
        fields["duration"]?.doubleValue=editor.currentSlide.transition.duration; fields["advance"]?.doubleValue=editor.currentSlide.transition.advanceAfter ?? 0
        for (key,field) in fields where !["duration","advance","slideTitle","section"].contains(key) { field.isEnabled=object != nil; if object == nil { field.stringValue="—" } }
        guard let o=object else { return }
        fields["name"]?.stringValue=o.name
        for (key,value) in [("x",o.frame.x),("y",o.frame.y),("width",o.frame.width),("height",o.frame.height),("rotation",o.rotation),("opacity",o.opacity*100),("size",o.textStyle.size)] { fields[key]?.stringValue=String(format:"%.1f",value) }
        fill.color=(o.style.fill ?? editor.presentation.deck.theme.accent).nsColor; textColor.color=(o.textStyle.color ?? editor.presentation.deck.theme.foreground).nsColor
        font.selectItem(withTitle:o.textStyle.fontName); alignment.selectItem(withTitle:o.textStyle.alignment.rawValue); fit.selectItem(withTitle:o.textStyle.fit.rawValue)
        bold.state=o.textStyle.bold ? .on : .off; italic.state=o.textStyle.italic ? .on : .off; underline.state=o.textStyle.underline ? .on : .off
        if let c=o.chart { chart.selectItem(withTitle:c.kind.rawValue) }
    }
    @objc func changeField(_ sender: NSTextField) {
        guard !updating, let key=sender.identifier?.rawValue, let editor=editor else { return }
        if key == "slideTitle" || key == "section" {
            var slide=editor.currentSlide
            if key == "slideTitle" { slide.title=sender.stringValue } else { slide.section=sender.stringValue }
            editor.commit(slide,name:"Edit Slide Details"); return
        }
        if key == "name" { editor.mutateSelection("Rename Object") { $0.name=sender.stringValue }; return }
        guard let value=Double(sender.stringValue), value.isFinite else { refresh(); return }
        if key == "duration" || key == "advance" {
            var slide=editor.currentSlide
            if key == "duration" { slide.transition.duration=min(10,max(0,value)) } else { slide.transition.advanceAfter=value > 0 ? min(86400,max(0.2,value)) : nil }
            editor.commit(slide,name:"Change Transition"); return
        }
        if key == "size" { editor.formatText("Change Font Size") { $0.size=min(1000,max(1,value)) }; return }
        editor.mutateSelection("Format Object") { o in
            var f=o.frame
            switch key {
            case "x":f.x=min(1_000_000,max(-1_000_000,value))
            case "y":f.y=min(1_000_000,max(-1_000_000,value))
            case "width":f.width=min(1_000_000,max(1,value))
            case "height":f.height=min(1_000_000,max(1,value))
            case "rotation":o.rotation=value.truncatingRemainder(dividingBy:360)
            case "opacity":o.opacity=min(1,max(0,value/100))
            case "size":o.textStyle.size=min(1000,max(1,value))
            default:break
            }; o.transform(to:f)
        }
    }
    @objc func selectLayer() {
        guard let id=(layers.selectedItem?.representedObject as? String).flatMap(UUID.init(uuidString:)) else { return }
        editor?.canvas.selected=[id]
    }
    @objc func visibility() { editor?.toggleVisibility(nil) }
    @objc func changeTheme() { guard !updating, let editor=editor else { return }; editor.canvas.finishText(); editor.presentation.perform(.setTheme(Theme.all[theme.indexOfSelectedItem]),named:"Change Theme") }
    @objc func changeTransition() { guard !updating, let editor=editor else { return }; var slide=editor.currentSlide; slide.transition.kind=TransitionKind.allCases[transition.indexOfSelectedItem]; editor.commit(slide,name:"Change Transition") }
    @objc func changeFill() { editor?.mutateSelection("Change Fill") { $0.style.fill=RGBA(fill.color) } }
    @objc func changeTextColor() { editor?.formatText("Change Text Color") { $0.color=RGBA(textColor.color) } }
    @objc func changeFont() { editor?.formatText("Change Font") { $0.fontName=font.titleOfSelectedItem ?? "Helvetica Neue" } }
    @objc func changeTraits() { editor?.formatText("Format Text") { $0.bold=bold.state == .on; $0.italic=italic.state == .on; $0.underline=underline.state == .on } }
    @objc func changeAlignment() { editor?.formatText("Align Text") { $0.alignment=TextAlignment.allCases[alignment.indexOfSelectedItem] } }
    @objc func changeFit() { editor?.mutateSelection("Change Text Fit") { $0.textStyle.fit=TextFit.allCases[fit.indexOfSelectedItem] } }
    @objc func changeChart() { editor?.mutateSelection("Change Chart Type") { $0.chart?.kind=ChartKind.allCases[chart.indexOfSelectedItem] } }
    @objc func editData() { editor?.editData(nil) }
    @objc func toggleImageFill() { editor?.mutateSelection("Fit Image") { $0.image?.fill.toggle() } }
    @objc func flipImage() { editor?.mutateSelection("Flip Image") { $0.image?.flippedHorizontally.toggle() } }
    @objc func resetCrop() { editor?.mutateSelection("Reset Crop") { $0.image?.crop=Rect(0,0,1,1) } }
    @objc func cropImage() {
        guard let editor=editor, let object=editor.currentSlide.objects.first(where: { editor.canvas.selected.contains($0.id) }), let image=object.image else { return }
        let alert=NSAlert(); alert.messageText="Crop image"; alert.informativeText="Enter the source crop as percentages: left, top, width, height. The original image is preserved."
        let field=NSTextField(frame:NSRect(x:0,y:0,width:320,height:24)); let c=image.crop; field.stringValue="\(c.x*100), \(c.y*100), \(c.width*100), \(c.height*100)"; alert.accessoryView=field; alert.addButton(withTitle:"Crop"); alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:editor.window!) { response in
            guard response == .alertFirstButtonReturn else { return }
            let values=field.stringValue.split(separator:",").compactMap { Double($0.trimmingCharacters(in:.whitespaces)) }
            guard values.count == 4, values.allSatisfy(\.isFinite), values[0] >= 0, values[1] >= 0, values[2] > 0, values[3] > 0, values[0]+values[2] <= 100, values[1]+values[3] <= 100 else { editor.presentation.presentError(FormatError.invalid("crop percentages must stay inside the image")); return }
            editor.mutateSelection("Crop Image") { $0.image?.crop=Rect(values[0]/100,values[1]/100,values[2]/100,values[3]/100) }
        }
    }
    @objc func resetColors() { editor?.mutateSelection("Reset Theme Colors") { $0.style.fill=nil; $0.textStyle.color=nil } }
    @objc func playbackSettings() { editor?.mediaSettings(nil) }
    @objc func previewMedia() { editor?.previewMedia(nil) }
    @objc func highlightText() { editor?.formatText("Highlight Text") { $0.highlight = $0.highlight == nil ? RGBA(1,0.9,0.3) : nil } }
    @objc func strikeText() { editor?.formatText("Strikethrough") { $0.strikethrough = !($0.strikethrough ?? false) } }
    @objc func paragraphSettings() { editor?.showParagraphSettings(nil) }
    @objc func front() { editor?.bringToFront(nil) }
    @objc func back() { editor?.sendToBack(nil) }
    @objc func lock() { editor?.toggleLock(nil) }
    @objc func unlock() { editor?.unlockAll(nil) }
}
