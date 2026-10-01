import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension PowerPoint {
    static func transitionXML(_ transition: Transition) -> String {
        guard transition.kind != .none || transition.advanceAfter != nil || transition.advanceOnClick == false else { return "" }
        let direction: String
        switch transition.direction ?? .left { case .left: direction="l"; case .right: direction="r"; case .up: direction="u"; case .down: direction="d" }
        let effect: String
        switch transition.kind {
        case .none: effect=""
        case .fade, .continuity: effect="<p:fade/>"
        case .dissolve: effect="<p:dissolve/>"
        case .push: effect="<p:push dir=\"\(direction)\"/>"
        case .wipe: effect="<p:wipe dir=\"\(direction)\"/>"
        case .slide: effect="<p:cover dir=\"\(direction)\"/>"
        case .zoom: effect="<p:zoom dir=\"in\"/>"
        }
        let speed=transition.duration < 0.5 ? "fast" : transition.duration < 1 ? "med" : "slow"
        let advance=transition.advanceAfter.map { " advTm=\"\(Int(($0*1000).rounded()))\"" } ?? ""
        let attributes="spd=\"\(speed)\" advClick=\"\(transition.advanceOnClick == false ? 0 : 1)\"\(advance)"
        // The fallback remains readable by clients predating Office 2010 duration metadata.
        return "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\"><mc:Choice Requires=\"p14\"><p:transition \(attributes) p14:dur=\"\(Int((transition.duration*1000).rounded()))\">\(effect)</p:transition></mc:Choice><mc:Fallback><p:transition \(attributes)>\(effect)</p:transition></mc:Fallback></mc:AlternateContent>"
    }
    static func readTransition(_ node: XMLElement?) -> Transition {
        var value=Transition(); guard let node else { return value }
        for (tag,kind) in [("fade",TransitionKind.fade),("dissolve",.dissolve),("push",.push),("wipe",.wipe),("cover",.slide),("zoom",.zoom)] {
            if let effect=node.first(tag) {
                value.kind=kind
                if let direction=["l":MotionDirection.left,"r":.right,"u":.up,"d":.down][effect.attr("dir")] { value.direction=direction }
                break
            }
        }
        value.duration=Double(node.attr("p14:dur")).map { $0/1000 } ?? (node.attr("spd") == "slow" ? 1 : node.attr("spd") == "fast" ? 0.25 : 0.5)
        value.advanceOnClick = !["0","false"].contains(node.attr("advClick"))
        value.advanceAfter=Double(node.attr("advTm")).map { $0/1000 }
        return value
    }
}
