import AppKit
import ExplorerCore
import UniformTypeIdentifiers

@MainActor
enum AppIcons {
    private static var typeCache: [String: NSImage] = [:]
    private static var packageCache: [String: NSImage] = [:]

    static func icon(
        for item: FileItem,
        folderColor: ThemeColor = ThemeColor(hex: "#4B9BFF") ?? .readableDark,
        folderStyle: FolderIconStyle = .classic
    ) -> NSImage {
        if item.isApplication || item.isPackage {
            if let cached = packageCache[item.url.path] { return cached }
            let icon = NSWorkspace.shared.icon(forFile: item.url.path)
            packageCache[item.url.path] = icon
            return icon
        }
        if item.isDirectory {
            return FolderIconRenderer.icon(folderColor: folderColor, style: folderStyle)
        }

        let ext = item.url.pathExtension.lowercased()
        let key = ext.isEmpty ? "<none>" : ext
        if let cached = typeCache[key] { return cached }
        let type = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        typeCache[key] = icon
        return icon
    }

    static func folderIcon(folderColor: ThemeColor, style: FolderIconStyle) -> NSImage {
        FolderIconRenderer.icon(folderColor: folderColor, style: style)
    }
}
