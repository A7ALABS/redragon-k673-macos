import Foundation

public struct Backup: Codable, Sendable {
    public var created: Date
    public var profile: Data
    public var palette: Data
    public var keyColors: Data
    public var matrix: Data

    public static func capture(from kb: Keyboard) throws -> Backup {
        Backup(
            created: Date(),
            profile: Data(try kb.readProfile().bytes),
            palette: Data(try kb.readPalette().bytes),
            keyColors: Data(try kb.readKeyColors().bytes),
            matrix: Data(try kb.readKeyMatrix().bytes)
        )
    }

    public func restore(to kb: Keyboard) throws {
        // Validate everything before the first write so a truncated file cannot leave the keyboard half-restored.
        let profile = try Profile(bytes: Array(profile))
        let palette = try Palette(bytes: Array(palette))
        let colors = try KeyColors(bytes: Array(keyColors))
        let matrix = try KeyMatrix(bytes: Array(matrix))
        try kb.writePalette(palette)
        try kb.writeKeyColors(colors)
        try kb.writeKeyMatrix(matrix)
        try kb.writeProfile(profile)
    }

    public func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> Backup {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Backup.self, from: Data(contentsOf: url))
    }
}
