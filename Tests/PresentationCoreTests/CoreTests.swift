import XCTest
@testable import PresentationCore

final class CoreTests: XCTestCase {
    func testNativeRoundTripPreservesNestedObjectsAndAssets() throws {
        var deck=Presentation(); let asset=Asset(name:"Original.png",data:Data([1,2,3,4])); deck.assets[asset.id]=asset
        var image=SlideObject(kind:.image,name:"Photo",frame:Rect(10,20,320,180)); image.image=ImageContent(assetID:asset.id); image.image?.crop=Rect(0.1,0.2,0.7,0.6)
        var group=SlideObject(kind:.group,name:"Group",frame:image.frame); group.children=[image]; deck.slides[0].objects.append(group); deck.slides[0].notes="Notes\n日本語"
        XCTAssertEqual(try PresentationFile.decode(PresentationFile.encode(deck)),deck)
    }
    func testFutureVersionFailsBeforeDecodingUnknownSchema() {
        XCTAssertThrowsError(try PresentationFile.decode(Data("{\"formatVersion\":999}".utf8))) { error in guard case FormatError.unsupportedVersion(999)=error else { return XCTFail("Wrong error: \(error)") } }
    }
    func testMissingAssetAndDuplicateIDsAreRejected() throws {
        var deck=Presentation(); deck.slides[0].objects.append(deck.slides[0].objects[0]); XCTAssertThrowsError(try PresentationFile.encode(deck))
        deck=Presentation(); var o=SlideObject(kind:.image,name:"Lost",frame:Rect(0,0,100,100)); o.image=ImageContent(assetID:UUID()); deck.slides[0].objects.append(o); XCTAssertThrowsError(try PresentationFile.encode(deck))
    }
    func testCommandsUndoRedoAndAtomicFailure() throws {
        var deck=Presentation(); let initial=deck, added=Layout.twoColumns.makeSlide()
        let undo=try Edit.insertSlide(added,1).apply(to:&deck); XCTAssertEqual(deck.slides.count,2)
        let redo=try undo.apply(to:&deck); XCTAssertEqual(deck,initial)
        _=try redo.apply(to:&deck); XCTAssertEqual(deck.slides[1],added)
        let before=deck
        XCTAssertThrowsError(try Edit.batch([.setTheme(.midnight),.removeSlide(UUID())]).apply(to:&deck)); XCTAssertEqual(deck,before)
    }
    func testCannotDeleteLastSlideOrCorruptOrdering() throws {
        var deck=Presentation(); XCTAssertThrowsError(try Edit.removeSlide(deck.slides[0].id).apply(to:&deck)); XCTAssertThrowsError(try Edit.orderSlides([]).apply(to:&deck))
    }
    func testGroupResizeAndDuplication() {
        var child=SlideObject(kind:.shape,name:"Child",frame:Rect(10,20,100,50)); child.rotation=12
        var group=SlideObject(kind:.group,name:"Group",frame:Rect(10,20,200,100)); group.children=[child]
        group.transform(to:Rect(100,200,400,200)); XCTAssertEqual(group.children[0].frame,Rect(100,200,200,100))
        let copy=group.duplicated(); XCTAssertNotEqual(copy.id,group.id); XCTAssertNotEqual(copy.children[0].id,child.id); XCTAssertEqual(copy.children[0].rotation,12)
    }
    func testScreenIndependentSnapAndRotationHitTest() {
        let snapped=Geometry.snap(Rect(593,200,100,100),others:[],guides:[],width:1280,height:720,tolerance:5)
        XCTAssertEqual(snapped.0.x,590); XCTAssertTrue(snapped.1.contains(Guide(vertical:true,position:640)))
        var object=SlideObject(kind:.shape,name:"Rotated",frame:Rect(100,100,200,20)); object.rotation=90
        XCTAssertTrue(Geometry.hit(Point(200,40),object:object)); XCTAssertFalse(Geometry.hit(Point(110,110),object:object)); object.locked=true; XCTAssertFalse(Geometry.hit(Point(200,110),object:object))
    }
    func testDistributionPreservesOuterEdges() {
        let objects=[Rect(0,0,50,50),Rect(80,40,100,50),Rect(400,100,50,50)].map { SlideObject(kind:.shape,name:"Box",frame:$0) }
        let aligned=Geometry.aligned(objects,command:.horizontal)
        XCTAssertEqual(aligned[0].frame.x,0); XCTAssertEqual(aligned[2].frame.maxX,450); XCTAssertEqual(aligned[1].frame.x-aligned[0].frame.maxX,aligned[2].frame.x-aligned[1].frame.maxX)
    }
    func testThemeChangePreservesExplicitOverrides() throws {
        var deck=Presentation(); deck.slides[0].objects[0].textStyle.color=RGBA(1,0,0)
        _=try Edit.setTheme(.midnight).apply(to:&deck); XCTAssertEqual(deck.slides[0].objects[0].textStyle.color,RGBA(1,0,0)); XCTAssertNil(deck.slides[0].objects[1].textStyle.color)
    }
    func testPPTXRoundTripTextShapesTablesNotesAndOrder() throws {
        var deck=Presentation(); deck.slides[0].objects[0].text="A & B < C — 日本語"; deck.slides[0].notes="Speaker notes & detail"
        var table=SlideObject(kind:.table,name:"Data",frame:Rect(10,20,400,200)); table.table=TableContent(); table.table?.cells=[["A","B"],["1","2"]]; deck.slides[0].objects.append(table)
        deck.slides.append(Layout.twoColumns.makeSlide()); deck.slides[1].skipped=true
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url)
        XCTAssertEqual(Array(try Data(contentsOf:url).prefix(2)),[0x50,0x4b])
        let result=try PowerPoint.importDeck(from:url)
        XCTAssertEqual(result.deck.slides.count,2); XCTAssertEqual(result.deck.width,deck.width); XCTAssertEqual(result.deck.slides[0].objects[0].text,deck.slides[0].objects[0].text)
        XCTAssertEqual(result.deck.slides[0].notes,deck.slides[0].notes); XCTAssertEqual(result.deck.slides[0].objects.last?.table?.cells,table.table?.cells); XCTAssertTrue(result.deck.slides[1].skipped)
    }
    func testIndependentPowerPointFixture() throws {
        let url=Bundle.module.url(forResource:"independent",withExtension:"pptx",subdirectory:"Fixtures")!
        let result=try PowerPoint.importDeck(from:url)
        XCTAssertEqual(result.deck.slides.count,2)
        XCTAssertEqual(result.deck.slides[0].objects[0].text,"Independent fixture — A & B < C")
        XCTAssertEqual(result.deck.slides[0].objects[0].textStyle.size,36)
        XCTAssertEqual(result.deck.slides[0].objects.first { $0.kind == .table }?.table?.cells,[["Region","Revenue"],["North","42"]])
        XCTAssertEqual(result.deck.assets.count,1)
        XCTAssertEqual(result.deck.slides[0].notes,"Independent speaker notes")
    }
    func testLargeDeckSerialization() throws {
        var deck=Presentation(); deck.slides=(0..<500).map { _ in Layout.twoColumns.makeSlide() }
        let data=try PresentationFile.encode(deck); XCTAssertEqual(try PresentationFile.decode(data).slides.count,500)
    }
}
