import AppKit
import CryptoKit
import PresentationCore

/// Assets are independent package members: saves avoid base64 expansion and reuse unchanged wrappers.
final class NativePackage {
    struct Manifest: Codable {
        var packageVersion=1
        var presentation: Presentation
        var lengths: [UUID:Int]
        var hashes: [UUID:String]
    }
    private struct CachedAsset { var data: Data; var hash: String; var wrapper: FileWrapper }
    private var cache: [UUID:CachedAsset]=[:]
    private func digest(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    func encode(_ deck: Presentation) throws -> FileWrapper {
        try PresentationFile.validate(deck)
        var metadata=deck, wrappers: [String:FileWrapper]=[:], lengths: [UUID:Int]=[:], hashes: [UUID:String]=[:]
        for (id,asset) in deck.assets {
            let entry: CachedAsset
            if let existing=cache[id], existing.data == asset.data { entry=existing }
            else { entry=CachedAsset(data:asset.data,hash:digest(asset.data),wrapper:FileWrapper(regularFileWithContents:asset.data)); cache[id]=entry }
            wrappers[id.uuidString+".bin"]=entry.wrapper; lengths[id]=asset.data.count; hashes[id]=entry.hash
            metadata.assets[id]?.data=Data()
        }
        cache=cache.filter { deck.assets[$0.key] != nil }
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
        let manifest=try encoder.encode(Manifest(presentation:metadata,lengths:lengths,hashes:hashes))
        return FileWrapper(directoryWithFileWrappers:["manifest.json":FileWrapper(regularFileWithContents:manifest),"Assets":FileWrapper(directoryWithFileWrappers:wrappers)])
    }
    func decode(_ wrapper: FileWrapper) throws -> Presentation {
        // Legacy version 1/2 single-file documents migrate on their next native save.
        if wrapper.isRegularFile, let data=wrapper.regularFileContents { return try PresentationFile.decode(data) }
        guard wrapper.isDirectory, let files=wrapper.fileWrappers, let metadata=files["manifest.json"], metadata.isRegularFile,
              let data=metadata.regularFileContents, data.count <= 50*1024*1024,
              let assets=files["Assets"], assets.isDirectory else { throw FormatError.invalid("missing native package manifest or assets directory") }
        let manifest=try JSONDecoder().decode(Manifest.self,from:data)
        guard manifest.packageVersion == 1 else { throw FormatError.invalid("this native package version requires a newer Orator") }
        var deck=manifest.presentation
        guard Set(manifest.lengths.keys) == Set(deck.assets.keys), Set(manifest.hashes.keys) == Set(deck.assets.keys) else { throw FormatError.invalid("asset manifest does not match presentation") }
        var total=0, restored: [UUID:CachedAsset]=[:]
        for id in deck.assets.keys {
            guard let length=manifest.lengths[id], (0...100*1024*1024).contains(length), let hash=manifest.hashes[id],
                  let asset=assets.fileWrappers?[id.uuidString+".bin"], asset.isRegularFile else { throw FormatError.invalid("missing or invalid package asset") }
            total += length; guard total <= 2_000_000_000 else { throw FormatError.invalid("native package exceeds the in-memory document limit") }
            if let size=asset.fileAttributes[.size] as? NSNumber, size.intValue != length { throw FormatError.invalid("asset size differs from its manifest") }
            guard let bytes=asset.regularFileContents, bytes.count == length, digest(bytes) == hash else { throw FormatError.invalid("asset checksum failed; the package may be incomplete or damaged") }
            deck.assets[id]?.data=bytes; restored[id]=CachedAsset(data:bytes,hash:hash,wrapper:asset)
        }
        if deck.formatVersion == 1 { deck.formatVersion=2 }; try PresentationFile.validate(deck); cache=restored; return deck
    }
}
