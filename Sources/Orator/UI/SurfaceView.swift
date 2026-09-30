import AppKit

/// Opaque system surfaces also render correctly in offscreen previews and dark mode.
class SurfaceView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }
