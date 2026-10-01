import AppKit

// A presentation frame and speaking corner, drawn as vectors at every icon size.
let directory=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=points*scale
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        bitmap.size=NSSize(width:pixels,height:pixels)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        let transform=NSAffineTransform(); transform.scale(by:Double(pixels)/1024); transform.concat()
        NSColor(calibratedRed:0.12,green:0.14,blue:0.17,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:80,y:80,width:864,height:864),xRadius:188,yRadius:188).fill()
        NSColor(calibratedWhite:0.97,alpha:1).setStroke()
        let screen=NSBezierPath(roundedRect:NSRect(x:258,y:326,width:508,height:398),xRadius:58,yRadius:58); screen.lineWidth=64; screen.stroke()
        NSColor(calibratedRed:0.19,green:0.53,blue:0.94,alpha:1).setFill()
        let voice=NSBezierPath(); voice.move(to:NSPoint(x:572,y:372)); voice.line(to:NSPoint(x:764,y:372)); voice.line(to:NSPoint(x:764,y:214)); voice.close(); voice.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name="icon_\(points)x\(points)"+(scale == 2 ? "@2x" : "")+".png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
    }
}
