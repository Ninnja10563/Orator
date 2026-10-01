import AppKit
import PDFKit
import PresentationCore

@objc(PresentationDocument)
final class PresentationDocument: NSDocument {
    static let recoveryQueue=DispatchQueue(label:"app.orator.recovery",qos:.utility)
    static let recoveryStore: RecoveryStore = {
        if CommandLine.arguments.contains(where: { $0 == "--recovery-write-test" || $0 == "--recovery-read-test" }), let path=ProcessInfo.processInfo.environment["ORATOR_RECOVERY_DIRECTORY"] { return RecoveryStore(directory:URL(fileURLWithPath:path)) }
        return RecoveryStore(directory:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Orator/Recovery",isDirectory:true))
    }()
    private let package=NativePackage()
    var recoverySession=UUID()
    private var recoveryTimer: Timer?
    var deck=Presentation()
    var didChange: (() -> Void)?
    override class var autosavesInPlace: Bool { true }
    override class var autosavesDrafts: Bool { true }
    override init() { super.init(); hasUndoManager=true }
    override func makeWindowControllers() { let editor=EditorWindowController(document:self); addWindowController(editor) }
    override func defaultDraftName() -> String { deck.title }
    var snapshot: Presentation {
        var snapshot=deck
        if let editor=windowControllers.first as? EditorWindowController, let pending=editor.canvas.pendingTextSlide, let edit=editor.replacementEdit(pending) { _=try? edit.apply(to:&snapshot) }
        return snapshot
    }
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper { try package.encode(snapshot) }
    override func read(from fileWrapper: FileWrapper,ofType typeName: String) throws { deck=try package.decode(fileWrapper) }
    override func data(ofType typeName: String) throws -> Data { try PresentationFile.encode(snapshot) }
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey:Any]) throws -> NSPrintOperation {
        let settings=printInfo.copy() as! NSPrintInfo; settings.dictionary().addEntries(from:printSettings)
        guard let pdf=PDFDocument(data:try PDFExporter.data(snapshot)), let operation=pdf.printOperation(for:settings,scalingMode:.pageScaleDownToFit,autoRotate:true) else { throw FormatError.invalid("could not prepare the presentation for printing") }
        return operation
    }
    override func close() {
        recoveryTimer?.invalidate()
        let session=recoverySession
        Self.recoveryQueue.async { Self.recoveryStore.remove(session) }
        super.close()
    }
    func scheduleRecovery() {
        recoveryTimer?.invalidate()
        recoveryTimer=Timer.scheduledTimer(withTimeInterval:0.8,repeats:false) { [weak self] _ in
            guard let self=self else { return }
            let record=RecoveryRecord(sessionID:self.recoverySession,originalPath:self.fileURL?.path,presentation:self.snapshot)
            Self.recoveryQueue.async {
                do { try Self.recoveryStore.write(record) }
                catch { NSLog("Orator recovery snapshot failed: %@",error.localizedDescription) }
            }
        }
    }
    override func read(from data: Data, ofType typeName: String) throws { deck=try PresentationFile.decode(data) }
    func perform(_ edit: Edit, named name: String) {
        do {
            let inverse=try edit.apply(to:&deck)
            undoManager?.registerUndo(withTarget:self) { target in target.perform(inverse,named:name) }
            undoManager?.setActionName(name)
            didChange?(); scheduleRecovery()
        } catch { presentError(error) }
    }
}
