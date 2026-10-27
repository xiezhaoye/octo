import Foundation

public enum TextFileKind: String, CaseIterable, Sendable {
    case markdown, html, text, json
    public var title: String { switch self { case .markdown: return "Markdown"; case .html: return "HTML"; case .text: return "TXT"; case .json: return "JSON" } }
    public var fileExtension: String { switch self { case .markdown: return "md"; case .html: return "html"; case .text: return "txt"; case .json: return "json" } }
    public var initialContent: String { switch self { case .json: return "{}\n"; case .html: return "<!doctype html>\n<html lang=\"zh-CN\">\n<head><meta charset=\"utf-8\"><title>新文档</title></head>\n<body>\n\n</body>\n</html>\n"; default: return "" } }
    public static func identify(_ url: URL) -> Self? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "html", "htm": return .html
        case "txt", "text", "log", "csv", "yaml", "yml", "toml", "xml", "css", "js", "ts", "sh", "ini", "conf": return .text
        case "json": return .json
        default: return nil
        }
    }
    @discardableResult public func create(in directory: URL, name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else { throw TextDocumentError.invalidName }
        let filename = (name as NSString).pathExtension.isEmpty ? name + "." + fileExtension : name
        let url = directory.appendingPathComponent(filename)
        try Data(initialContent.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }
}

public enum TextDocumentError: LocalizedError {
    case tooLarge, unsupportedEncoding, changedOnDisk, invalidName
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "文件超过 8 MB，请使用外部编辑器打开。"
        case .unsupportedEncoding: return "文件不是受支持的 UTF-8 或 UTF-16 文本，请使用外部编辑器打开。"
        case .changedOnDisk: return "文件已被外部修改或删除。请保留编辑内容，重新载入前先复制需要保留的文字。"
        case .invalidName: return "文件名不能为空，不能为 . 或 ..，也不能包含 /、: 或空字符。"
        }
    }
}

/// Keeps the original bytes as a conflict baseline and preserves BOM, encoding and line endings.
public struct TextDocument {
    public let url: URL
    public private(set) var content: String
    public private(set) var originalData: Data
    private let encoding: String.Encoding
    private let bom: Data
    private let newline: String
    public init(url: URL) throws {
        self.url = url.resolvingSymlinksInPath()
        let size = try self.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8 * 1024 * 1024 else { throw TextDocumentError.tooLarge }
        let bytes = try Data(contentsOf: self.url)
        guard bytes.count <= 8 * 1024 * 1024 else { throw TextDocumentError.tooLarge }
        originalData = bytes
        if bytes.starts(with: [0xFF, 0xFE]) { encoding = .utf16LittleEndian; bom = Data([0xFF, 0xFE]) }
        else if bytes.starts(with: [0xFE, 0xFF]) { encoding = .utf16BigEndian; bom = Data([0xFE, 0xFF]) }
        else { encoding = .utf8; bom = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Data([0xEF, 0xBB, 0xBF]) : Data() }
        guard let decoded = String(data: bytes.dropFirst(bom.count), encoding: encoding), !decoded.contains("\0") else { throw TextDocumentError.unsupportedEncoding }
        newline = decoded.contains("\r\n") ? "\r\n" : decoded.contains("\r") && !decoded.contains("\n") ? "\r" : "\n"
        content = decoded.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
    public func hasExternalChanges() -> Bool { (try? Data(contentsOf: url)) != originalData }
    public mutating func save(_ text: String) throws {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let body = normalized.replacingOccurrences(of: "\n", with: newline).data(using: encoding) else { throw TextDocumentError.unsupportedEncoding }
        let bytes = bom + body
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
            do {
                guard (try? Data(contentsOf: coordinated)) == originalData else { throw TextDocumentError.changedOnDisk }
                try bytes.write(to: coordinated, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
        content = normalized; originalData = bytes
    }
}
