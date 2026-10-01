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
    func testMasterPropagationAndLocalBackgroundOverride() throws {
        var deck=Presentation(); var logo=SlideObject(kind:.shape,name:"Logo",frame:Rect(20,20,100,60)); logo.style.fill = .accent
        deck.masters?[0].objects=[logo]
        XCTAssertEqual(deck.resolved(deck.slides[0]).objects.first?.id,logo.id)
        deck.masters?[0].background = .ink; deck.slides[0].background = .white
        XCTAssertEqual(deck.resolved(deck.slides[0]).background,.white)
        deck.masters?[0].objects[0].frame.x=80
        XCTAssertEqual(deck.resolved(deck.slides[0]).objects.first?.frame.x,80)
        XCTAssertEqual(try PresentationFile.decode(PresentationFile.encode(deck)),deck)
    }
    func testAnimationClicksAndRelativeTiming() {
        let id=UUID(); var first=ObjectAnimation(objectID:id,effect:.fadeIn); first.duration=1
        var second=ObjectAnimation(objectID:id,effect:.spin); second.start = .afterPrevious; second.delay=0.25
        var third=ObjectAnimation(objectID:id,effect:.fadeOut); third.start = .withPrevious
        let schedule=AnimationEngine.schedule([first,second,third])
        XCTAssertEqual(schedule.map(\.click),[1,1,1]); XCTAssertEqual(schedule[1].start,1.25); XCTAssertEqual(schedule[2].start,1.25)
        var slide=Slide(); var object=SlideObject(kind:.shape,name:"Object",frame:Rect(10,20,100,100)); object.id=id; slide.objects=[object]; slide.animations=[first]
        XCTAssertEqual(AnimationEngine.frame(slide:slide,click:0,elapsed:10,width:1280,height:720).objects[0].opacity,0)
        XCTAssertEqual(AnimationEngine.frame(slide:slide,click:1,elapsed:0.5,width:1280,height:720).objects[0].opacity,0.5,accuracy:0.001)
    }
    func testContinuityKeepsUniqueObjectIDs() {
        let slide=Layout.title.makeSlide(); var copy=slide.duplicated(); copy.objects[0].frame.x += 200
        let halfway=AnimationEngine.interpolate(from:slide,to:copy,progress:0.5)
        XCTAssertNotEqual(copy.objects[0].id,slide.objects[0].id)
        XCTAssertEqual(halfway.objects[0].frame.x,slide.objects[0].frame.x+100)
    }
}

extension AdvancedTests {
    func testMediaArchiveAndClipboardPreserveOriginalBytes() throws {
        var deck=Presentation(); let asset=Asset(name:"sample.wav",data:Data("RIFFfixture".utf8))
        deck.assets[asset.id]=asset; var audio=SlideObject(kind:.audio,name:"Audio",frame:Rect(0,0,200,60)); audio.media=MediaContent(assetID:asset.id)
        audio.media?.trimStart=1; audio.media?.trimEnd=4; audio.media?.loop=true; deck.slides[0].objects.append(audio)
        XCTAssertEqual(try PresentationFile.decode(PresentationFile.encode(deck)),deck)
        XCTAssertEqual(ObjectClipboard(objects:[audio],assets:deck.assets).assets[asset.id]?.data,asset.data)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url)
        let imported=try PowerPoint.importDeck(from:url)
        let media=try XCTUnwrap(imported.deck.slides[0].objects.first { $0.kind == .audio }?.media)
        XCTAssertEqual(imported.deck.assets[media.assetID]?.data,asset.data)
    }
}
