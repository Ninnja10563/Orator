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
        if bold { f=NSFontManager.shared.convert(f,toHaveTrait:.boldFontMask) }
        if italic { f=NSFontManager.shared.convert(f,toHaveTrait:.italicFontMask) }; return f
    }
    func attributes(theme: Theme, scale: Double = 1) -> [NSAttributedString.Key: Any] {
        let p=NSMutableParagraphStyle(); p.lineSpacing=lineSpacing
        switch alignment { case .left:p.alignment = .left; case .center:p.alignment = .center; case .right:p.alignment = .right; case .justified:p.alignment = .justified }
        if let options=paragraph {
            p.paragraphSpacingBefore=options.before; p.paragraphSpacing=options.after
            p.headIndent=options.indent; p.firstLineHeadIndent=options.firstLineIndent
            if options.list != .none { p.textLists=(0...min(8,options.level)).map { _ in NSTextList(markerFormat:options.list == .numbered ? .decimal : .disc,options:0) } }
        }
        var attributes: [NSAttributedString.Key:Any] = [.font: NSFontManager.shared.convert(font,toSize:size*scale), .foregroundColor:(color ?? theme.foreground).nsColor, .paragraphStyle:p, .underlineStyle:underline ? NSUnderlineStyle.single.rawValue : 0, .strikethroughStyle:strikethrough == true ? NSUnderlineStyle.single.rawValue : 0, .kern:tracking ?? 0]
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
        if let clip=o.animationClip { clip.nsRect.clip() }
        switch o.kind {
        case .text: drawRichText(o,rect:r,theme:deck.theme)
        case .shape:
            let path=shape(o.shape,in:r,radius:o.style.cornerRadius)
            (o.style.fill ?? deck.theme.accent).nsColor.setFill()
            if o.shape != .line && o.shape != .arrow { path.fill() }
            (o.style.strokeWidth > 0 ? o.style.stroke : (o.style.fill ?? deck.theme.accent)).nsColor.setStroke()
            path.lineWidth = o.style.strokeWidth > 0 ? o.style.strokeWidth : ((o.shape == .line || o.shape == .arrow) ? 3 : 0)
            if path.lineWidth > 0 { path.stroke() }
            if !o.text.isEmpty { drawRichText(o,rect:r.insetBy(dx:12,dy:10),theme:deck.theme) }
        case .image:
            guard let content=o.image, let image=image(content.assetID,in:deck) else { return }
            r.clip()
            let size=image.size, c=content.crop
            let source=NSRect(x:c.x*size.width,y:(1-c.maxY)*size.height,width:c.width*size.width,height:c.height*size.height)
            let ratio=content.fill ? max(r.width/source.width,r.height/source.height) : min(r.width/source.width,r.height/source.height)
            var dest=NSRect(x:r.midX-source.width*ratio/2,y:r.midY-source.height*ratio/2,width:source.width*ratio,height:source.height*ratio)
            if content.flippedHorizontally {
                let flip=NSAffineTransform(); flip.translateX(by:r.midX,yBy:0); flip.scaleX(by:-1,yBy:1); flip.translateX(by:-r.midX,yBy:0); flip.concat()
                dest.origin.x=r.minX+(r.maxX-dest.maxX)
            }
            image.draw(in:dest,from:source,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high.rawValue])
        case .table:
            guard let table=o.table, !table.cells.isEmpty, let count=table.cells.first?.count, count > 0 else { return }
            let h=r.height/Double(table.cells.count), w=r.width/Double(count)
            for row in table.cells.indices { for col in table.cells[row].indices {
                let cell=NSRect(x:r.minX+Double(col)*w,y:r.minY+Double(row)*h,width:w,height:h)
                (row == 0 ? deck.theme.accent : deck.theme.background).nsColor.setFill(); cell.fill()
                deck.theme.foreground.nsColor.withAlphaComponent(0.18).setStroke(); let p=NSBezierPath(rect:cell); p.lineWidth=1; p.stroke()
                var style=o.textStyle; style.size=min(style.size,24); style.bold=row == 0; if row == 0 { let c=deck.theme.accent; style.color = c.red*0.2126+c.green*0.7152+c.blue*0.0722 > 0.6 ? .ink : .white }
                drawText(table.cells[row][col],style:style,rect:cell.insetBy(dx:12,dy:8),theme:deck.theme)
            } }
        case .chart: if let chart=o.chart { drawChart(chart,object:o,deck:deck) }
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
        case .ellipse:return NSBezierPath(ovalIn:r)
        default:
            let p=NSBezierPath(); var points: [NSPoint]
            switch kind {
            case .triangle: points=[NSPoint(x:r.midX,y:r.minY),NSPoint(x:r.maxX,y:r.maxY),NSPoint(x:r.minX,y:r.maxY)]
            case .diamond: points=[NSPoint(x:r.midX,y:r.minY),NSPoint(x:r.maxX,y:r.midY),NSPoint(x:r.midX,y:r.maxY),NSPoint(x:r.minX,y:r.midY)]
            case .star: points=(0..<10).map { i in let a=Double(i)*Double.pi/5-Double.pi/2; let f=i%2 == 0 ? 0.5 : 0.22; return NSPoint(x:r.midX+cos(a)*r.width*f,y:r.midY+sin(a)*r.height*f) }
            default: points=[NSPoint(x:r.minX,y:r.midY),NSPoint(x:r.maxX,y:r.midY)]
            }
            p.move(to:points[0]); for point in points.dropFirst() { p.line(to:point) }
            if kind == .arrow { p.move(to:NSPoint(x:r.maxX-18,y:r.midY-12)); p.line(to:NSPoint(x:r.maxX,y:r.midY)); p.line(to:NSPoint(x:r.maxX-18,y:r.midY+12)) }
            else if kind != .line { p.close() }; return p
        }
    }
    private func drawChart(_ chart: ChartContent, object: SlideObject, deck: Presentation) {
        let r=object.frame.nsRect; var title=object.textStyle; title.size=24; title.bold=true
        NSGraphicsContext.saveGraphicsState(); drawText(chart.title,style:title,rect:NSRect(x:r.minX,y:r.minY,width:r.width,height:38),theme:deck.theme); NSGraphicsContext.restoreGraphicsState()
        guard !chart.values.isEmpty else { return }
        let plot=r.insetBy(dx:48,dy:52), maximum=max(1,chart.values.max() ?? 1), minimum=min(0,chart.values.min() ?? 0), span=maximum-minimum
        let count=chart.values.count, slot=plot.width/Double(count)
        func y(_ value: Double) -> Double { plot.maxY-(value-minimum)/span*plot.height }
        let color=deck.theme.accent.nsColor; color.setFill(); color.setStroke()
        if chart.kind == .pie {
            let total=chart.values.reduce(0) { $0+max(0,$1) }; guard total > 0 else { return }
            var angle=0.0
            for (i,value) in chart.values.enumerated() {
                let end=angle+max(0,value)/total*360, p=NSBezierPath(); p.move(to:NSPoint(x:plot.midX,y:plot.midY))
                p.appendArc(withCenter:NSPoint(x:plot.midX,y:plot.midY),radius:min(plot.width,plot.height)/2,startAngle:angle,endAngle:end)
                p.close(); color.blended(withFraction:Double(i)/Double(count)*0.7,of:.white)?.setFill(); p.fill(); angle=end
            }; return
        }
        deck.theme.foreground.nsColor.withAlphaComponent(0.18).setStroke()
        for n in 0...4 { let p=NSBezierPath(); let y=plot.minY+Double(n)*plot.height/4; p.move(to:NSPoint(x:plot.minX,y:y)); p.line(to:NSPoint(x:plot.maxX,y:y)); p.stroke() }
        let line=NSBezierPath()
        for (i,value) in chart.values.enumerated() {
            let x=plot.minX+(Double(i)+0.5)*slot, point=NSPoint(x:x,y:y(value)); color.setFill()
            switch chart.kind {
            case .column: NSRect(x:x-slot*0.3,y:min(y(value),y(0)),width:slot*0.6,height:max(1,abs(y(value)-y(0)))).fill()
            case .bar:
                let height=plot.height/Double(count), zero=plot.minX+(0-minimum)/span*plot.width, end=plot.minX+(value-minimum)/span*plot.width
                NSRect(x:min(zero,end),y:plot.minY+Double(i)*height+height*0.15,width:max(1,abs(end-zero)),height:height*0.7).fill()
            case .line, .area: if i == 0 { line.move(to:point) } else { line.line(to:point) }
            case .scatter: NSBezierPath(ovalIn:NSRect(x:x-5,y:point.y-5,width:10,height:10)).fill()
            case .pie: break
            }
            var label=object.textStyle; label.size=14; label.alignment = .center
            NSGraphicsContext.saveGraphicsState(); drawText(chart.labels[i],style:label,rect:NSRect(x:x-slot/2,y:plot.maxY+10,width:slot,height:24),theme:deck.theme); NSGraphicsContext.restoreGraphicsState()
        }
        color.setStroke(); line.lineWidth=3; line.stroke()
        if chart.kind == .area { line.line(to:NSPoint(x:plot.maxX-slot/2,y:y(0))); line.line(to:NSPoint(x:plot.minX+slot/2,y:y(0))); line.close(); color.withAlphaComponent(0.2).setFill(); line.fill() }
    }
    func thumbnail(slide: Slide, deck: Presentation, size: NSSize) -> NSImage {
        let image=NSImage(size:size); image.lockFocusFlipped(true); draw(slide:slide,deck:deck,in:NSRect(origin:.zero,size:size)); image.unlockFocus(); return image
    }
}
