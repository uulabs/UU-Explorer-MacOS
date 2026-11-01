import Foundation

enum CustomActionScope: String, Codable, CaseIterable, Identifiable {
    case selection
    case currentFolder

    var id: String { rawValue }
    var title: String {
        switch self {
        case .selection: return "Selected Items"
        case .currentFolder: return "Current Folder"
        }
    }
}

struct CustomAction: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var scope: CustomActionScope
    var runInTerminal: Bool
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        command: String = "",
        scope: CustomActionScope = .selection,
        runInTerminal: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.scope = scope
        self.runInTerminal = runInTerminal
        self.isEnabled = isEnabled
    }
}
