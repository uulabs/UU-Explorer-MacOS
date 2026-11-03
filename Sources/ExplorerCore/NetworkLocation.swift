import Foundation

public enum NetworkProtocol: String, Codable, CaseIterable, Sendable {
    case smb
    case afp
    case nfs

    public var title: String { rawValue.uppercased() }
}

public enum NetworkLocationError: LocalizedError {
    case emptyAddress
    case unsupportedScheme(String)
    case missingHost
    case invalidAddress(String)

    public var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "Enter a server address."
        case .unsupportedScheme(let scheme):
            return "Use an SMB, AFP, or NFS address (not “\(scheme)”)."
        case .missingHost:
            return "The address needs a server name."
        case .invalidAddress(let value):
            return "“\(value)” isn’t a valid network address."
        }
    }
}

public struct NetworkLocation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var urlString: String
    public var protocolName: NetworkProtocol
    public var autoConnect: Bool

    public var url: URL? { URL(string: urlString) }

    public init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        protocolName: NetworkProtocol,
        autoConnect: Bool = false
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.protocolName = protocolName
        self.autoConnect = autoConnect
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, urlString, protocolName, autoConnect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        urlString = try container.decode(String.self, forKey: .urlString)
        protocolName = try container.decode(NetworkProtocol.self, forKey: .protocolName)
        autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
    }

    public static func parse(
        address: String,
        name: String = "",
        autoConnect: Bool = false
    ) throws -> NetworkLocation {
        var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetworkLocationError.emptyAddress }
        if !trimmed.contains("://") {
            trimmed = "smb://\(trimmed)"
        }
        guard let url = URL(string: trimmed) else {
            throw NetworkLocationError.invalidAddress(trimmed)
        }
        guard let scheme = url.scheme?.lowercased() else {
            throw NetworkLocationError.invalidAddress(trimmed)
        }
        guard let networkProtocol = NetworkProtocol(rawValue: scheme) else {
            throw NetworkLocationError.unsupportedScheme(scheme)
        }
        guard let host = url.host, !host.isEmpty else {
            throw NetworkLocationError.missingHost
        }

        var normalized = URLComponents()
        normalized.scheme = scheme
        normalized.host = host
        normalized.path = url.path == "/" ? "" : url.path
        guard let normalizedURL = normalized.url else {
            throw NetworkLocationError.invalidAddress(trimmed)
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathName = normalizedURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fallback = pathName.isEmpty ? host : "\(host)/\(pathName)"
        return NetworkLocation(
            name: trimmedName.isEmpty ? fallback : trimmedName,
            urlString: normalizedURL.absoluteString,
            protocolName: networkProtocol,
            autoConnect: autoConnect
        )
    }
}
