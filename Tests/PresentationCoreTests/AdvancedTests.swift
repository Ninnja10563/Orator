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

extension AdvancedTests {
    func testTableMergesPreserveCoveredDataAndResizeProportionally() throws {
        var table=TableContent(rows:3,columns:3); table.cells[0]=["A","B","C"]
        try table.merge(CellMerge(row:0,column:0,rows:1,columns:2))
        XCTAssertEqual(table.cellFrame(row:0,column:0,in:Rect(0,0,300,90)).width,200)
        XCTAssertEqual(table.anchor(row:0,column:1).1,0)
        XCTAssertThrowsError(try table.merge(CellMerge(row:0,column:1,rows:1,columns:2)))
        table.split(row:0,column:1); XCTAssertEqual(table.cells[0][1],"B")
        table.insertColumn(at:0); XCTAssertEqual(table.cells[0][2],"B")
        table.removeColumn(at:0); XCTAssertEqual(table.cells[0],["A","B","C"])
        table.insertRow(at:1); table.removeRow(at:1); XCTAssertEqual(table.cells.count,3)
    }
}

extension AdvancedTests {
    func testGroupedAnimationsSurviveDuplicationAndDeletionValidation() throws {
        var deck=Presentation(); let child=deck.slides[0].objects[0]
        var group=SlideObject(kind:.group,name:"Group",frame:child.frame); group.children=[child]
        deck.slides[0].objects=[group]; deck.slides[0].animations=[ObjectAnimation(objectID:child.id,effect:.fadeIn)]
        try PresentationFile.validate(deck)
        let copy=deck.slides[0].duplicated(); XCTAssertEqual(copy.animations?.first?.objectID,copy.objects[0].children[0].id)
        let hidden=AnimationEngine.frame(slide:deck.slides[0],click:0,elapsed:0,width:1280,height:720)
        XCTAssertEqual(hidden.objects[0].children[0].opacity,0)
        let shown=AnimationEngine.frame(slide:deck.slides[0],click:1,elapsed:1,width:1280,height:720)
        XCTAssertEqual(shown.objects[0].children[0].opacity,1)
    }
    func testRejectsInvalidParagraphAndCellStyles() throws {
        var deck=Presentation(); var paragraph=ParagraphSettings(); paragraph.level = -1; deck.slides[0].objects[0].textStyle.paragraph=paragraph
        XCTAssertThrowsError(try PresentationFile.validate(deck))
        deck.slides[0].objects[0].textStyle.paragraph=nil
        var table=SlideObject(kind:.table,name:"Table",frame:Rect(0,0,400,200)); table.table=TableContent()
        var style=CellStyle(); style.padding = -.infinity; table.table?.styles=["0:0":style]; deck.slides[0].objects.append(table)
        XCTAssertThrowsError(try PresentationFile.validate(deck))
    }
    func testRecoveryMigratesVersionOne() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }; try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        var deck=Presentation(); deck.formatVersion=1
        let record=RecoveryRecord(sessionID:UUID(),originalPath:nil,presentation:deck)
        try JSONEncoder().encode(record).write(to:url.appendingPathComponent(record.sessionID.uuidString+".recovery"))
        let recovered=try RecoveryStore(directory:url).records(); XCTAssertEqual(recovered.count,1); XCTAssertEqual(recovered.first?.presentation.formatVersion,2)
    }
}

extension AdvancedTests {
    func testPowerPointRichRunsLinksAndTableGeometry() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        var deck=Presentation(); var style=TextStyle(); style.bold=true; style.strikethrough=true; style.tracking=1.25; style.hyperlink="https://example.com/report?a=1&b=2"; style.highlight=RGBA(1,1,0)
        deck.slides[0].objects[0].text="Bold 👋\nSecond line"; deck.slides[0].objects[0].textRuns=[TextRun(location:0,length:7,style:style)]
        var object=SlideObject(kind:.table,name:"Merged",frame:Rect(40,200,600,300)); var table=TableContent(rows:3,columns:3)
        table.cells[0][0]="Merged header"; table.columnWidths=[1,2,3]; table.rowHeights=[2,1,1]; try table.merge(CellMerge(row:0,column:0,rows:1,columns:2)); object.table=table; deck.slides[0].objects.append(object)
        _=try PowerPoint.export(deck,to:url); let result=try PowerPoint.importDeck(from:url).deck
        let text=result.slides[0].objects[0]; XCTAssertEqual(text.text,deck.slides[0].objects[0].text); XCTAssertEqual(text.textRuns?.first?.style.hyperlink,style.hyperlink); XCTAssertEqual(text.textRuns?.first?.style.strikethrough,true); XCTAssertEqual(text.textRuns?.first?.style.tracking,1.25)
        let imported=try XCTUnwrap(result.slides[0].objects.last?.table); XCTAssertEqual(imported.merges,table.merges)
        let frame=imported.cellFrame(row:0,column:0,in:object.frame); XCTAssertEqual(frame.width,300,accuracy:0.01); XCTAssertEqual(frame.height,150,accuracy:0.01)
    }
}

extension AdvancedTests {
    func testAllChartTypesRoundTripWithEmbeddedWorkbook() throws {
        var deck=Presentation(); deck.slides=[]
        for kind in ChartKind.allCases {
            var slide=Slide(); var object=SlideObject(kind:.chart,name:"Chart",frame:Rect(100,100,800,480)); var chart=ChartContent(); chart.kind=kind; chart.labels=["1","2","3","4"]
            chart.setSeries([ChartSeries(name:"Revenue",values:[2,4,-1,8]),ChartSeries(name:"Costs",values:[1,2,3,4])]); object.chart=chart; slide.objects=[object]; deck.slides.append(slide)
        }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url); let imported=try PowerPoint.importDeck(from:url).deck
        for (original,copy) in zip(deck.slides,imported.slides) { let a=try XCTUnwrap(original.objects.first?.chart), b=try XCTUnwrap(copy.objects.first?.chart); XCTAssertEqual(a.kind,b.kind); if a.kind == .scatter { XCTAssertEqual(a.labels.compactMap(Double.init),b.labels.compactMap(Double.init)) } else { XCTAssertEqual(a.labels,b.labels) }; XCTAssertEqual(a.dataSeries.first,b.dataSeries.first); if a.kind != .pie { XCTAssertEqual(a.dataSeries,b.dataSeries) } }
        let listing=try PowerPoint.run("/usr/bin/unzip",["-Z1",url.path]); XCTAssertTrue(String(decoding:listing,as:UTF8.self).contains("ppt/embeddings/chart1_2.xlsx"))
    }
}
