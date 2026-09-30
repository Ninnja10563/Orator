import Foundation

public struct RecoveryRecord: Codable, Sendable {
    public var sessionID: UUID
    public var originalPath: String?
    public var savedAt: Date
    public var presentation: Presentation
    public init(sessionID: UUID, originalPath: String?, presentation: Presentation) {
        self.sessionID=sessionID; self.originalPath=originalPath; self.presentation=presentation; savedAt=Date()
    }
}
/// Recovery files are separate from user documents and are never promoted over an original.
/// Retain the previous valid snapshot in case a new recovery write is interrupted.
public struct RecoveryStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory=directory }
    public func write(_ record: RecoveryRecord) throws {
        try PresentationFile.validate(record.presentation)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let current=directory.appendingPathComponent(record.sessionID.uuidString+".recovery")
        let previous=directory.appendingPathComponent(record.sessionID.uuidString+".previous")
        if let old=try? Data(contentsOf:current), let decoded=try? JSONDecoder().decode(RecoveryRecord.self,from:old), (try? PresentationFile.validate(decoded.presentation)) != nil {
            try old.write(to:previous,options:.atomic)
        }
        try JSONEncoder().encode(record).write(to:current,options:.atomic)
    }
    public func records() throws -> [RecoveryRecord] {
        guard FileManager.default.fileExists(atPath:directory.path) else { return [] }
        let urls=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
        let ids=Set(urls.filter { ["recovery","previous"].contains($0.pathExtension) }.map { $0.deletingPathExtension().lastPathComponent })
        return ids.compactMap { id in
            for ext in ["recovery","previous"] {
                let url=directory.appendingPathComponent(id+"."+ext)
                if let data=try? Data(contentsOf:url), let record=try? JSONDecoder().decode(RecoveryRecord.self,from:data), (try? PresentationFile.validate(record.presentation)) != nil { return record }
            }
            return nil
        }.sorted { $0.savedAt < $1.savedAt }
    }
    public func remove(_ sessionID: UUID) {
        for ext in ["recovery","previous"] { try? FileManager.default.removeItem(at:directory.appendingPathComponent(sessionID.uuidString+"."+ext)) }
    }
}
