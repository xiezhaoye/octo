import Foundation

public enum CommandTarget: String, Codable, CaseIterable, Sendable {
    case all, folders, files, extensions
    public var title: String {
        switch self { case .all: return "文件与文件夹"; case .folders: return "仅文件夹"; case .files: return "仅文件"; case .extensions: return "指定文件类型" }
    }
}

public struct CustomCommand: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var script: String
    public var target: CommandTarget
    public var fileExtensions: [String]
    public var foldersOnly: Bool { get { target == .folders } set { target = newValue ? .folders : .all } }
    public init(name: String, script: String, foldersOnly: Bool = false, target: CommandTarget? = nil, fileExtensions: [String] = []) {
        self.name = name; self.script = script; self.target = target ?? (foldersOnly ? .folders : .all)
        self.fileExtensions = Self.normalizeExtensions(fileExtensions.joined(separator: ","))
    }
    public static func normalizeExtensions(_ text: String) -> [String] {
        Array(Set(text.lowercased().components(separatedBy: CharacterSet(charactersIn: ",，;； ").union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".*")) }.filter { !$0.isEmpty })).sorted()
    }
    public func applies(to urls: [URL], directory: URL) -> Bool {
        let items = urls.isEmpty ? [directory] : urls
        return items.allSatisfy { url in
            guard let record = try? FileRecord(url: url) else { return false }
            switch target {
            case .all: return true
            case .folders: return record.browsable
            case .files: return !record.directory
            case .extensions: return !record.directory && fileExtensions.contains(url.pathExtension.lowercased())
            }
        }
    }
    enum CodingKeys: String, CodingKey { case id, name, script, foldersOnly, target, fileExtensions }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id); name = try values.decode(String.self, forKey: .name); script = try values.decode(String.self, forKey: .script)
        let oldFolders = try values.decodeIfPresent(Bool.self, forKey: .foldersOnly) ?? false
        target = try values.decodeIfPresent(CommandTarget.self, forKey: .target) ?? (oldFolders ? .folders : .all)
        fileExtensions = Self.normalizeExtensions((try values.decodeIfPresent([String].self, forKey: .fileExtensions) ?? []).joined(separator: ","))
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(name, forKey: .name); try values.encode(script, forKey: .script)
        try values.encode(foldersOnly, forKey: .foldersOnly); try values.encode(target, forKey: .target); try values.encode(fileExtensions, forKey: .fileExtensions)
    }
}
