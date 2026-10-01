import AppKit
import QuartzCore
import PresentationCore

final class AudienceView: NSView {
    var deck=Presentation(); var index=0; var black=false; var pointer: NSPoint?; var laser=false
    var playbackSlide: Slide?
    var wipeFrom: Slide?
    var wipeProgress: Double=1
    var wipeDirection: MotionDirection = .left
    var onKey: ((UInt16,String) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill(); guard !black else { return }
        let scale=min(bounds.width/deck.width,bounds.height/deck.height)
        let r=NSRect(x:(Double(bounds.width)-deck.width*Double(scale))/2,y:(Double(bounds.height)-deck.height*Double(scale))/2,width:deck.width*scale,height:deck.height*scale)
        if let previous=wipeFrom, wipeProgress < 1 {
            SlideRenderer.shared.draw(slide:previous,deck:deck,in:r)
            NSGraphicsContext.saveGraphicsState()
            var clip=r
            switch wipeDirection {
            case .left:clip.size.width *= wipeProgress
            case .right:clip.origin.x += clip.width*(1-wipeProgress); clip.size.width *= wipeProgress
            case .up:clip.size.height *= wipeProgress
            case .down:clip.origin.y += clip.height*(1-wipeProgress); clip.size.height *= wipeProgress
            }; clip.clip()
            SlideRenderer.shared.draw(slide:playbackSlide ?? deck.slides[index],deck:deck,in:r)
            NSGraphicsContext.restoreGraphicsState()
        } else { SlideRenderer.shared.draw(slide:playbackSlide ?? deck.slides[index],deck:deck,in:r) }
        if laser, let p=pointer { NSColor.systemRed.setFill(); NSBezierPath(ovalIn:NSRect(x:p.x-5,y:p.y-5,width:10,height:10)).fill() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseMoved,.activeAlways,.inVisibleRect],owner:self,userInfo:nil))
    }
    override func keyDown(with event: NSEvent) { onKey?(event.keyCode,event.charactersIgnoringModifiers ?? "") }
    override func mouseDown(with event: NSEvent) { onKey?(124,"") }
    override func mouseMoved(with event: NSEvent) { pointer=convert(event.locationInWindow,from:nil); if laser { needsDisplay=true } }
}
final class AudienceWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }
final class PresenterWindow: NSWindow {
    var onKey: ((UInt16,String) -> Void)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.modifierFlags.contains(.command),
           [53,123,124,125,126,49,36].contains(event.keyCode) || (event.type == .keyDown && ["b","p","l"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "")) {
            onKey?(event.keyCode,event.charactersIgnoringModifiers ?? ""); return
        }
        super.sendEvent(event)
    }
}
final class PresenterController: NSObject, NSWindowDelegate {
    let deck: Presentation
    var index: Int
    let audience=AudienceView()
    var audienceWindow: NSWindow?
    var console: NSWindow?
    var clock: Timer?, advance: Timer?, visualTimer: Timer?
    var animationClick=0
    var animationStarted=Date()
    var transitionStarted=Date()
    var transitionFrom: Slide?
    var transitionDuration=0.0
    var transitionKind: TransitionKind = .none
    var started=Date(); var paused=false; var pausedAt: Date?
    var elapsedLabel=NSTextField(labelWithString:"")
    var notes=NSTextView()
    var currentImage=NSImageView(), nextImage=NSImageView()
    init(deck: Presentation,startID: UUID) { self.deck=deck; index=deck.slides.firstIndex { $0.id == startID } ?? 0; super.init() }
    func start() {
        let screen=NSScreen.screens.last ?? NSScreen.main!
        let window=AudienceWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false,screen:screen)
        window.level = .normal; window.backgroundColor = .black; window.isReleasedWhenClosed=false; window.delegate=self; window.acceptsMouseMovedEvents=true
        audience.frame=NSRect(origin:.zero,size:screen.frame.size); audience.autoresizingMask=[.width,.height]; audience.wantsLayer=true; audience.deck=deck; audience.index=index
        audience.onKey = { [weak self] code,characters in self?.key(code,characters) }; window.contentView=audience
        audienceWindow=window; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(audience)
        if NSScreen.screens.count > 1 { makeConsole() }
        animationStarted=Date(); visualTimer=Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] _ in self?.tick() }
        started=Date(); clock=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in self?.updateClock() }; update(); scheduleAdvance()
        NSApp.presentationOptions=[.autoHideDock,.autoHideMenuBar]
    }
    func makeConsole() {
        guard let screen=NSScreen.screens.first else { return }
        let window=PresenterWindow(contentRect:NSRect(x:screen.visibleFrame.minX+40,y:screen.visibleFrame.minY+40,width:1000,height:700),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.onKey = { [weak self] code,characters in self?.key(code,characters) }
        window.title="Orator — Presenter View"; window.delegate=self; window.isReleasedWhenClosed=false
        let stack=NSStackView(); stack.orientation = .vertical; stack.spacing=16; stack.edgeInsets=NSEdgeInsets(top:20,left:20,bottom:20,right:20); stack.frame=window.contentView!.bounds; stack.autoresizingMask=[.width,.height]; window.contentView=stack
        let images=NSStackView(views:[currentImage,nextImage]); images.distribution = .fillEqually
        currentImage.imageScaling = .scaleProportionallyUpOrDown; nextImage.imageScaling = .scaleProportionallyUpOrDown; images.heightAnchor.constraint(equalToConstant:280).isActive=true; stack.addArrangedSubview(images)
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize:16,weight:.medium); stack.addArrangedSubview(elapsedLabel)
        let scroll=NSScrollView(); scroll.hasVerticalScroller=true; scroll.documentView=notes; notes.isEditable=false; notes.font = .systemFont(ofSize:22); notes.autoresizingMask=[.width]; notes.textContainer?.widthTracksTextView=true; notes.isVerticallyResizable=true; stack.addArrangedSubview(scroll); scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:200).isActive=true
        let controls=NSStackView(views:[NSButton(title:"Previous",target:self,action:#selector(previous)),NSButton(title:"Next",target:self,action:#selector(next)),NSButton(title:"Pause",target:self,action:#selector(pause)),NSButton(title:"Black Screen",target:self,action:#selector(black)),NSButton(title:"End",target:self,action:#selector(end))]); stack.addArrangedSubview(controls)
        console=window; window.orderFront(nil)
    }
    func key(_ code: UInt16,_ characters: String) {
        switch code { case 53:end(); case 123,126:previous(); case 124,125,49,36:next(); default:
            if characters.lowercased() == "b" { black() }; if characters.lowercased() == "p" { pause() }; if characters.lowercased() == "l" { audience.laser.toggle(); audience.needsDisplay=true }
        }
    }
    @objc func next() {
        let clicks=AnimationEngine.schedule(deck.slides[index].animations ?? []).map(\.click).max() ?? 0
        if animationClick < clicks { animationClick += 1; animationStarted=Date(); tick(); return }
        navigate(1)
    }
    @objc func previous() { navigate(-1) }
    func navigate(_ delta: Int) {
        var next=index+delta
        while deck.slides.indices.contains(next), deck.slides[next].skipped { next += delta }
        guard deck.slides.indices.contains(next) else { return }
        let transition=deck.slides[next].transition
        transitionFrom=deck.resolved(deck.slides[index]); transitionStarted=Date(); transitionDuration=transition.duration; transitionKind=transition.kind
        animationClick=0; animationStarted=Date()
        if transition.kind != .none && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation=CATransition(); animation.type=[TransitionKind.fade,.dissolve].contains(transition.kind) ? .fade : .push
            switch transition.direction ?? (delta > 0 ? .left : .right) { case .left:animation.subtype = .fromRight; case .right:animation.subtype = .fromLeft; case .up:animation.subtype = .fromTop; case .down:animation.subtype = .fromBottom }
             animation.duration=transition.duration; if ![TransitionKind.wipe,.continuity,.zoom].contains(transition.kind) { audience.layer?.add(animation,forKey:"slide") }
            if transition.kind == .zoom { let zoom=CABasicAnimation(keyPath:"transform.scale"); zoom.fromValue=0.8; zoom.toValue=1; zoom.duration=transition.duration; audience.layer?.add(zoom,forKey:"zoom") }
        }
        index=next; audience.black=false; update(); scheduleAdvance()
    }
    func update() {
        audience.index=index; tick(); audience.needsDisplay=true; notes.string=deck.slides[index].notes
        if console != nil {
            currentImage.image=SlideRenderer.shared.thumbnail(slide:deck.slides[index],deck:deck,size:NSSize(width:640,height:360))
            let next=deck.slides.indices.first { $0 > index && !deck.slides[$0].skipped }
            nextImage.image=next.map { SlideRenderer.shared.thumbnail(slide:deck.slides[$0],deck:deck,size:NSSize(width:640,height:360)) }
        }; updateClock()
    }
    func tick() {
        guard !paused else { return }
        let elapsed=Date().timeIntervalSince(animationStarted)
        let reduced=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var frame=AnimationEngine.frame(slide:deck.slides[index],click:animationClick,elapsed:elapsed,width:deck.width,height:deck.height,reducedMotion:reduced)
        let t=reduced ? 1 : min(1,Date().timeIntervalSince(transitionStarted)/max(0.001,transitionDuration))
        if t < 1, let from=transitionFrom {
            if transitionKind == .continuity { frame=AnimationEngine.interpolate(from:from,to:deck.resolved(frame),progress:t) }
            if transitionKind == .wipe { audience.wipeFrom=from; audience.wipeProgress=t; audience.wipeDirection=deck.slides[index].transition.direction ?? .left }
        } else { transitionFrom=nil; audience.wipeFrom=nil }
        if audience.playbackSlide != frame || audience.wipeFrom != nil { audience.playbackSlide=frame; audience.needsDisplay=true }
    }
    func updateClock() {
        let elapsed=Int((pausedAt ?? Date()).timeIntervalSince(started))
        elapsedLabel.stringValue=String(format:"%02d:%02d",elapsed/60,elapsed%60)+"   ·   Slide \(index+1) of \(deck.slides.count)   ·   "+DateFormatter.localizedString(from:Date(),dateStyle:.none,timeStyle:.short)+(paused ? "   Paused" : "")
    }
    func scheduleAdvance() { advance?.invalidate(); guard !paused, let interval=deck.slides[index].transition.advanceAfter else { return }; advance=Timer.scheduledTimer(withTimeInterval:max(0.2,interval),repeats:false) { [weak self] _ in self?.next() } }
    @objc func pause() { paused.toggle(); if paused { pausedAt=Date(); advance?.invalidate() } else { if let at=pausedAt { let interval=Date().timeIntervalSince(at); started=started.addingTimeInterval(interval); animationStarted=animationStarted.addingTimeInterval(interval); transitionStarted=transitionStarted.addingTimeInterval(interval) }; pausedAt=nil; scheduleAdvance() }; updateClock() }
    @objc func black() { audience.black.toggle(); audience.needsDisplay=true }
    @objc func end() { clock?.invalidate(); advance?.invalidate(); visualTimer?.invalidate(); audienceWindow?.orderOut(nil); console?.orderOut(nil); NSApp.presentationOptions=[]; audienceWindow=nil; console=nil }
    func windowWillClose(_ notification: Notification) { end() }
    deinit { clock?.invalidate(); advance?.invalidate(); visualTimer?.invalidate() }
}
