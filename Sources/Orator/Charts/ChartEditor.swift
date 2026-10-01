import AppKit
import PresentationCore

final class ChartEditor: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    weak var editor: EditorWindowController?
    let objectID: UUID
    let slideID: UUID
    let grid=NSTableView(), title=NSTextField(), category=NSTextField(), value=NSTextField()
    let legend=NSButton(checkboxWithTitle:"Legend",target:nil,action:nil), lines=NSButton(checkboxWithTitle:"Gridlines",target:nil,action:nil), labels=NSButton(checkboxWithTitle:"Data labels",target:nil,action:nil)
    init(editor: EditorWindowController,object: SlideObject) {
        self.editor=editor; objectID=object.id; slideID=editor.currentSlide.id
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:540),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false); window.title="Chart Data"; window.isReleasedWhenClosed=false
        super.init(window:window); window.center()
        let root=NSStackView(); root.orientation = .vertical; root.spacing=12; root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16); root.frame=window.contentView!.bounds; root.autoresizingMask=[.width,.height]; window.contentView=root
        for (label,field) in [("Title",title),("Category / X axis",category),("Value / Y axis",value)] {
            let row=NSStackView(views:[NSTextField(labelWithString:label),field]); root.addArrangedSubview(row); field.widthAnchor.constraint(greaterThanOrEqualToConstant:500).isActive=true
        }
        let settings=NSStackView(views:[legend,lines,labels,NSButton(title:"Apply Labels",target:self,action:#selector(applySettings))]); root.addArrangedSubview(settings)
        let scroll=NSScrollView(); scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true; scroll.borderType = .bezelBorder
        grid.dataSource=self; grid.delegate=self; grid.allowsMultipleSelection=true; grid.gridStyleMask=[.solidHorizontalGridLineMask,.solidVerticalGridLineMask]; grid.usesAlternatingRowBackgroundColors=true; scroll.documentView=grid; root.addArrangedSubview(scroll); scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:240).isActive=true
        let actions: [(String,Selector)]=[("Add Category",#selector(addRow)),("Delete Category",#selector(deleteRow)),("Add Series",#selector(addSeries)),("Edit Series…",#selector(editSeries)),("Remove Series…",#selector(removeSeries))]
        root.addArrangedSubview(NSStackView(views:actions.map { NSButton(title:$0.0,target:self,action:$0.1) }))
        let hint=NSTextField(labelWithString:"Double-click cells to edit. Scatter charts use numeric category labels as X coordinates."); hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize:11); root.addArrangedSubview(hint)
        if let chart=object.chart { title.stringValue=chart.title; category.stringValue=chart.categoryAxisTitle ?? ""; value.stringValue=chart.valueAxisTitle ?? ""; legend.state=chart.showLegend == false ? .off : .on; lines.state=chart.showGridlines == false ? .off : .on; labels.state=chart.showDataLabels == true ? .on : .off }
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }
    var content: ChartContent? { editor?.editableSlide(slideID)?.objects.first { $0.id == objectID }?.chart }
    func save(_ chart: ChartContent,_ name: String,reload: Bool = true) { editor?.modifyObject(objectID,on:slideID,name:name) { $0.chart=chart }; if reload { rebuild() } }
    func rebuild() { for col in grid.tableColumns { grid.removeTableColumn(col) }; guard let chart=content else { return }; for (i,name) in (["Category"]+chart.dataSeries.map(\.name)).enumerated() { let column=NSTableColumn(identifier:.init(String(i))); column.title=name; column.isEditable=true; column.width=150; grid.addTableColumn(column) }; grid.reloadData() }
    func numberOfRows(in tableView: NSTableView) -> Int { content?.labels.count ?? 0 }
    func tableView(_ tableView: NSTableView,objectValueFor column: NSTableColumn?,row: Int) -> Any? { guard let chart=content, chart.labels.indices.contains(row), let c=Int(column?.identifier.rawValue ?? "") else { return nil }; if c == 0 { return chart.labels[row] }; guard chart.dataSeries.indices.contains(c-1) else { return nil }; return chart.dataSeries[c-1].values[row] }
    func tableView(_ tableView: NSTableView,setObjectValue object: Any?,for column: NSTableColumn?,row: Int) {
        guard var chart=content, chart.labels.indices.contains(row), let c=Int(column?.identifier.rawValue ?? "") else { return }
        let text=(object as? String) ?? (object as? NSNumber)?.stringValue ?? ""
        if c == 0 { chart.labels[row]=text }
        else { guard let number=Double(text), number.isFinite, abs(number) <= 1e12, chart.dataSeries.indices.contains(c-1) else { NSSound.beep(); grid.reloadData(); return }; var series=chart.dataSeries; series[c-1].values[row]=number; chart.setSeries(series) }
        save(chart,"Edit Chart Data",reload:false)
    }
    @objc func applySettings() { guard var chart=content else { return }; chart.title=title.stringValue; chart.categoryAxisTitle=category.stringValue; chart.valueAxisTitle=value.stringValue; chart.showLegend=legend.state == .on; chart.showGridlines=lines.state == .on; chart.showDataLabels=labels.state == .on; save(chart,"Format Chart") }
    @objc func addRow() { guard var chart=content else { return }; chart.insertCategory(); save(chart,"Add Chart Category") }
    @objc func deleteRow() { guard var chart=content else { return }; for row in grid.selectedRowIndexes.sorted().reversed() { chart.removeCategory(at:row) }; save(chart,"Delete Chart Category") }
    @objc func addSeries() { guard var chart=content, chart.dataSeries.count < 32 else { return }; chart.setSeries(chart.dataSeries+[ChartSeries(name:"Series \(chart.dataSeries.count+1)",values:Array(repeating:0,count:chart.labels.count))]); save(chart,"Add Chart Series") }
    func seriesSelection(_ title: String) -> Int? { guard let chart=content else { return nil }; let alert=NSAlert(); alert.messageText=title; let popup=NSPopUpButton(frame:NSRect(x:0,y:0,width:300,height:26)); popup.addItems(withTitles:chart.dataSeries.map(\.name)); alert.accessoryView=popup; alert.addButton(withTitle:"Continue"); alert.addButton(withTitle:"Cancel"); return alert.runModal() == .alertFirstButtonReturn ? popup.indexOfSelectedItem : nil }
    @objc func removeSeries() { guard let i=seriesSelection("Remove Series"), var chart=content, chart.dataSeries.count > 1 else { return }; var data=chart.dataSeries; data.remove(at:i); chart.setSeries(data); save(chart,"Remove Chart Series") }
    @objc func editSeries() {
        guard let i=seriesSelection("Edit Series"), var chart=content else { return }
        let alert=NSAlert(); alert.messageText="Series Appearance"; let name=NSTextField(string:chart.dataSeries[i].name), color=NSColorWell(); color.color=(chart.dataSeries[i].color ?? .accent).nsColor
        let row=NSStackView(views:[name,color]); row.frame=NSRect(x:0,y:0,width:360,height:32); alert.accessoryView=row; alert.addButton(withTitle:"Apply"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }; var data=chart.dataSeries; data[i].name=name.stringValue; data[i].color=RGBA(color.color); chart.setSeries(data); save(chart,"Format Chart Series")
    }
}
