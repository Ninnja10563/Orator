import Foundation
public enum BorderPattern: String, Codable, CaseIterable, Sendable { case solid, dashed, dotted }
public struct GradientFill: Codable, Equatable, Sendable {
    public var end: RGBA
    public var angle: Double
    public init(end: RGBA,angle: Double = 0) { self.end=end; self.angle=angle }
}
public struct ObjectShadow: Codable, Equatable, Sendable {
    public var color: RGBA = RGBA(0,0,0,0.25)
    public var blur: Double = 8
    public var x: Double = 0
    public var y: Double = 4
    public init() {}
}

public extension RawRepresentable where RawValue == String {
    var displayName: String {
        let value=rawValue.replacingOccurrences(of:"([a-z])([A-Z])",with:"$1 $2",options:.regularExpression)
        return value.prefix(1).uppercased()+value.dropFirst()
    }
}
