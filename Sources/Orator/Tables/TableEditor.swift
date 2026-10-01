import AppKit
import PresentationCore

final class TableEditor: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    weak var editor: EditorWindowController?
    let objectID: UUID
    let grid=NSTableView()
    let rowHeight=NSTextField(string:"40"), padding=NSTextField(string:"10")
    let fill=NSColorWell(), vertical=NSPopUpButton()
    var rebuilding=false
    var resizeTimer: Timer?
    init(editor: EditorWindowController,object: SlideObject) {
        self.editor=editor; objectID=object.id
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:880,height:520),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false); window.title="Edit Table"; window.isReleasedWhenClosed=false
        super.init(window:window); window.center()
        let root=SurfaceView(frame:window.contentView!.bounds); root.autoresizingMask=[.width,.height]; window.contentView=root
        let scroll=NSScrollView(frame:NSRect(x:16,y:16,width:848,height:350)); scroll.autoresizingMask=[.width,.height]; scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true; scroll.borderType = .bezelBorder
        grid.dataSource=self; grid.delegate=self; grid.allowsMultipleSelection=true; grid.allowsColumnSelection=true; grid.usesAlternatingRowBackgroundColors=true; grid.gridStyleMask=[.solidHorizontalGridLineMask,.solidVerticalGridLineMask]; scroll.documentView=grid; root.addSubview(scroll)
        let actions: [(String,Selector)]=[("Add Row",#selector(addRow)),("Delete Row",#selector(deleteRow)),("Add Column",#selector(addColumn)),("Delete Column",#selector(deleteColumn)),("Merge",#selector(merge)),("Split",#selector(split))]
        let buttons=NSStackView(views:actions.map { NSButton(title:$0.0,target:self,action:$0.1) }); buttons.frame=NSRect(x:16,y:382,width:848,height:28); buttons.autoresizingMask=[.width,.minYMargin]; root.addSubview(buttons)
        vertical.addItems(withTitles:VerticalAlignment.allCases.map(\.rawValue)); fill.color = .white
        let style=NSStackView(views:[NSTextField(labelWithString:"Row height"),rowHeight,NSTextField(labelWithString:"Padding"),padding,fill,vertical,NSButton(title:"Apply to Selected Cells",target:self,action:#selector(styleCells))]); style.frame=NSRect(x:16,y:425,width:848,height:32); style.autoresizingMask=[.width,.minYMargin]; root.addSubview(style)
        let help=NSTextField(labelWithString:"Double-click to edit. Shift-select rows and column headers for a rectangular range. Drag column dividers to resize."); help.font = .systemFont(ofSize:11); help.textColor = .secondaryLabelColor; help.frame=NSRect(x:16,y:478,width:848,height:24); help.autoresizingMask=[.width,.minYMargin]; root.addSubview(help)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }
    var content: TableContent? { editor?.currentSlide.objects.first { $0.id == objectID }?.table }
    func save(_ content: TableContent,name: String,reload: Bool = true) {
        guard let editor=editor, let index=editor.currentSlide.objects.firstIndex(where: { $0.id == objectID }) else { return }
        var slide=editor.currentSlide; slide.objects[index].table=content; editor.commit(slide,name:name)
        if reload { rebuild() }
    }
    func rebuild() {
        rebuilding=true; defer { rebuilding=false }
        for column in grid.tableColumns { grid.removeTableColumn(column) }
        guard let content=content else { return }
        for c in 0..<(content.cells.first?.count ?? 0) {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(String(c))); column.title="\(c+1)"; column.width=max(50,content.columnWidths?[c] ?? 150); column.isEditable=true; grid.addTableColumn(column)
        }; grid.reloadData()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { content?.cells.count ?? 0 }
    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? { guard let c=Int(column?.identifier.rawValue ?? "") else { return nil }; return content?.cells[row][c] }
    func tableView(_ tableView: NSTableView, setObjectValue value: Any?, for column: NSTableColumn?, row: Int) {
        guard var table=content, let c=Int(column?.identifier.rawValue ?? "") else { return }; table.cells[row][c]=value as? String ?? ""; save(table,name:"Edit Table Cell",reload:false)
    }
    func tableViewColumnDidResize(_ notification: Notification) {
        guard !rebuilding else { return }; resizeTimer?.invalidate()
        resizeTimer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:false) { [weak self] _ in guard let self=self, var table=self.content else { return }; table.columnWidths=self.grid.tableColumns.map { Double($0.width) }; self.save(table,name:"Resize Table Columns",reload:false) }
    }
    var rows: [Int] { grid.selectedRowIndexes.isEmpty ? [max(0,grid.editedRow)] : Array(grid.selectedRowIndexes) }
    var columns: [Int] { grid.selectedColumnIndexes.isEmpty ? [max(0,grid.editedColumn)] : Array(grid.selectedColumnIndexes) }
    @objc func addRow() { guard var table=content else { return }; table.insertRow(at:min(table.cells.count,(rows.last ?? 0)+1)); save(table,name:"Add Table Row") }
    @objc func deleteRow() { guard var table=content else { return }; for row in rows.sorted().reversed() { table.removeRow(at:row) }; save(table,name:"Delete Table Rows") }
    @objc func addColumn() { guard var table=content else { return }; table.insertColumn(at:min(table.cells.first?.count ?? 0,(columns.last ?? 0)+1)); save(table,name:"Add Table Column") }
    @objc func deleteColumn() { guard var table=content else { return }; for col in columns.sorted().reversed() { table.removeColumn(at:col) }; save(table,name:"Delete Table Columns") }
    @objc func merge() {
        guard var table=content, let r=rows.first, let c=columns.first else { return }
        do { try table.merge(CellMerge(row:r,column:c,rows:(rows.last ?? r)-r+1,columns:(columns.last ?? c)-c+1)); save(table,name:"Merge Cells") }
        catch { editor?.presentation.presentError(error) }
    }
    @objc func split() { guard var table=content else { return }; for r in rows { for c in columns { table.split(row:r,column:c) } }; save(table,name:"Split Cells") }
    @objc func styleCells() {
        guard var table=content, let height=Double(rowHeight.stringValue), height.isFinite, height > 0, let inset=Double(padding.stringValue), inset.isFinite, inset >= 0 else { return }
        if table.rowHeights == nil { table.rowHeights=Array(repeating:40,count:table.cells.count) }
        for r in rows where table.cells.indices.contains(r) {
            table.rowHeights?[r]=min(1000,height)
            for c in columns where table.cells[r].indices.contains(c) {
                let key="\(r):\(c)"; var style=table.styles?[key] ?? CellStyle(); style.fill=RGBA(fill.color); style.padding=min(100,inset); style.vertical=VerticalAlignment.allCases[vertical.indexOfSelectedItem]
                if table.styles == nil { table.styles=[:] }; table.styles?[key]=style
            }
        }; save(table,name:"Format Table Cells")
    }
}
