import Foundation

public enum FolderTagColor: Int, CaseIterable, Codable, Sendable {
    case red = 6, orange = 7, yellow = 5, green = 2, blue = 4, purple = 3, gray = 1
    public var title: String {
        switch self { case .red:return "红色";case .orange:return "橙色";case .yellow:return "黄色";case .green:return "绿色";case .blue:return "蓝色";case .purple:return "紫色";case .gray:return "灰色" }
    }
}

extension Workspace {
    public func colors(for url:URL) -> [FolderTagColor] {
        folderColors?[url.standardizedFileURL.path] ?? []
    }
    public mutating func setFolderColor(_ color:FolderTagColor?,enabled:Bool,at url:URL) {
        let key=url.standardizedFileURL.path
        var colors=folderColors?[key] ?? []
        if let color {colors.removeAll{$0 == color};if enabled {colors.insert(color,at:0)}} else {colors=[]}
        if folderColors == nil {folderColors=[:]}
        if colors.isEmpty {folderColors?.removeValue(forKey:key)} else {folderColors?[key]=colors}
    }
}
