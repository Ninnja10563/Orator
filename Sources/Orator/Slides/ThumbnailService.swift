import AppKit
import PresentationCore

/// Each worker owns its drawing context and image cache. Views stay on the main thread.
final class ThumbnailService {
    private struct Pending {
        var token: UUID
        var slide: Slide
        var theme: Theme
        var operation: BlockOperation
        var completions: [(NSImage) -> Void]
    }
    private let queue=OperationQueue()
    private let renderer=SlideRenderer()
    private var pending: [UUID:Pending]=[:]
    init() { queue.name="app.orator.thumbnails"; queue.maxConcurrentOperationCount=1; queue.qualityOfService = .userInitiated }
    func request(slide: Slide,deck: Presentation,completion: @escaping (NSImage) -> Void) {
        let resolved=deck.resolved(slide)
        if let existing=pending[slide.id], existing.slide == resolved, existing.theme == deck.theme { pending[slide.id]?.completions.append(completion); return }
        pending[slide.id]?.operation.cancel()
        let token=UUID(), operation=BlockOperation(), renderer=self.renderer
        pending[slide.id]=Pending(token:token,slide:resolved,theme:deck.theme,operation:operation,completions:[completion])
        operation.addExecutionBlock { [weak self,weak operation] in
            guard operation?.isCancelled == false else { return }
            let image: NSImage=autoreleasepool { renderer.thumbnail(slide:slide,deck:deck,size:NSSize(width:240,height:135)) }
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self=self, let entry=self.pending[slide.id], entry.token == token else { return }
                self.pending[slide.id]=nil; for completion in entry.completions { completion(image) }
            }
        }; queue.addOperation(operation)
    }
    deinit { queue.cancelAllOperations() }
}
