import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension PowerPoint {
    static func commentAuthors(_ deck: Presentation) -> [String] {
        Array(Set(deck.slides.flatMap(\.comments).flatMap { [$0.author]+$0.messages.map(\.author).filter { !$0.isEmpty } })).sorted()
    }
    static func commentsXML(_ slide: Slide,authors: [String],counts: inout [Int:Int],ids: [UUID:Int]) -> String {
        let dates=ISO8601DateFormatter()
        func element(text: String,author: String,date: Date?,parent: (Int,Int)?,metadata: String,position: Point) -> (String,Int,Int) {
            let authorID=authors.firstIndex(of:author) ?? 0, index=(counts[authorID] ?? 0)+1; counts[authorID]=index
            let dateAttribute=date.map { " dt=\"\(dates.string(from:$0))\"" } ?? ""
            let thread="<p:ext uri=\"{C676402C-5697-4E1C-873F-D02D1690AC5C}\"><p15:threadingInfo xmlns:p15=\"http://schemas.microsoft.com/office/powerpoint/2012/main\" timeZoneBias=\"0\">\(parent.map { "<p15:parentCm authorId=\"\($0.0)\" idx=\"\($0.1)\"/>" } ?? "")</p15:threadingInfo></p:ext>"
            return ("<p:cm authorId=\"\(authorID)\" idx=\"\(index)\"\(dateAttribute)><p:pos x=\"\(emu(position.x))\" y=\"\(emu(position.y))\"/><p:text>\(xml(text))</p:text><p:extLst>\(thread)\(metadata)</p:extLst></p:cm>",authorID,index)
        }
        func find(_ id: UUID,in objects: [SlideObject]) -> SlideObject? { for object in objects { if object.id == id { return object }; if let child=find(id,in:object.children) { return child } }; return nil }
        var body=""
        for comment in slide.comments {
            let target=comment.objectID.flatMap { find($0,in:slide.objects) }, point=Point(target?.frame.x ?? 20,target?.frame.y ?? 20)
            let metadata="<p:ext uri=\"app.orator.comment.v1\"><o:comment xmlns:o=\"https://orator.app/schema/comments/1\" id=\"\(comment.id.uuidString)\" resolved=\"\(comment.resolved ? 1 : 0)\" spid=\"\(comment.objectID.flatMap { ids[$0] }.map(String.init) ?? "")\"/></p:ext>"
            let parent=element(text:comment.text,author:comment.author,date:comment.createdAt,parent:nil,metadata:metadata,position:point); body += parent.0
            for reply in comment.messages {
                body += element(text:reply.text,author:reply.author.isEmpty ? comment.author : reply.author,date:reply.createdAt,parent:(parent.1,parent.2),metadata:"",position:point).0
            }
        }
        return "<p:cmLst xmlns:p=\"\(p)\">\(body)</p:cmLst>"
    }
    static func commentAuthorsXML(_ authors: [String],counts: [Int:Int]) -> String {
        let body=authors.enumerated().map { index,author in
            let initials=author.split(separator:" ").prefix(3).compactMap(\.first).map(String.init).joined()
            return "<p:cmAuthor id=\"\(index)\" name=\"\(xml(author))\" initials=\"\(xml(initials))\" lastIdx=\"\(counts[index] ?? 0)\" clrIdx=\"\(index%8)\"/>"
        }.joined()
        return "<p:cmAuthorLst xmlns:p=\"\(p)\">\(body)</p:cmAuthorLst>"
    }
    static func readComments(_ root: XMLElement,authors: [String:String],ids: [String:UUID]) -> [Comment] {
        let dates=ISO8601DateFormatter(), nodes=root.descendants("cm")
        var comments: [Comment]=[], positions: [String:Int]=[:]
        for node in nodes where node.first("parentCm") == nil {
            var value=Comment(text:node.direct("text")?.stringValue ?? "",author:authors[node.attr("authorId")] ?? "Unknown author")
            value.createdAt=dates.date(from:node.attr("dt"))
            if let metadata=node.descendants("comment").first(where: { $0.uri == "https://orator.app/schema/comments/1" }) {
                value.id=UUID(uuidString:metadata.attr("id")) ?? value.id; value.resolved=metadata.attr("resolved") == "1"; value.objectID=ids[metadata.attr("spid")]
            }
            positions[node.attr("authorId")+":"+node.attr("idx")]=comments.count; comments.append(value)
        }
        for node in nodes {
            guard let parent=node.first("parentCm") else { continue }
            let author=authors[node.attr("authorId")] ?? "Unknown author", text=node.direct("text")?.stringValue ?? ""
            if let index=positions[parent.attr("authorId")+":"+parent.attr("idx")] {
                var replies=comments[index].messages; replies.append(CommentReply(text:text,author:author,createdAt:dates.date(from:node.attr("dt"))))
                comments[index].replyDetails=replies; comments[index].replies=replies.map(\.text)
                positions[node.attr("authorId")+":"+node.attr("idx")]=index
            } else { comments.append(Comment(text:text,author:author)) }
        }; return comments
    }
}
