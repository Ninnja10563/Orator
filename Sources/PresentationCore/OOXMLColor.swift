import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
extension XMLElement {
    func officeColor(palette: [String:RGBA]) -> RGBA? {
        let node: XMLElement?
        if ["srgbClr","sysClr","schemeClr"].contains(localName ?? "") { node=self }
        else { node=first("srgbClr") ?? first("sysClr") ?? first("schemeClr") }
        guard let node=node else { return nil }
        var color: RGBA
        if node.localName == "schemeClr" { guard let value=palette[node.attr("val")] else { return nil }; color=value }
        else { let hex=node.localName == "sysClr" ? node.attr("lastClr") : node.attr("val"); let raw=UInt32(hex,radix:16) ?? 0; color=RGBA(Double((raw >> 16)&255)/255,Double((raw >> 8)&255)/255,Double(raw&255)/255) }
        for transform in node.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            let v=transform.number("val")/100000
            switch transform.localName {
            case "alpha":color.alpha=v
            case "tint":color.red += (1-color.red)*v; color.green += (1-color.green)*v; color.blue += (1-color.blue)*v
            case "shade","lumMod":color.red *= v; color.green *= v; color.blue *= v
            case "lumOff":color.red += v; color.green += v; color.blue += v
            default:break
            }
        }
        return RGBA(min(1,max(0,color.red)),min(1,max(0,color.green)),min(1,max(0,color.blue)),min(1,max(0,color.alpha)))
    }
}
