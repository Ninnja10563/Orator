import AppKit

/// File adapters work on immutable snapshots; AppKit windows remain on the main thread.
enum DocumentTask {
    static func run<Value>(title: String,window: NSWindow?,operation: @escaping () throws -> Value,completion: @escaping (Result<Value,Error>) -> Void) {
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:360,height:100),styleMask:[.titled],backing:.buffered,defer:false)
        panel.title=title; panel.isReleasedWhenClosed=false
        let surface=SurfaceView(frame:panel.contentView!.bounds); panel.contentView=surface
        let progress=NSProgressIndicator(frame:NSRect(x:22,y:36,width:24,height:24)); progress.style = .spinning; progress.startAnimation(nil); surface.addSubview(progress)
        let label=NSTextField(labelWithString:title); label.frame=NSRect(x:60,y:38,width:280,height:24); surface.addSubview(label)
        if let window { window.beginSheet(panel) } else { panel.center(); panel.makeKeyAndOrderFront(nil) }
        DispatchQueue.global(qos:.userInitiated).async {
            let result: Result<Value,Error>=autoreleasepool { Result { try operation() } }
            DispatchQueue.main.async {
                if let parent=panel.sheetParent { parent.endSheet(panel) }; panel.close(); completion(result)
            }
        }
    }
}
