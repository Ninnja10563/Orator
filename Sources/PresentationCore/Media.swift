import Foundation

public struct MediaContent: Codable, Equatable, Sendable {
    public var assetID: UUID
    public var posterAssetID: UUID? = nil
    public var trimStart: Double = 0
    public var trimEnd: Double? = nil
    public var sourceDuration: Double? = nil
    /// Office files express end trim as a duration removed from the tail.
    public var trimEndOffset: Double? = nil
    public var volume: Double = 1
    public var autoplay = false
    public var loop = false
    public var acrossSlides = false
    public var fadeIn: Double = 0
    public var fadeOut: Double = 0
    public init(assetID: UUID) { self.assetID=assetID }
}
