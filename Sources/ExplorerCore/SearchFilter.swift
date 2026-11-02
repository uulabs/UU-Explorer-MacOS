import Foundation
import UniformTypeIdentifiers

public enum SearchTextMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case name
    case nameAndContent
    case content

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .name: return "Name"
        case .nameAndContent: return "Name & Contents"
        case .content: return "Contents"
        }
    }
}

public enum SearchKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case image
    case document
    case audio
    case video
    case code
    case archive

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .image: return "Images"
        case .document: return "Documents"
        case .audio: return "Audio"
        case .video: return "Video"
        case .code: return "Code"
        case .archive: return "Archives"
        }
    }

    public var symbol: String {
        switch self {
        case .image: return "photo"
        case .document: return "doc.text"
        case .audio: return "waveform"
        case .video: return "film"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archive: return "archivebox"
        }
    }

    fileprivate func matches(_ type: UTType?) -> Bool {
        guard let type else { return false }
        switch self {
        case .image: return type.conforms(to: .image)
        case .audio: return type.conforms(to: .audio)
        case .video: return type.conforms(to: .movie) || type.conforms(to: .video)
        case .archive: return type.conforms(to: .archive) || type.conforms(to: .zip) || type.conforms(to: .gzip)
        case .code:
            return type.conforms(to: .sourceCode)
                || [.json, .xml, .yaml, .html, .script].contains(where: { type.conforms(to: $0) })
        case .document:
            return type.conforms(to: .text)
                || type.conforms(to: .pdf)
                || type.conforms(to: .rtf)
                || type.conforms(to: .html)
                || ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "odt", "ods", "odp"]
                    .contains(type.preferredFilenameExtension ?? "")
        }
    }
}

public struct SearchFilter: Codable, Equatable, Sendable {
    public var textMode: SearchTextMode
    public var minimumSize: Int64?
    public var kind: SearchKind?
    public var modifiedWithinDays: Int?

    public init(
        textMode: SearchTextMode = .name,
        minimumSize: Int64? = nil,
        kind: SearchKind? = nil,
        modifiedWithinDays: Int? = nil
    ) {
        self.textMode = textMode
        self.minimumSize = minimumSize
        self.kind = kind
        self.modifiedWithinDays = modifiedWithinDays
    }

    public var isActive: Bool {
        minimumSize != nil || kind != nil || modifiedWithinDays != nil
    }

    public func matches(_ item: FileItem, now: Date = Date()) -> Bool {
        if let minimumSize {
            guard !item.isDirectory, (item.byteSize ?? 0) >= minimumSize else { return false }
        }
        if let kind {
            guard !item.isDirectory else { return false }
            let type = item.typeIdentifier.flatMap { UTType($0) }
                ?? UTType(filenameExtension: item.url.pathExtension)
            guard kind.matches(type) else { return false }
        }
        if let modifiedWithinDays {
            guard let date = item.dateModified,
                  date >= now.addingTimeInterval(-Double(modifiedWithinDays) * 86_400) else {
                return false
            }
        }
        return true
    }
}
