import XCTest
@testable import PresentationCore

final class AdvancedTests: XCTestCase {
    func testV1MigrationAndRichTextRoundTrip() throws {
        var deck=Presentation()
        let old=try PresentationFile.encode(deck)
        let legacy=String(data:old,encoding:.utf8)!.replacingOccurrences(of:"\"formatVersion\":2",with:"\"formatVersion\":1")
        XCTAssertEqual(try PresentationFile.decode(Data(legacy.utf8)).formatVersion,2)
        var style=TextStyle(); style.bold=true; style.highlight=RGBA(1,1,0); style.tracking=2
        deck.slides[0].objects[0].text="Rich 👋 text"
        deck.slides[0].objects[0].textRuns=[TextRun(location:0,length:4,style:style)]
        XCTAssertEqual(try PresentationFile.decode(PresentationFile.encode(deck)),deck)
        deck.slides[0].objects[0].textRuns=[TextRun(location:999,length:1,style:style)]
        XCTAssertThrowsError(try PresentationFile.encode(deck))
    }
}
