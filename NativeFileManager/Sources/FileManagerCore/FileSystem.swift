import Foundation

public struct FileRecord: Hashable, Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let directory: Bool
    public let package: Bool
    public let symbolicLink: Bool
    public let hidden: Bool
    public let size: Int64
    public let modified: Date?
    public var name: String { url.lastPathComponent }
    public var browsable: Bool { directory && !package }
    public init(url: URL) throws {
        self.url = url.standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey])
        directory = values.isDirectory ?? false; package = values.isPackage ?? false
        symbolicLink = values.isSymbolicLink ?? false; hidden = (values.isHidden ?? false) || url.lastPathComponent.hasPrefix(".")
        size = Int64(values.fileSize ?? 0); modified = values.contentModificationDate
    }
}

public actor DirectoryReader {
    public init() {}
    public func contents(of url: URL, showHidden: Bool) throws -> [FileRecord] {
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey], options: showHidden ? [] : [.skipsHiddenFiles])
        return files.compactMap { try? FileRecord(url: $0) }.filter { showHidden || !$0.hidden }.sorted {
            if $0.browsable != $1.browsable { return $0.browsable }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    public func search(in root: URL, query: String, showHidden: Bool, recursive: Bool = true, limit: Int = 10000) throws -> [FileRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try contents(of: root, showHidden: showHidden) }
        if !recursive { return try contents(of: root, showHidden: showHidden).filter { $0.name.localizedStandardContains(query) } }
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey], options: options, errorHandler: { _, _ in true }) else { return [] }
        var result: [FileRecord] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            if let item = try? FileRecord(url: url), item.name.localizedStandardContains(query), showHidden || !item.hidden {
                result.append(item); if result.count >= limit { break }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public enum TransferKind { case copy, move }
public struct TransferResult {
    public let source: URL
    public let destination: URL
    public let skipped: Bool
    public let moved: Bool
    public let note: String?
    public init(source: URL, destination: URL, skipped: Bool, moved: Bool, note: String? = nil) { self.source = source; self.destination = destination; self.skipped = skipped; self.moved = moved; self.note = note }
}
public enum FileOperationError: LocalizedError {
    case invalidDestination, conflict(String), sourceEqualsDestination, sourceRemovalFailed(String), rollbackFailed(String), retainedBackup(String, String)
    public var errorDescription: String? {
        switch self {
        case .invalidDestination: return "不能将文件夹放入它自己或其子目录。"
        case .conflict(let name): return "目标位置已存在“\(name)”。请选择替换、保留两者或跳过。"
        case .sourceEqualsDestination: return "来源和目标是同一个项目。请选择保留两者，或换一个目标目录。"
        case .sourceRemovalFailed(let path): return "目标副本已完整写入，但来源“\(path)”清理未完成。请检查权限并核对两处内容。"
        case .rollbackFailed(let path): return "操作未完成，原目标已保留在“\(path)”。请恢复该备份。"
        case .retainedBackup(let reason, let path): return reason + "\n替换前的目标备份保留在：" + path
        }
    }
}

public actor FileOperator {
    private let fm = FileManager.default
    private let recycle: @Sendable (URL) throws -> Void
    public init(recycle: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) { self.recycle = recycle }
    public func transfer(_ source: URL, to directory: URL, kind: TransferKind, conflict: ConflictPolicy) throws -> TransferResult {
        let source = source.standardizedFileURL
        let directory = directory.standardizedFileURL
        let realSource = source.resolvingSymlinksInPath().path
        let realDirectory = directory.resolvingSymlinksInPath().path
        let sourceRecord = try FileRecord(url: source)
        if sourceRecord.directory && (realDirectory == realSource || realDirectory.hasPrefix(realSource + "/")) { throw FileOperationError.invalidDestination }
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        let same = source.resolvingSymlinksInPath().path == destination.resolvingSymlinksInPath().path
        if same && kind == .move { return TransferResult(source: source, destination: destination, skipped: true, moved: false) }
        var backup: URL?
        if fm.fileExists(atPath: destination.path) {
            switch conflict {
            case .ask: throw FileOperationError.conflict(destination.lastPathComponent)
            case .skip: return TransferResult(source: source, destination: destination, skipped: true, moved: false)
            case .keepBoth: destination = uniqueURL(for: destination)
            case .replace:
                if same { throw FileOperationError.sourceEqualsDestination }
                let temp = directory.appendingPathComponent(".dualpane-backup-" + UUID().uuidString)
                try fm.moveItem(at: destination, to: temp); backup = temp
            }
        }
        do {
            let sourceVolume = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            let targetVolume = try? directory.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            if kind == .move, let sourceVolume, let targetVolume, sourceVolume == targetVolume {
                try fm.moveItem(at: source, to: destination)
            } else {
                // Copy into a staging name first. A failed copy never removes the source.
                let staging = directory.appendingPathComponent(".dualpane-transfer-" + UUID().uuidString)
                do {
                    try fm.copyItem(at: source, to: staging)
                    try fm.moveItem(at: staging, to: destination)
                } catch {
                    if fm.fileExists(atPath: staging.path) { try? fm.removeItem(at: staging) }
                    throw error
                }
                if kind == .move {
                    do { try fm.removeItem(at: source) }
                    catch { throw FileOperationError.sourceRemovalFailed(source.path) }
                }
            }
        } catch {
            if let backup, !fm.fileExists(atPath: destination.path) {
                do { try fm.moveItem(at: backup, to: destination) }
                catch { throw FileOperationError.rollbackFailed(backup.path) }
            }
            if let backup, fm.fileExists(atPath: backup.path) { throw FileOperationError.retainedBackup(error.localizedDescription, backup.path) }
            throw error
        }
        var note: String?
        if let backup { do { try recycle(backup) } catch { note = "替换已完成，原目标备份保留在：" + backup.path } }
        return TransferResult(source: source, destination: destination, skipped: false, moved: kind == .move, note: note)
    }
    public func createDirectory(in parent: URL, name: String) throws -> URL {
        try validate(name)
        let url = parent.appendingPathComponent(name)
        if fm.fileExists(atPath: url.path) { throw FileOperationError.conflict(name) }
        try fm.createDirectory(at: url, withIntermediateDirectories: false); return url
    }
    public func rename(_ source: URL, to name: String) throws -> URL {
        try validate(name)
        let target = source.deletingLastPathComponent().appendingPathComponent(name)
        if target.path == source.path { return source }
        if fm.fileExists(atPath: target.path) { throw FileOperationError.conflict(name) }
        try fm.moveItem(at: source, to: target); return target
    }
    public func trash(_ urls: [URL]) throws {
        for url in urls { try recycle(url) }
    }
    private func validate(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.contains("/") || name == "." || name == ".." || name.contains("\0") { throw CocoaError(.fileWriteInvalidFileName) }
    }
    private func uniqueURL(for original: URL) -> URL {
        let ext = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let name = stem + " 副本" + (n == 2 ? "" : " \(n)") + (ext.isEmpty ? "" : "." + ext)
            let candidate = original.deletingLastPathComponent().appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }; n += 1
        }
    }
}

public func shellQuote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
public func renderCommand(_ script: String, urls: [URL], directory: URL) -> String {
    // Single-pass substitution: user filenames cannot introduce another placeholder.
    let pattern = "\\{(paths|path|directory)\\}"
    let regex = try! NSRegularExpression(pattern: pattern)
    var result = script
    for match in regex.matches(in: script, range: NSRange(script.startIndex..., in: script)).reversed() {
        guard let range = Range(match.range, in: result), let keyRange = Range(match.range(at: 1), in: script) else { continue }
        let key = String(script[keyRange])
        let replacement = key == "paths" ? urls.map { shellQuote($0.path) }.joined(separator: " ") : shellQuote(key == "directory" ? directory.path : (urls.first?.path ?? directory.path))
        result.replaceSubrange(range, with: replacement)
    }
    return result
}
