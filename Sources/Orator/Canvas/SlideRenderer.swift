import AppKit
import PresentationCore

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed:red,green:green,blue:blue,alpha:alpha) }
    init(_ color: NSColor) { let c=color.usingColorSpace(.sRGB) ?? .black; self.init(c.redComponent,c.greenComponent,c.blueComponent,c.alphaComponent) }
}
extension Rect { var nsRect: NSRect { NSRect(x:x,y:y,width:width,height:height) } }
extension TextStyle {
    var font: NSFont {
        var f=NSFont(name:fontName,size:size) ?? .systemFont(ofSize:size)
        var traits=f.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }; if italic { traits.insert(.italic) }
        f=NSFont(descriptor:f.fontDescriptor.withSymbolicTraits(traits),size:size) ?? f; return f
    }
    func attributes(theme: Theme, scale: Double = 1) -> [NSAttributedString.Key: Any] {
        let p=NSMutableParagraphStyle(); p.lineSpacing=lineSpacing
        switch alignment { case .left:p.alignment = .left; case .center:p.alignment = .center; case .right:p.alignment = .right; case .justified:p.alignment = .justified }
        if let options=paragraph {
            p.paragraphSpacingBefore=options.before; p.paragraphSpacing=options.after
            p.headIndent=options.indent; p.firstLineHeadIndent=options.firstLineIndent
            if options.list != .none { p.textLists=(0...max(0,min(8,options.level))).map { _ in NSTextList(markerFormat:options.list == .numbered ? .decimal : .disc,options:0) } }
        }
        var attributes: [NSAttributedString.Key:Any] = [.font: (NSFont(descriptor:font.fontDescriptor,size:size*scale) ?? font), .foregroundColor:(color ?? theme.foreground).nsColor, .paragraphStyle:p, .underlineStyle:underline ? NSUnderlineStyle.single.rawValue : 0, .strikethroughStyle:strikethrough == true ? NSUnderlineStyle.single.rawValue : 0, .kern:tracking ?? 0]
        if let highlight=highlight { attributes[.backgroundColor]=highlight.nsColor }
        if let link=hyperlink { attributes[.link]=link }
        if color == nil { attributes[NSAttributedString.Key("OratorThemeForeground")]=true }
        return attributes
    }
}
/// Shared drawing path for editing, thumbnails, PDF, and the audience window.
final class SlideRenderer {
    static let shared = SlideRenderer()
    private let images=NSCache<NSString,NSImage>()
    init() { images.countLimit=128; images.totalCostLimit=256*1024*1024 }
    func image(_ id: UUID, in deck: Presentation) -> NSImage? {
        let key=id.uuidString as NSString
        if let cached=images.object(forKey:key) { return cached }
        guard let data=deck.assets[id]?.data, let image=NSImage(data:data) else { return nil }
        images.setObject(image,forKey:key,cost:data.count); return image
    }
    func draw(slide: Slide, deck: Presentation, in rect: NSRect, excluding: UUID? = nil) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        rect.clip()
        let t=AffineTransform(translationByX:rect.minX,byY:rect.minY)
        var transform=t; transform.scale(x:rect.width/deck.width,y:rect.height/deck.height); (transform as NSAffineTransform).concat()
        (deck.resolved(slide).background ?? deck.theme.background).nsColor.setFill(); NSRect(x:0,y:0,width:deck.width,height:deck.height).fill()
        for object in deck.resolved(slide).objects where !object.hidden && object.id != excluding { draw(object:object,deck:deck) }
    }
    func draw(object o: SlideObject, deck: Presentation, inheritedOpacity: Double = 1) {
        guard !o.hidden else { return }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context=NSGraphicsContext.current?.cgContext else { return }
        context.setAlpha(o.opacity*inheritedOpacity)
        let r=o.frame.nsRect
        let transform=NSAffineTransform(); transform.translateX(by:r.midX,yBy:r.midY); transform.rotate(byDegrees:o.rotation); transform.translateX(by:-r.midX,yBy:-r.midY); transform.concat()
        if let shadow=o.style.shadow { let native=NSShadow(); native.shadowColor=shadow.color.nsColor; native.shadowBlurRadius=shadow.blur; native.shadowOffset=NSSize(width:shadow.x,height:-shadow.y); native.set() }
        if let clip=o.animationClip { clip.nsRect.clip() }
        switch o.kind {
        case .text: drawRichText(o,rect:r,theme:deck.theme)
        case .shape:
            let path=o.connector.map(connectorPath) ?? shape(o.shape,in:r,radius:o.style.cornerRadius)
            (o.style.fill ?? deck.theme.accent).nsColor.setFill()
            if o.connector == nil && ![ShapeKind.line,.arrow,.doubleArrow].contains(o.shape) {
                if let gradient=o.style.gradient { NSGradient(starting:(o.style.fill ?? deck.theme.accent).nsColor,ending:gradient.end.nsColor)?.draw(in:path,angle:gradient.angle) }
                else { path.fill() }
            }
            (o.style.strokeWidth > 0 ? o.style.stroke : (o.style.fill ?? deck.theme.accent)).nsColor.setStroke()
            path.lineWidth = o.style.strokeWidth > 0 ? o.style.strokeWidth : ([ShapeKind.line,.arrow,.doubleArrow].contains(o.shape) ? 3 : 0)
            switch o.style.borderPattern ?? .solid { case .solid:break; case .dashed:path.setLineDash([8,5],count:2,phase:0); case .dotted:path.setLineDash([1,4],count:2,phase:0); path.lineCapStyle = .round }
            if path.lineWidth > 0 { path.stroke() }
            context.setShadow(offset:.zero,blur:0,color:nil)
            if !o.text.isEmpty { drawRichText(o,rect:r.insetBy(dx:12,dy:10),theme:deck.theme) }
        case .image:
            guard let content=o.image, let image=image(content.assetID,in:deck) else { return }
            switch content.mask ?? .rectangle { case .rectangle:r.clip(); case .roundedRectangle:NSBezierPath(roundedRect:r,xRadius:o.style.cornerRadius,yRadius:o.style.cornerRadius).addClip(); case .ellipse:NSBezierPath(ovalIn:r).addClip() }
            let size=image.size, c=content.crop
            let source=NSRect(x:c.x*size.width,y:(1-c.maxY)*size.height,width:c.width*size.width,height:c.height*size.height)
            let ratio=content.fill ? max(r.width/source.width,r.height/source.height) : min(r.width/source.width,r.height/source.height)
            var dest=NSRect(x:r.midX-source.width*ratio/2,y:r.midY-source.height*ratio/2,width:source.width*ratio,height:source.height*ratio)
            if content.flippedHorizontally {
                let flip=NSAffineTransform(); flip.translateX(by:r.midX,yBy:0); flip.scaleX(by:-1,yBy:1); flip.translateX(by:-r.midX,yBy:0); flip.concat()
                dest.origin.x=r.minX+(r.maxX-dest.maxX)
            }
            if content.flippedVertically == true { let flip=NSAffineTransform(); flip.translateX(by:0,yBy:r.midY); flip.scaleX(by:1,yBy:-1); flip.translateX(by:0,yBy:-r.midY); flip.concat() }
            image.draw(in:dest,from:source,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high.rawValue])
        case .table:
            guard let table=o.table, !table.cells.isEmpty, let count=table.cells.first?.count, count > 0 else { return }
            for row in table.cells.indices { for col in table.cells[row].indices {
                let anchor=table.anchor(row:row,column:col); if anchor.0 != row || anchor.1 != col { continue }
                let cell=table.cellFrame(row:row,column:col,in:o.frame).nsRect
                let cellStyle=table.styles?["\(row):\(col)"] ?? CellStyle()
                (cellStyle.fill ?? (row == 0 ? deck.theme.accent : deck.theme.background)).nsColor.setFill(); cell.fill()
                (cellStyle.border?.nsColor ?? deck.theme.foreground.nsColor.withAlphaComponent(0.18)).setStroke(); let p=NSBezierPath(rect:cell); p.lineWidth=cellStyle.borderWidth; p.stroke()
                var style=cellStyle.textStyle ?? o.textStyle
                if cellStyle.textStyle == nil { style.size=min(style.size,24); style.bold=row == 0; if row == 0 { let c=deck.theme.accent; style.color=c.red*0.2126+c.green*0.7152+c.blue*0.0722 > 0.6 ? .ink : .white } }
                var textRect=cell.insetBy(dx:cellStyle.padding,dy:cellStyle.padding)
                if cellStyle.vertical != .top {
                    let height=(table.cells[row][col] as NSString).boundingRect(with:textRect.size,options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:style.attributes(theme:deck.theme)).height
                    textRect.origin.y += max(0,textRect.height-height)*(cellStyle.vertical == .middle ? 0.5 : 1)
                }
                drawText(table.cells[row][col],style:style,rect:textRect,theme:deck.theme)
            } }
        case .chart: if let chart=o.chart { drawChart(chart,object:o,deck:deck) }
        case .video, .audio:
            if let poster=o.media?.posterAssetID, let image=image(poster,in:deck) { image.draw(in:r,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            else { RGBA(0.12,0.14,0.18).nsColor.setFill(); r.fill() }
            NSColor.white.withAlphaComponent(0.85).setFill()
            let play=NSBezierPath(); play.move(to:NSPoint(x:r.midX-12,y:r.midY-18)); play.line(to:NSPoint(x:r.midX+18,y:r.midY)); play.line(to:NSPoint(x:r.midX-12,y:r.midY+18)); play.close(); play.fill()
        case .group: for child in o.children { draw(object:child,deck:deck,inheritedOpacity:inheritedOpacity*o.opacity) }
        }
    }
    func drawRichText(_ object: SlideObject, rect: NSRect, theme: Theme) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }; rect.clip()
        var value=NativeText.attributed(object,theme:theme)
        if object.textStyle.fit == .shrink {
            var factor=1.0
            while factor > 0.25 && value.boundingRect(with:NSSize(width:rect.width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height > rect.height {
                factor -= 0.025; value=NativeText.scaled(NativeText.attributed(object,theme:theme),factor:factor)
            }
        }
        value.draw(with:rect,options:[.usesLineFragmentOrigin,.usesFontLeading])
    }
    func drawText(_ text: String, style: TextStyle, rect: NSRect, theme: Theme) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        rect.clip()
        var scale=1.0
        if style.fit == .shrink {
            while scale > 0.25 {
                let measured=(text as NSString).boundingRect(with:NSSize(width:rect.width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:style.attributes(theme:theme,scale:scale))
                if measured.height <= rect.height { break }; scale -= 0.025
            }
        }
        (text as NSString).draw(with:rect,options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:style.attributes(theme:theme,scale:scale))
    }
    func shape(_ kind: ShapeKind, in r: NSRect, radius: Double) -> NSBezierPath {
        switch kind {
        case .rectangle:return NSBezierPath(rect:r)
        case .roundedRectangle:return NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius)
        case .ellipse,.circle:return NSBezierPath(ovalIn:r)
        default:
            let p=NSBezierPath(); var points: [NSPoint]
            switch kind {
            case .triangle: points=[NSPoint(x:r.midX,y:r.minY),NSPoint(x:r.maxX,y:r.maxY),NSPoint(x:r.minX,y:r.maxY)]
            case .diamond: points=[NSPoint(x:r.midX,y:r.minY),NSPoint(x:r.maxX,y:r.midY),NSPoint(x:r.midX,y:r.maxY),NSPoint(x:r.minX,y:r.midY)]
            case .polygon: points=(0..<6).map { i in let a=Double(i)*Double.pi/3; return NSPoint(x:r.midX+cos(a)*r.width/2,y:r.midY+sin(a)*r.height/2) }
            case .speechBubble: points=[NSPoint(x:r.minX,y:r.minY),NSPoint(x:r.maxX,y:r.minY),NSPoint(x:r.maxX,y:r.maxY-r.height*0.2),NSPoint(x:r.midX,y:r.maxY-r.height*0.2),NSPoint(x:r.minX+r.width*0.2,y:r.maxY),NSPoint(x:r.minX+r.width*0.2,y:r.maxY-r.height*0.2),NSPoint(x:r.minX,y:r.maxY-r.height*0.2)]
            case .star: points=(0..<10).map { i in let a=Double(i)*Double.pi/5-Double.pi/2; let f=i%2 == 0 ? 0.5 : 0.22; return NSPoint(x:r.midX+cos(a)*r.width*f,y:r.midY+sin(a)*r.height*f) }
            default: points=[NSPoint(x:r.minX,y:r.midY),NSPoint(x:r.maxX,y:r.midY)]
            }
            p.move(to:points[0]); for point in points.dropFirst() { p.line(to:point) }
            if kind == .arrow || kind == .doubleArrow { p.move(to:NSPoint(x:r.maxX-18,y:r.midY-12)); p.line(to:NSPoint(x:r.maxX,y:r.midY)); p.line(to:NSPoint(x:r.maxX-18,y:r.midY+12)) }
            else if kind != .line { p.close() }
            if kind == .doubleArrow { p.move(to:NSPoint(x:r.minX+18,y:r.midY-12)); p.line(to:NSPoint(x:r.minX,y:r.midY)); p.line(to:NSPoint(x:r.minX+18,y:r.midY+12)) }; return p
        }
    }
    func thumbnail(slide: Slide, deck: Presentation, size: NSSize) -> NSImage {
        let image=NSImage(size:size); image.lockFocusFlipped(true); draw(slide:slide,deck:deck,in:NSRect(origin:.zero,size:size)); image.unlockFocus(); return image
    }
}
