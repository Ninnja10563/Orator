import AppKit
import PresentationCore

/// Converts document runs at the renderer/editor boundary. No AppKit archive is stored in the file.
enum NativeText {
    static func attributed(_ object: SlideObject, theme: Theme) -> NSAttributedString {
        let text=NSMutableAttributedString(string:object.text,attributes:object.textStyle.attributes(theme:theme))
        for run in object.textRuns ?? [] where run.location >= 0 && run.length <= text.length-run.location {
            text.setAttributes(run.style.attributes(theme:theme),range:NSRange(location:run.location,length:run.length))
        }
        return text
    }
    static func style(_ attributes: [NSAttributedString.Key:Any], fallback: TextStyle = TextStyle()) -> TextStyle {
        var style=fallback
        if let font=attributes[.font] as? NSFont {
            style.fontName=font.familyName ?? font.fontName; style.size=font.pointSize
            let traits=font.fontDescriptor.symbolicTraits; style.bold=traits.contains(.bold); style.italic=traits.contains(.italic)
        }
        style.color=attributes[NSAttributedString.Key("OratorThemeForeground")] as? Bool == true ? nil : (attributes[.foregroundColor] as? NSColor).map(RGBA.init)
        style.highlight=(attributes[.backgroundColor] as? NSColor).map(RGBA.init)
        style.underline=(attributes[.underlineStyle] as? Int ?? 0) != 0
        style.strikethrough=(attributes[.strikethroughStyle] as? Int ?? 0) != 0
        style.tracking=(attributes[.kern] as? NSNumber)?.doubleValue
        style.hyperlink=(attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
        if let p=attributes[.paragraphStyle] as? NSParagraphStyle {
            switch p.alignment { case .center:style.alignment = .center; case .right:style.alignment = .right; case .justified:style.alignment = .justified; default:style.alignment = .left }
            style.lineSpacing=p.lineSpacing
            var options=ParagraphSettings(); options.before=p.paragraphSpacingBefore; options.after=p.paragraphSpacing
            options.indent=p.headIndent; options.firstLineIndent=p.firstLineHeadIndent
            if let list=p.textLists.last { options.list=list.markerFormat == .decimal ? .numbered : .bullet; options.level=max(0,p.textLists.count-1) }
            style.paragraph=options
        }
        if let original=attributes[paragraphKey] as? ParagraphSettings { style.paragraph=original }
        return style
    }
    static func store(_ value: NSAttributedString, in object: inout SlideObject) {
        object.text=value.string
        var runs: [TextRun]=[]
        value.enumerateAttributes(in:NSRange(location:0,length:value.length)) { attributes,range,_ in
            var runStyle=style(attributes,fallback:object.textStyle)
            // Keep theme-linked foreground when the editor has not deliberately overridden it.
            if attributes[NSAttributedString.Key("OratorThemeForeground")] as? Bool == true { runStyle.color=nil }
            runs.append(TextRun(location:range.location,length:range.length,style:runStyle))
        }
        object.textRuns=runs.isEmpty ? nil : runs
    }
    static func scaled(_ value: NSAttributedString, factor: Double) -> NSAttributedString {
        let copy=NSMutableAttributedString(attributedString:value)
        value.enumerateAttributes(in:NSRange(location:0,length:value.length)) { attributes,range,_ in
            if let font=attributes[.font] as? NSFont { copy.addAttribute(.font,value:(NSFont(descriptor:font.fontDescriptor,size:font.pointSize*factor) ?? font),range:range) }
            if let paragraph=attributes[.paragraphStyle] as? NSParagraphStyle, let scaled=paragraph.mutableCopy() as? NSMutableParagraphStyle {
                scaled.headIndent *= factor; scaled.firstLineHeadIndent *= factor; scaled.lineSpacing *= factor; scaled.paragraphSpacing *= factor; scaled.paragraphSpacingBefore *= factor
                copy.addAttribute(.paragraphStyle,value:scaled,range:range)
            }
            if let tracking=attributes[.kern] as? NSNumber { copy.addAttribute(.kern,value:tracking.doubleValue*factor,range:range) }
            if var settings=attributes[paragraphKey] as? ParagraphSettings { settings.indent *= factor; settings.firstLineIndent *= factor; settings.before *= factor; settings.after *= factor; copy.addAttribute(paragraphKey,value:settings,range:range) }
        }
        return copy
    }
}
