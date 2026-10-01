import AppKit
import Vision
import CoreImage
import PresentationCore

protocol ImageProcessor: Sendable { func process(_ data: Data) async throws -> Data }
struct ForegroundProcessor: ImageProcessor {
    func process(_ data: Data) async throws -> Data {
        try await Task.detached(priority:.userInitiated) {
            let request=VNGenerateForegroundInstanceMaskRequest(), handler=VNImageRequestHandler(data:data,options:[:])
            try handler.perform([request])
            guard let observation=request.results?.first, !observation.allInstances.isEmpty else { throw FormatError.invalid("no foreground subject was detected in this image") }
            let buffer=try observation.generateMaskedImage(ofInstances:observation.allInstances,from:handler,croppedToInstancesExtent:false)
            let image=CIImage(cvPixelBuffer:buffer), context=CIContext()
            guard let color=CGColorSpace(name:CGColorSpace.sRGB), let png=context.pngRepresentation(of:image,format:.RGBA8,colorSpace:color) else { throw FormatError.invalid("could not encode the processed image") }
            return png
        }.value
    }
}
final class ImageProcessingController: NSWindowController {
    var task: Task<Void,Never>?
    init(editor: EditorWindowController,object: SlideObject,slideID: UUID,data: Data,processor: any ImageProcessor = ForegroundProcessor()) {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:360,height:120),styleMask:[.titled],backing:.buffered,defer:false); window.title="Remove Background"; window.isReleasedWhenClosed=false
        super.init(window:window); window.center()
        let progress=NSProgressIndicator(); progress.style = .spinning; progress.startAnimation(nil)
        let root=NSStackView(views:[progress,NSTextField(labelWithString:"Processing on this Mac…"),NSButton(title:"Cancel",target:self,action:#selector(cancel))]); root.frame=window.contentView!.bounds; root.autoresizingMask=[.width,.height]; root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16); window.contentView=root
        task=Task { @MainActor [weak self,weak editor] in
            do {
                let result=try await processor.process(data); try Task.checkCancellation()
                guard let editor=editor else { self?.close(); return }
                let asset=Asset(name:"Foreground.png",data:result)
                // The processing request belongs to the captured object, never the later selection.
                let current=editor.editableSlide(slideID)?.objects.first { $0.id == object.id }
                guard current?.image?.assetID == object.image?.assetID else { self?.close(); return }
                editor.presentation.undoManager?.beginUndoGrouping()
                editor.presentation.perform(.putAsset(asset),named:"Remove Background")
                editor.modifyObject(object.id,on:slideID,name:"Remove Background") { value in let original=value.image?.originalAssetID ?? value.image?.assetID; value.image?.originalAssetID=original; value.image?.assetID=asset.id }
                editor.presentation.undoManager?.endUndoGrouping(); self?.close()
            } catch is CancellationError { self?.close() }
            catch { self?.close(); editor?.presentation.presentError(error) }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func cancel() { task?.cancel(); close() }
}
extension EditorWindowController {
    @objc func removeImageBackground(_ sender: Any?) {
        canvas.finishText(); guard let object=currentSlide.objects.first(where: { canvas.selected.contains($0.id) }), let image=object.image, let data=presentation.deck.assets[image.assetID]?.data else { return }
        let panel=ImageProcessingController(editor:self,object:object,slideID:currentSlide.id,data:data); toolWindows.append(panel); panel.showWindow(nil)
    }
    @objc func restoreImageBackground(_ sender: Any?) { mutateSelection("Restore Original Image") { object in if let id=object.image?.originalAssetID { object.image?.assetID=id; object.image?.originalAssetID=nil } } }
}
