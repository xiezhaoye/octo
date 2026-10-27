import Foundation

public enum FileContextPaths {
    public static func fullPaths(for urls: [URL], directory: URL) -> [String] {
        (urls.isEmpty ? [directory] : urls).map(\.path)
    }
    public static func directoryPaths(for urls: [URL], directory: URL) -> [String] {
        let folders = urls.isEmpty ? [directory] : urls.map { url in
            (try? FileRecord(url: url).browsable) == true ? url : url.deletingLastPathComponent()
        }
        var seen = Set<String>()
        return folders.map(\.path).filter { seen.insert($0).inserted }
    }
}
