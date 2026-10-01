import AppKit
import PresentationCore

extension SlideRenderer {
    func drawChart(_ chart: ChartContent,object: SlideObject,deck: Presentation) {
        let r=object.frame.nsRect, series=chart.dataSeries
        guard !chart.labels.isEmpty else { return }
        var label=object.textStyle; label.size=14; label.alignment = .center
        var title=object.textStyle; title.size=24; title.bold=true
        drawText(chart.title,style:title,rect:NSRect(x:r.minX,y:r.minY,width:r.width,height:34),theme:deck.theme)
        let legend=chart.showLegend != false
        let plot=NSRect(x:r.minX+72,y:r.minY+48,width:max(1,r.width-100),height:max(1,r.height-(legend ? 150 : 116)))
        let palette: [RGBA]=[deck.theme.accent,RGBA(0.19,0.55,0.46),RGBA(0.82,0.46,0.20),RGBA(0.55,0.39,0.65),RGBA(0.67,0.28,0.33)]
        func color(_ i: Int) -> NSColor { (series[i].color ?? palette[i%palette.count]).nsColor }
        let values=series.flatMap(\.values), maximum=max(1,values.max() ?? 1), minimum=min(0,values.min() ?? 0), span=maximum-minimum
        let count=chart.labels.count, slot=plot.width/Double(count)
        func y(_ v: Double) -> Double { plot.maxY-(v-minimum)/span*plot.height }
        func x(_ v: Double) -> Double { plot.minX+(v-minimum)/span*plot.width }
        if chart.kind == .pie {
            let values=series[0].values, total=values.reduce(0) { $0+max(0,$1) }; guard total > 0 else { return }
            var angle=0.0
            for (i,v) in values.enumerated() {
                let end=angle+max(0,v)/total*360, path=NSBezierPath(); path.move(to:NSPoint(x:plot.midX,y:plot.midY)); path.appendArc(withCenter:NSPoint(x:plot.midX,y:plot.midY),radius:min(plot.width,plot.height)/2,startAngle:angle,endAngle:end); path.close(); palette[i%palette.count].nsColor.setFill(); path.fill()
                if chart.showDataLabels == true { let a=(angle+end)/2 * .pi/180, radius=min(plot.width,plot.height)*0.35; var style=label; style.color = .white; drawText(String(format:"%.0f%%",v/total*100),style:style,rect:NSRect(x:plot.midX+cos(a)*radius-30,y:plot.midY+sin(a)*radius-10,width:60,height:22),theme:deck.theme) }; angle=end
            }
        } else {
            for n in 0...4 {
                let v=minimum+span*Double(n)/4
                if chart.showGridlines != false {
                    deck.theme.foreground.nsColor.withAlphaComponent(0.15).setStroke(); let path=NSBezierPath()
                    if chart.kind == .bar { path.move(to:NSPoint(x:x(v),y:plot.minY)); path.line(to:NSPoint(x:x(v),y:plot.maxY)) }
                    else { path.move(to:NSPoint(x:plot.minX,y:y(v))); path.line(to:NSPoint(x:plot.maxX,y:y(v))) }; path.stroke()
                }
                if chart.kind == .bar { drawText(String(format:"%.3g",v),style:label,rect:NSRect(x:x(v)-24,y:plot.maxY+6,width:48,height:22),theme:deck.theme) }
                else { var axis=label; axis.alignment = .right; drawText(String(format:"%.3g",v),style:axis,rect:NSRect(x:r.minX,y:y(v)-10,width:62,height:22),theme:deck.theme) }
            }
            let numericX=chart.labels.enumerated().map { Double($0.element) ?? Double($0.offset+1) }, minX=chart.labels.compactMap(Double.init).min() ?? 1, maxX=chart.labels.compactMap(Double.init).max() ?? Double(count)
            for (s,data) in series.enumerated() {
                let line=NSBezierPath(), color=color(s); color.setFill()
                for (i,v) in data.values.enumerated() {
                    let px=chart.kind == .scatter ? plot.minX+(numericX[i]-minX)/max(1,maxX-minX)*plot.width : plot.minX+(Double(i)+0.5)*slot
                    let point=NSPoint(x:px,y:y(v)); var labelRect=NSRect(x:px-30,y:y(v)-24,width:60,height:22)
                    switch chart.kind {
                    case .column:
                        let width=slot*0.8/Double(series.count), left=px-slot*0.4+Double(s)*width
                        NSRect(x:left,y:min(y(v),y(0)),width:max(1,width-2),height:max(1,abs(y(v)-y(0)))).fill(); labelRect.origin.x=left-12
                    case .bar:
                        let row=plot.height/Double(count), height=row*0.8/Double(series.count), top=plot.minY+Double(i)*row+row*0.1+Double(s)*height
                        NSRect(x:min(x(0),x(v)),y:top,width:max(1,abs(x(v)-x(0))),height:max(1,height-2)).fill(); labelRect=NSRect(x:x(v)+4,y:top,width:60,height:22)
                    case .line,.area: if i == 0 { line.move(to:point) } else { line.line(to:point) }
                    case .scatter: NSBezierPath(ovalIn:NSRect(x:px-4,y:point.y-4,width:8,height:8)).fill()
                    case .pie:break
                    }
                    if chart.showDataLabels == true { drawText(String(format:"%.3g",v),style:label,rect:labelRect,theme:deck.theme) }
                }
                color.setStroke(); line.lineWidth=3; line.stroke()
                if chart.kind == .area { line.line(to:NSPoint(x:plot.maxX-slot/2,y:y(0))); line.line(to:NSPoint(x:plot.minX+slot/2,y:y(0))); line.close(); color.withAlphaComponent(0.2).setFill(); line.fill() }
            }
            let stride=max(1,count/12)
            for i in 0..<count where i%stride == 0 {
                if chart.kind == .bar { var style=label; style.alignment = .right; drawText(chart.labels[i],style:style,rect:NSRect(x:r.minX,y:plot.minY+(Double(i)+0.5)*plot.height/Double(count)-10,width:62,height:22),theme:deck.theme) }
                else { let px=chart.kind == .scatter ? plot.minX+(numericX[i]-minX)/max(1,maxX-minX)*plot.width : plot.minX+(Double(i)+0.5)*slot; drawText(chart.labels[i],style:label,rect:NSRect(x:px-max(24,slot)/2,y:plot.maxY+6,width:max(48,slot),height:22),theme:deck.theme) }
            }
        }
        if let axis=chart.categoryAxisTitle, !axis.isEmpty { drawText(axis,style:label,rect:NSRect(x:plot.minX,y:plot.maxY+34,width:plot.width,height:22),theme:deck.theme) }
        if let axis=chart.valueAxisTitle, !axis.isEmpty { var style=label; style.alignment = .left; drawText(axis,style:style,rect:NSRect(x:plot.minX,y:r.minY+30,width:plot.width,height:20),theme:deck.theme) }
        if legend {
            let names=chart.kind == .pie ? chart.labels : series.map(\.name), width=Double(plot.width)/Double(max(1,names.count))
            for (i,name) in names.enumerated() { (chart.kind == .pie ? palette[i%palette.count].nsColor : color(i)).setFill(); NSRect(x:Double(plot.minX)+Double(i)*width,y:r.maxY-22,width:10,height:10).fill(); var style=label; style.alignment = .left; drawText(name,style:style,rect:NSRect(x:Double(plot.minX)+Double(i)*width+16,y:r.maxY-28,width:max(1,width-20),height:24),theme:deck.theme) }
        }
    }
}
