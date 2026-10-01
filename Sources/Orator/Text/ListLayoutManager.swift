import AppKit
import PresentationCore

/// TextKit 1 does not synthesize visible list markers from paragraph metadata.
/// Drawing them separately keeps UTF-16 document ranges independent of numbering.
final class ListLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange:glyphsToShow,at:origin)
        guard let storage=textStorage, storage.length > 0 else { return }
        let string=storage.string as NSString
        var index=0, counters=Array(repeating:0,count:9), previousLevel = -1
        while index < string.length {
            let paragraph=string.paragraphRange(for:NSRange(location:index,length:0))
            let attributes=storage.attributes(at:index,effectiveRange:nil)
            let style=NativeText.style(attributes)
            if let options=style.paragraph, options.list != .none {
                let level=min(8,max(0,options.level))
                if previousLevel < 0 { counters=Array(repeating:0,count:9) }
                if level < 8 { for deeper in (level+1)...8 { counters[deeper]=0 } }
                counters[level] += 1; previousLevel=level
                let glyph=glyphIndexForCharacter(at:index)
                if NSLocationInRange(glyph,glyphsToShow), glyph < numberOfGlyphs {
                    let line=lineFragmentRect(forGlyphAt:glyph,effectiveRange:nil)
                    let position=location(forGlyphAt:glyph)
                    let marker=options.list == .numbered ? "\(counters[level])." : "•"
                    var markerAttributes=attributes; markerAttributes.removeValue(forKey:.paragraphStyle)
                    markerAttributes.removeValue(forKey:.backgroundColor); markerAttributes.removeValue(forKey:.link)
                    let size=(marker as NSString).size(withAttributes:markerAttributes)
                    (marker as NSString).draw(at:NSPoint(x:origin.x+line.minX+position.x-size.width-max(6,style.size*0.22),y:origin.y+line.minY),withAttributes:markerAttributes)
                }
            } else { previousLevel = -1 }
            index=NSMaxRange(paragraph)
        }
    }
}

extension NativeText {
    static let paragraphKey=NSAttributedString.Key("OratorParagraph")
    static func hasLists(_ value: NSAttributedString) -> Bool {
        var found=false
        value.enumerateAttribute(.paragraphStyle,in:NSRange(location:0,length:value.length)) { value,_,stop in
            if let p=value as? NSParagraphStyle, !p.textLists.isEmpty { found=true; stop.pointee=true }
        }; return found
    }
    static func layout(_ value: NSAttributedString,width: CGFloat) -> (NSTextStorage,ListLayoutManager,NSTextContainer) {
        let storage=NSTextStorage(attributedString:value), manager=ListLayoutManager()
        let container=NSTextContainer(containerSize:NSSize(width:width,height:100000)); container.lineFragmentPadding=0
        storage.addLayoutManager(manager); manager.addTextContainer(container); manager.ensureLayout(for:container)
        return (storage,manager,container)
    }
    static func measuredSize(_ value: NSAttributedString,width: CGFloat) -> NSSize {
        guard hasLists(value) else { return value.boundingRect(with:NSSize(width:width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading]).size }
        let (storage,manager,container)=layout(value,width:width)
        return withExtendedLifetime(storage) { manager.usedRect(for:container).size }
    }
    static func draw(_ value: NSAttributedString,in rect: NSRect) {
        guard hasLists(value) else { value.draw(with:rect,options:[.usesLineFragmentOrigin,.usesFontLeading]); return }
        let (storage,manager,container)=layout(value,width:rect.width)
        withExtendedLifetime(storage) {
            let range=manager.glyphRange(for:container)
            manager.drawBackground(forGlyphRange:range,at:rect.origin); manager.drawGlyphs(forGlyphRange:range,at:rect.origin)
        }
    }
}
