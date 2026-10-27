import Foundation

public enum BuiltinContextCommand: String, CaseIterable, Sendable {
    case copyPath, copyDirectoryPath, openTerminal, open, preview, copy, rename, trash, paste, moveHere, newFolder, newFile, expandAll, collapseAll, termius, toggleHidden, manageCommands
    public var title: String {
        switch self {
        case .copyPath: return "复制完整路径"; case .copyDirectoryPath: return "复制目录路径"; case .openTerminal: return "在终端打开"
        case .open: return "打开"; case .preview: return "快速预览"; case .copy: return "复制"; case .rename: return "重命名…"; case .trash: return "移入废纸篓…"
        case .paste: return "粘贴"; case .moveHere: return "将剪贴板项目移到此处"; case .newFolder: return "新建文件夹…"; case .newFile: return "新建文件"
        case .expandAll: return "展开所有文件夹"; case .collapseAll: return "收拢所有文件夹"; case .termius: return "Termius：复制路径并打开"
        case .toggleHidden: return "显示／隐藏隐藏项目"; case .manageCommands: return "管理右键命令…"
        }
    }
}

public enum ContextMenuOrder {
    public static func key(for command: CustomCommand) -> String { "custom:" + command.id.uuidString }
    public static func keys(saved: [String]?, commands: [CustomCommand]) -> [String] {
        let builtins = BuiltinContextCommand.allCases.filter { $0 != .manageCommands }.map(\.rawValue)
        let defaults = builtins + commands.map(key) + [BuiltinContextCommand.manageCommands.rawValue]
        let valid = Set(defaults); var seen = Set<String>()
        return ((saved ?? []) + defaults).filter { valid.contains($0) && seen.insert($0).inserted }
    }
    public static func moving(_ key: String, in keys: [String], before row: Int) -> [String] {
        guard let source = keys.firstIndex(of: key) else { return keys }
        var result = keys; result.remove(at: source)
        let insertion = min(result.count, max(0, row - (source < row ? 1 : 0)))
        result.insert(key, at: insertion); return result
    }
}
