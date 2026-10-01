import AppKit
import PresentationCore

final class CropView: NSView {
    let image: NSImage
    var crop: Rect { didSet { needsDisplay=true } }
    var ratio: Double? = nil
    private var start=NSPoint.zero, initial=Rect(0,0,1,1), corner: Int? = nil, moving=false
    init(image: NSImage,crop: Rect) { self.image=image; self.crop=crop; super.init(frame:.zero); setAccessibilityLabel("Image crop preview"); setAccessibilityHelp("Drag corners to resize the crop, or drag inside to move it. Use the aspect ratio menu for a fixed crop.") }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    var imageRect: NSRect { let scale=min((bounds.width-40)/image.size.width,(bounds.height-40)/image.size.height); let size=NSSize(width:image.size.width*scale,height:image.size.height*scale); return NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height) }
    var cropRect: NSRect { let r=imageRect; return NSRect(x:r.minX+crop.x*r.width,y:r.minY+crop.y*r.height,width:crop.width*r.width,height:crop.height*r.height) }
    func handles() -> [NSPoint] { let r=cropRect; return [NSPoint(x:r.minX,y:r.minY),NSPoint(x:r.maxX,y:r.minY),NSPoint(x:r.minX,y:r.maxY),NSPoint(x:r.maxX,y:r.maxY)] }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill(); image.draw(in:imageRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        let overlay=NSBezierPath(rect:imageRect); overlay.append(NSBezierPath(rect:cropRect)); overlay.windingRule = .evenOdd; NSColor.black.withAlphaComponent(0.5).setFill(); overlay.fill()
        NSColor.white.setStroke(); let border=NSBezierPath(rect:cropRect); border.lineWidth=1; border.stroke()
        for i in 1...2 { let path=NSBezierPath(); path.move(to:NSPoint(x:cropRect.minX+cropRect.width*Double(i)/3,y:cropRect.minY)); path.line(to:NSPoint(x:cropRect.minX+cropRect.width*Double(i)/3,y:cropRect.maxY)); path.move(to:NSPoint(x:cropRect.minX,y:cropRect.minY+cropRect.height*Double(i)/3)); path.line(to:NSPoint(x:cropRect.maxX,y:cropRect.minY+cropRect.height*Double(i)/3)); NSColor.white.withAlphaComponent(0.45).setStroke(); path.stroke() }
        for point in handles() { NSColor.white.setFill(); NSRect(x:point.x-4,y:point.y-4,width:8,height:8).fill() }
    }
    override func mouseDown(with event: NSEvent) { start=convert(event.locationInWindow,from:nil); initial=crop; corner=handles().firstIndex { hypot($0.x-start.x,$0.y-start.y) < 14 }; moving=corner == nil && cropRect.contains(start) }
    override func mouseDragged(with event: NSEvent) {
        let point=convert(event.locationInWindow,from:nil), r=imageRect
        let dx=Double((point.x-start.x)/r.width), dy=Double((point.y-start.y)/r.height)
        if moving { crop=Rect(min(1-initial.width,max(0,initial.x+dx)),min(1-initial.height,max(0,initial.y+dy)),initial.width,initial.height); return }
        guard let corner=corner else { return }
        let left=corner%2 == 0, top=corner < 2, fixedX=left ? initial.maxX : initial.x, fixedY=top ? initial.maxY : initial.y
        var width=max(0.01,min(left ? fixedX : 1-fixedX,initial.width+(left ? -dx : dx)))
        var height=max(0.01,min(top ? fixedY : 1-fixedY,initial.height+(top ? -dy : dy)))
        if let ratio=ratio {
            let normalized=ratio*Double(image.size.height/image.size.width)
            height=width/normalized; let limit=top ? fixedY : 1-fixedY
            if height > limit { height=limit; width=height*normalized }
        }
        crop=Rect(left ? fixedX-width : fixedX,top ? fixedY-height : fixedY,width,height)
    }
    func setAspect(_ aspect: Double?) {
        ratio=aspect; guard let aspect=aspect else { return }
        let normalized=aspect*Double(image.size.height/image.size.width), width=min(1,normalized), height=min(1,1/normalized)
        crop=Rect((1-width)/2,(1-height)/2,width,height)
    }
}
final class CropEditor: NSWindowController {
    let preview: CropView
    let apply: (Rect,ImageMask) -> Void
    let aspect=NSPopUpButton(), mask=NSPopUpButton()
    init(image: NSImage,content: ImageContent,apply: @escaping (Rect,ImageMask) -> Void) {
        self.apply=apply; preview=CropView(image:image,crop:content.crop)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:600),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false); window.title="Crop Image"; window.isReleasedWhenClosed=false
        super.init(window:window); window.center()
        let root=SurfaceStackView(); root.orientation = .vertical; root.spacing=12; root.edgeInsets=NSEdgeInsets(top:12,left:16,bottom:16,right:16); root.frame=window.contentView!.bounds; root.autoresizingMask=[.width,.height]; window.contentView=root
        root.addArrangedSubview(preview); preview.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true; preview.heightAnchor.constraint(greaterThanOrEqualToConstant:380).isActive=true
        aspect.addItems(withTitles:["Free","Square","4:3","16:9","3:4","9:16"]); aspect.target=self; aspect.action=#selector(changeAspect)
        mask.addItems(withTitles:ImageMask.allCases.map(\.rawValue)); mask.selectItem(withTitle:(content.mask ?? .rectangle).rawValue)
        let row=NSStackView(views:[NSTextField(labelWithString:"Aspect"),aspect,NSTextField(labelWithString:"Mask"),mask,NSButton(title:"Reset",target:self,action:#selector(reset)),NSButton(title:"Cancel",target:self,action:#selector(cancel)),NSButton(title:"Apply Crop",target:self,action:#selector(save))]); root.addArrangedSubview(row)
        let help=NSTextField(labelWithString:"Drag the crop corners or move the crop area. Original image quality is retained."); help.font = .systemFont(ofSize:11); help.textColor = .secondaryLabelColor; root.addArrangedSubview(help)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func changeAspect() { let ratios: [Double?]=[nil,1,4.0/3,16.0/9,3.0/4,9.0/16]; preview.setAspect(ratios[aspect.indexOfSelectedItem]) }
    @objc func reset() { aspect.selectItem(at:0); preview.ratio=nil; preview.crop=Rect(0,0,1,1) }
    @objc func cancel() { close() }
    @objc func save() { apply(preview.crop,ImageMask.allCases[mask.indexOfSelectedItem]); close() }
}
