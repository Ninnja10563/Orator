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
    public static func validate(_ runs: [TextRun], text: String) throws {
        let count=text.utf16.count
        var end=0
        for run in runs {
            guard run.location >= end, run.length > 0, run.location <= count, run.length <= count-run.location else { throw FormatError.invalid("overlapping or out-of-bounds text run") }
            guard run.style.size.isFinite, (1...1000).contains(run.style.size), (run.style.tracking ?? 0).isFinite else { throw FormatError.invalid("invalid text run style") }
            end=run.location+run.length
        }
    }
}
