import Foundation

public struct CommentReply: Codable, Equatable, Identifiable, Sendable {
    public var id=UUID()
    public var author: String
    public var text: String
    public var createdAt: Date?
    public init(text: String,author: String,createdAt: Date? = Date()) { self.text=text; self.author=author; self.createdAt=createdAt }
}
public extension Comment {
    var messages: [CommentReply] { replyDetails ?? replies.map { CommentReply(text:$0,author:"",createdAt:nil) } }
    mutating func addReply(_ text: String,author: String) {
        var details=messages; details.append(CommentReply(text:text,author:author)); replyDetails=details; replies=details.map(\.text)
    }
}
