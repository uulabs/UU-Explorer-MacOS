import Foundation
import ExplorerCore

struct LaunchOptions {
    var startURL: URL?
    var snapshotPath: String?
    var selectName: String?
    var editPath = false
    var pathDraft: String?
    var appearance: String?
    var selectAll = false
    var showNewFolder = false
    var viewMode: String?
    var themePreset: String?
    var themeAppearance: String?
    var folderStyle: String?
    var showSettings = false

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--path":
                if index + 1 < arguments.count {
                    let raw = arguments[index + 1]
                    options.startURL = PathTools.expand(raw, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    index += 1
                }
            case "--snapshot":
                if index + 1 < arguments.count {
                    options.snapshotPath = (arguments[index + 1] as NSString).expandingTildeInPath
                    index += 1
                }
            case "--select":
                if index + 1 < arguments.count {
                    options.selectName = arguments[index + 1]
                    index += 1
                }
            case "--edit-path":
                options.editPath = true
            case "--path-draft":
                if index + 1 < arguments.count {
                    options.pathDraft = arguments[index + 1]
                    index += 1
                }
            case "--appearance":
                if index + 1 < arguments.count {
                    options.appearance = arguments[index + 1]
                    index += 1
                }
            case "--select-all":
                options.selectAll = true
            case "--show-new-folder":
                options.showNewFolder = true
            case "--view":
                if index + 1 < arguments.count {
                    options.viewMode = arguments[index + 1]
                    index += 1
                }
            case "--theme-preset":
                if index + 1 < arguments.count {
                    options.themePreset = arguments[index + 1]
                    index += 1
                }
            case "--theme-appearance":
                if index + 1 < arguments.count {
                    options.themeAppearance = arguments[index + 1]
                    index += 1
                }
            case "--folder-style":
                if index + 1 < arguments.count {
                    options.folderStyle = arguments[index + 1]
                    index += 1
                }
            case "--settings":
                options.showSettings = true
            default:
                break
            }
            index += 1
        }
        return options
    }
}
