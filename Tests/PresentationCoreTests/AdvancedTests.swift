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
        audio.media?.sourceDuration=6; audio.media?.trimStart=1; audio.media?.trimEnd=4; audio.media?.loop=true; audio.media?.autoplay=true; audio.media?.volume=0.6; audio.media?.fadeIn=0.2; deck.slides[0].objects.append(audio)
        XCTAssertEqual(try PresentationFile.decode(PresentationFile.encode(deck)),deck)
        XCTAssertEqual(ObjectClipboard(objects:[audio],assets:deck.assets).assets[asset.id]?.data,asset.data)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url)
        let imported=try PowerPoint.importDeck(from:url)
        let media=try XCTUnwrap(imported.deck.slides[0].objects.first { $0.kind == .audio }?.media)
        XCTAssertEqual(imported.deck.assets[media.assetID]?.data,asset.data)
        XCTAssertEqual(media.trimEndOffset,2); XCTAssertEqual(media.trimStart,1); XCTAssertEqual(media.fadeIn,0.2); XCTAssertEqual(media.volume,0.6); XCTAssertTrue(media.loop); XCTAssertTrue(media.autoplay)
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
        let text=result.slides[0].objects[0]; XCTAssertEqual(text.text,deck.slides[0].objects[0].text); XCTAssertEqual(text.textRuns?.first?.style.hyperlink,style.hyperlink); XCTAssertEqual(text.textRuns?.first?.style.strikethrough,true); XCTAssertEqual(text.textRuns?.first?.style.tracking ?? 0,1.25,accuracy:0.01)
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

extension AdvancedTests {
    func testLayoutInheritanceKeepsContentAndLocalGeometryOverrides() throws {
        var deck=Presentation(); var template=SlideObject(kind:.text,name:"Title",frame:Rect(40,40,900,100)); template.placeholderKey="title"
        let layout=MasterLayout(name:"Title",objects:[template]); deck.masters?[0].layouts=[layout]; deck.slides[0].layoutID=layout.id
        deck.slides[0].objects[0].placeholderKey="title"; deck.slides[0].objects[0].layoutLinked=true
        let text=deck.slides[0].objects[0].text
        XCTAssertEqual(deck.resolvedContent(deck.slides[0]).objects[0].frame,template.frame); XCTAssertEqual(deck.resolvedContent(deck.slides[0]).objects[0].text,text)
        deck.slides[0].objects[0].transform(to:Rect(200,200,300,100))
        XCTAssertEqual(deck.resolvedContent(deck.slides[0]).objects[0].frame.x,200)
        deck.slides[0].objects[0].masterTextLinked=true; deck.masters?[0].titleFont.size=66
        XCTAssertEqual(deck.resolvedContent(deck.slides[0]).objects[0].textStyle.size,66)
        try PresentationFile.validate(deck)
    }
}

extension AdvancedTests {
    func testConnectorFollowsObjectsAndDuplicateTargets() throws {
        var slide=Slide(); let a=SlideObject(kind:.shape,name:"A",frame:Rect(20,30,100,80)), b=SlideObject(kind:.shape,name:"B",frame:Rect(400,200,120,60))
        var line=SlideObject(kind:.shape,name:"Link",frame:Rect(0,0,1,1)); line.connector=Connector(start:ConnectorEndpoint(point:Point(),objectID:a.id,anchor:.right),end:ConnectorEndpoint(point:Point(),objectID:b.id,anchor:.left)); slide.objects=[a,b,line]
        XCTAssertEqual(slide.resolvingConnectors().objects[2].connector?.start.point,Point(120,70))
        slide.objects[0].frame.x=80; XCTAssertEqual(slide.resolvingConnectors().objects[2].connector?.start.point,Point(180,70))
        let copy=slide.duplicated(); XCTAssertEqual(copy.objects[2].connector?.start.objectID,copy.objects[0].id); XCTAssertNotEqual(copy.objects[2].connector?.start.objectID,a.id)
        var deck=Presentation(); deck.slides=[slide]
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }; _=try PowerPoint.export(deck,to:url)
        let imported=try PowerPoint.importDeck(from:url).deck.slides[0]; XCTAssertEqual(imported.objects[2].connector?.start.objectID,imported.objects[0].id)
    }
}

extension AdvancedTests {
    func testIndependentPlaceholderInheritance() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"inherited",withExtension:"pptx",subdirectory:"Fixtures"))
        let deck=try PowerPoint.importDeck(from:url).deck
        let title=try XCTUnwrap(deck.slides[0].objects.first { $0.text == "Inherited title placement" })
        XCTAssertEqual(title.frame.x,72,accuracy:0.01); XCTAssertEqual(title.frame.y,223.6667,accuracy:0.01); XCTAssertEqual(title.frame.width,816,accuracy:0.01)
        XCTAssertGreaterThan(title.textStyle.size,40); XCTAssertNotEqual(deck.theme.name,"Studio")
    }
}

extension AdvancedTests {
    func testEqualSpacingAndSizeSnapping() {
        let peers=[Rect(0,0,100,80),Rect(150,0,100,80)]
        let moved=Geometry.snap(Rect(302,0,100,80),others:peers,guides:[],width:1280,height:720,tolerance:5)
        XCTAssertEqual(moved.0.x,300); XCTAssertTrue(moved.1.contains { $0.label == "Equal spacing" })
        let resized=Geometry.snapSize(Rect(300,0,103,78),others:peers,tolerance:5)
        XCTAssertEqual(resized.0.width,100); XCTAssertEqual(resized.0.height,80)
    }
}

extension AdvancedTests {
    func testPowerPointPreservesNestedRotatedEditableGroups() throws {
        var child=SlideObject(kind:.text,name:"Editable text",frame:Rect(100,100,300,80)); child.text="Group contents"; child.textStyle.size=32
        var inner=SlideObject(kind:.group,name:"Inner",frame:child.frame); inner.children=[child]; inner.rotation=15
        var outer=SlideObject(kind:.group,name:"Outer",frame:child.frame); outer.children=[inner]; outer.rotation=20
        outer.transform(to:Rect(100,100,600,160)); XCTAssertEqual(outer.children[0].children[0].textStyle.size,64)
        var deck=Presentation(); deck.slides[0].objects=[outer]
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url); let imported=try PowerPoint.importDeck(from:url).deck.slides[0].objects[0]
        XCTAssertEqual(imported.kind,.group); XCTAssertEqual(imported.rotation,20); XCTAssertEqual(imported.children[0].rotation,15); XCTAssertEqual(imported.children[0].children[0].text,"Group contents"); XCTAssertEqual(imported.children[0].children[0].textStyle.size,64)
    }
    func testPowerPointTransitionSettingsRoundTrip() throws {
        var deck=Presentation(); deck.slides=[]
        for kind in TransitionKind.allCases {
            var slide=Slide(); slide.transition.kind=kind; slide.transition.direction = .up; slide.transition.duration=1.375; slide.transition.advanceAfter=8.125; slide.transition.advanceOnClick=false; deck.slides.append(slide)
        }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx")
        defer { try? FileManager.default.removeItem(at:url) }
        let warnings=try PowerPoint.export(deck,to:url)
        XCTAssertTrue(warnings.contains { $0.contains("Continuity") })
        let imported=try PowerPoint.importDeck(from:url).deck
        for (original,copy) in zip(deck.slides,imported.slides) {
            XCTAssertEqual(copy.transition.kind,original.transition.kind == .continuity ? .fade : original.transition.kind)
            XCTAssertEqual(copy.transition.duration,1.375,accuracy:0.001)
            XCTAssertEqual(copy.transition.advanceAfter,8.125)
            XCTAssertEqual(copy.transition.advanceOnClick,false)
            if [.push,.wipe,.slide].contains(original.transition.kind) { XCTAssertEqual(copy.transition.direction,.up) }
        }
    }
    func testMalformedMergeDoesNotOverflowAndFreeConnectorDuplicatesWithOffset() throws {
        var table=TableContent()
        XCTAssertThrowsError(try table.merge(CellMerge(row:1,column:0,rows:Int.max,columns:1)))
        XCTAssertFalse(CellMerge(row:Int.max,column:0,rows:Int.max,columns:1).contains(row:1,column:0))
        var object=SlideObject(kind:.shape,name:"Connector",frame:Rect(10,20,30,40))
        object.connector=Connector(start:ConnectorEndpoint(point:Point(10,20)),end:ConnectorEndpoint(point:Point(40,60)))
        let copy=object.duplicated(offset:Point(24,24))
        XCTAssertEqual(copy.connector?.start.point,Point(34,44)); XCTAssertEqual(copy.connector?.end.point,Point(64,84))
    }
    func testConnectorHitTestingUsesPathInsteadOfBoundingBox() {
        var object=SlideObject(kind:.shape,name:"Connector",frame:Rect(0,0,100,100)); object.connector=Connector(start:ConnectorEndpoint(point:Point()),end:ConnectorEndpoint(point:Point(100,100)))
        XCTAssertTrue(Geometry.hit(Point(50,52),object:object)); XCTAssertFalse(Geometry.hit(Point(5,90),object:object))
        object.connector?.kind = .curved
        XCTAssertTrue(Geometry.hit(Point(50,50),object:object)); XCTAssertFalse(Geometry.hit(Point(5,90),object:object))
        object.rotation=90
        XCTAssertTrue(Geometry.hit(Point(50,50),object:object))
    }
    func testCurvedMotionPathPassesThroughEditablePoints() {
        var animation=ObjectAnimation(objectID:UUID(),effect:.motionPath); animation.path=[Point(0,0),Point(100,200),Point(200,0)]; animation.curvedPath=true
        XCTAssertEqual(AnimationEngine.pathPosition(animation,progress:0),Point())
        XCTAssertEqual(AnimationEngine.pathPosition(animation,progress:0.5),Point(100,200))
        XCTAssertEqual(AnimationEngine.pathPosition(animation,progress:1),Point(200,0))
        let curved=AnimationEngine.pathPosition(animation,progress:0.25)
        animation.curvedPath=false
        XCTAssertNotEqual(curved,AnimationEngine.pathPosition(animation,progress:0.25))
    }
    func testOfficeAnimationBehaviorsAndClickTiming() throws {
        var deck=Presentation(); let object=deck.slides[0].objects[0]
        deck.slides[0].animations=AnimationEffect.allCases.enumerated().map { index,effect in
            var value=ObjectAnimation(objectID:object.id,effect:effect); value.start=AnimationStart.allCases[index%3]; value.delay=0.125; value.duration=0.8; value.direction = .down; value.path=[Point(object.frame.midX,object.frame.midY),Point(700,500)]; return value
        }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url); let imported=try PowerPoint.importDeck(from:url).deck.slides[0]
        XCTAssertEqual(imported.animations?.count,AnimationEffect.allCases.count)
        for (original,copy) in zip(deck.slides[0].animations!,imported.animations ?? []) {
            XCTAssertEqual(original.effect,copy.effect); XCTAssertEqual(original.start,copy.start); XCTAssertEqual(original.delay,copy.delay,accuracy:0.001); XCTAssertEqual(original.duration,copy.duration,accuracy:0.001)
        }
        XCTAssertEqual(imported.animations?.last?.path.last,Point(700,500))
    }
    func testPowerPointCommentThreadsAndAuthors() throws {
        var deck=Presentation(), comment=Comment(text:"Review this title",author:"Alex",objectID:nil)
        comment.objectID=deck.slides[0].objects[0].id; comment.resolved=true; comment.addReply("Updated",author:"Sam"); deck.slides[0].comments=[comment]
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url); let slide=try PowerPoint.importDeck(from:url).deck.slides[0]
        XCTAssertEqual(slide.comments.count,1); XCTAssertEqual(slide.comments[0].text,comment.text); XCTAssertEqual(slide.comments[0].author,"Alex")
        XCTAssertEqual(slide.comments[0].messages.first?.author,"Sam"); XCTAssertEqual(slide.comments[0].messages.first?.text,"Updated")
        XCTAssertTrue(slide.comments[0].resolved); XCTAssertEqual(slide.comments[0].objectID,slide.objects[0].id)
    }
    func testRichTableTextSurvivesStructureChangesAndOfficeExchange() throws {
        var table=TableContent(), style=TextStyle(); style.bold=true; style.color=RGBA(1,0,0); style.hyperlink="https://example.com/table"
        table.setText("Rich cell",row:1,column:1,runs:[TextRun(location:0,length:4,style:style)])
        table.insertRow(at:0); table.insertColumn(at:0)
        XCTAssertEqual(table.richText?["2:2"]?.first?.length,4)
        var deck=Presentation(), object=SlideObject(kind:.table,name:"Table",frame:Rect(100,100,800,400)); object.table=table; deck.slides[0].objects=[object]
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url); let imported=try PowerPoint.importDeck(from:url).deck.slides[0].objects[0].table!
        XCTAssertEqual(imported.cells[2][2],"Rich cell"); XCTAssertTrue(imported.richText?["2:2"]?.first?.style.bold == true)
        XCTAssertEqual(imported.richText?["2:2"]?.first?.style.hyperlink,"https://example.com/table")
        table.setText("Replaced",row:2,column:2); XCTAssertNil(table.richText?["2:2"])
    }
    func testMasterRelationshipsStayEditableAcrossOfficeExchange() throws {
        var deck=Presentation(), master=SlideMaster(); master.name="Corporate"; master.titleFont.size=62
        var footer=SlideObject(kind:.text,name:"Footer",frame:Rect(50,650,400,40)); footer.text="Shared footer"; master.objects=[footer]
        var placeholder=SlideObject(kind:.text,name:"Title layout",frame:Rect(120,100,900,120)); placeholder.placeholderKey="title"
        let layout=MasterLayout(name:"Custom title",objects:[placeholder]); master.layouts=[layout]; deck.masters=[master]
        var object=placeholder.duplicated(offset:Point()); object.text="Linked title"; object.layoutLinked=true; object.masterTextLinked=true
        deck.slides[0].objects=[object]; deck.slides[0].masterID=master.id; deck.slides[0].layoutID=layout.id
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }
        _=try PowerPoint.export(deck,to:url); var imported=try PowerPoint.importDeck(from:url).deck
        XCTAssertEqual(imported.masters?.first?.name,"Corporate"); XCTAssertEqual(imported.slides[0].objects.count,1)
        XCTAssertEqual(imported.resolved(imported.slides[0]).objects.count,2)
        imported.masters?[0].layouts[0].objects[0].frame.x=230; imported.masters?[0].titleFont.size=70
        let resolved=imported.resolvedContent(imported.slides[0])
        XCTAssertEqual(resolved.objects[0].frame.x,230); XCTAssertEqual(resolved.objects[0].textStyle.size,70)
    }
}
