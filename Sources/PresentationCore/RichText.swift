import Foundation

public enum ListKind: String, Codable, CaseIterable, Sendable { case none, bullet, numbered }
public struct ParagraphSettings: Codable, Equatable, Sendable {
    public var before: Double = 0
    public var after: Double = 0
    public var indent: Double = 0
    public var firstLineIndent: Double = 0
    public var list: ListKind = .none
    public var level: Int = 0
    public init() {}
}
/// Ranges use UTF-16 offsets, matching the native text system and OOXML text runs.
public struct TextRun: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var style: TextStyle
    public init(location: Int, length: Int, style: TextStyle) { self.location=location; self.length=length; self.style=style }
}
public enum RichText {
    public static func validateStyle(_ style: TextStyle) throws {
        guard style.size.isFinite, (1...1000).contains(style.size), style.lineSpacing.isFinite, (0...10000).contains(style.lineSpacing), (style.tracking ?? 0).isFinite, abs(style.tracking ?? 0) <= 10000 else { throw FormatError.invalid("invalid text style") }
        for color in [style.color,style.highlight].compactMap({ $0 }) {
            guard [color.red,color.green,color.blue,color.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw FormatError.invalid("invalid text color") }
        }
        if let p=style.paragraph {
            guard (0...8).contains(p.level), [p.before,p.after,p.indent,p.firstLineIndent].allSatisfy({ $0.isFinite && abs($0) <= 10000 }) else { throw FormatError.invalid("invalid paragraph settings") }
        }
    }
    public static func validate(_ runs: [TextRun], text: String) throws {
        let count=text.utf16.count
        var end=0
        for run in runs {
            guard run.location >= end, run.length > 0, run.location <= count, run.length <= count-run.location else { throw FormatError.invalid("overlapping or out-of-bounds text run") }
            try validateStyle(run.style)
            end=run.location+run.length
        }
    }
}
