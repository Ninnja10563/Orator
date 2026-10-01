import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
extension PowerPoint {
    static func objectStyleXML(_ object: SlideObject,theme: Theme) -> String {
        func alpha(_ color: RGBA) -> RGBA { RGBA(color.red,color.green,color.blue,color.alpha*object.opacity) }
        var fill: String
        let isLine=[ShapeKind.line,.arrow,.doubleArrow].contains(object.shape)
        if object.kind == .text || isLine { fill="<a:noFill/>" }
        else if let gradient=object.style.gradient {
            let angle=(gradient.angle.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)
            fill="<a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\">\(color(alpha(object.style.fill ?? theme.accent)))</a:gs><a:gs pos=\"100000\">\(color(alpha(gradient.end)))</a:gs></a:gsLst><a:lin ang=\"\(Int(angle*60000))\" scaled=\"1\"/></a:gradFill>"
        } else { fill=solid(alpha(object.style.fill ?? theme.accent)) }
        let width=object.style.strokeWidth > 0 ? object.style.strokeWidth : isLine ? 3 : 0
        if object.kind == .text || width == 0 { fill += "<a:ln><a:noFill/></a:ln>" }
        else {
            let stroke=object.style.strokeWidth > 0 ? object.style.stroke : object.style.fill ?? theme.accent
            let pattern=object.style.borderPattern == .dashed ? "dash" : object.style.borderPattern == .dotted ? "sysDot" : "solid"
            fill += "<a:ln w=\"\(emu(width))\">\(solid(alpha(stroke)))<a:prstDash val=\"\(pattern)\"/>"
            if object.shape == .doubleArrow { fill += "<a:headEnd type=\"triangle\"/>" }; if object.shape == .arrow || object.shape == .doubleArrow { fill += "<a:tailEnd type=\"triangle\"/>" }; fill += "</a:ln>"
        }
        if let shadow=object.style.shadow {
            let direction=(atan2(shadow.y,shadow.x)*180 / .pi+360).truncatingRemainder(dividingBy:360)
            fill += "<a:effectLst><a:outerShdw blurRad=\"\(emu(shadow.blur))\" dist=\"\(emu(hypot(shadow.x,shadow.y)))\" dir=\"\(Int(direction*60000))\" rotWithShape=\"0\">\(color(alpha(shadow.color)))</a:outerShdw></a:effectLst>"
        }; return fill
    }
    static func readObjectEffects(_ node: XMLElement,object: inout SlideObject,palette: [String:RGBA]) {
        if let gradient=node.first("spPr")?.direct("gradFill"), let first=gradient.first("gs"), let last=gradient.descendants("gs").last, let start=first.officeColor(palette:palette), let end=last.officeColor(palette:palette) {
            object.style.fill=start; object.style.gradient=GradientFill(end:end,angle:(gradient.first("lin")?.number("ang") ?? 0)/60000)
        }
        if let line=node.first("spPr")?.direct("ln") {
            object.style.borderPattern=line.first("prstDash")?.attr("val") == "dash" ? .dashed : line.first("prstDash")?.attr("val") == "sysDot" ? .dotted : .solid
        }
        if let shadow=node.first("spPr")?.first("outerShdw") {
            var value=ObjectShadow(); value.color=shadow.officeColor(palette:palette) ?? RGBA(0,0,0,0.25); value.blur=shadow.number("blurRad")/9525
            let angle=shadow.number("dir")/60000 * .pi/180, distance=shadow.number("dist")/9525
            value.x=cos(angle)*distance; value.y=sin(angle)*distance; object.style.shadow=value
        }
    }
}
