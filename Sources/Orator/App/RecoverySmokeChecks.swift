import AppKit
import PresentationCore

extension AppDelegate {
    func runRecoveryCheck() -> Bool {
        guard CommandLine.arguments.contains("--recovery-write-test") || CommandLine.arguments.contains("--recovery-read-test") else { return false }
        guard let path=ProcessInfo.processInfo.environment["ORATOR_RECOVERY_DIRECTORY"] else { fatalError("Recovery test directory missing") }
        let directory=URL(fileURLWithPath:path)
        do {
            if CommandLine.arguments.contains("--recovery-write-test") {
                let document=PresentationDocument(); document.deck.title="Unsaved recovery test"
                NSDocumentController.shared.addDocument(document); document.makeWindowControllers(); document.showWindows()
                let editor=document.windowControllers[0] as! EditorWindowController
                editor.canvas.beginText(editor.currentSlide.objects[0])
                let text=editor.canvas.subviews.compactMap { $0 as? NSTextView }.first!
                text.string="Recovered active text"; text.didChangeText()
                DispatchQueue.main.asyncAfter(deadline:.now()+2) {
                    PresentationDocument.recoveryQueue.sync {}
                    guard let record=try? PresentationDocument.recoveryStore.records().first, record.presentation.slides[0].objects[0].text == "Recovered active text" else { fatalError("Recovery did not capture active editing") }
                    try! Data("ready".utf8).write(to:directory.appendingPathComponent("ready"),options:.atomic)
                }
            } else {
                let records=try PresentationDocument.recoveryStore.records()
                guard records.count == 1, records[0].presentation.title == "Unsaved recovery test" else { fatalError("Recovery snapshot missing after forced termination") }
                restoreRecoveryCopies()
                guard let document=NSDocumentController.shared.documents.first as? PresentationDocument, document.fileURL == nil, document.deck.title.hasPrefix("Recovered — "), document.deck.slides[0].objects[0].text == "Recovered active text" else { fatalError("Recovery did not reopen a labeled independent document") }
                document.updateChangeCount(.changeCleared); document.close()
                print("Forced-termination recovery: active text reopened as a labeled copy")
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } catch { fputs("Recovery check failed: \(error)\n",stderr); exit(1) }
        return true
    }
}
