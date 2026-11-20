import AppKit
import SwiftUI

struct OpenWithResolvedApplication: Identifiable, @unchecked Sendable {
    let url: URL
    let name: String
    let icon: NSImage

    var id: String { url.path }
}

@MainActor
final class OpenWithResolver: ObservableObject {
    static let shared = OpenWithResolver()

    @Published private(set) var revision = 0

    private struct CacheEntry {
        let applications: [OpenWithResolvedApplication]
        let resolvedAt: Date
        var lastUsedAt: Date
    }

    private static let cacheLifetime: TimeInterval = 60
    private static let cacheCapacity = 50
    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<[OpenWithResolvedApplication], Never>] = [:]

    func cachedApplications(for url: URL) -> [OpenWithResolvedApplication]? {
        let key = cacheKey(for: url)
        guard var entry = cache[key] else { return nil }
        entry.lastUsedAt = Date()
        cache[key] = entry
        return entry.applications
    }

    @discardableResult
    func loadApplications(for url: URL) async -> [OpenWithResolvedApplication] {
        let key = cacheKey(for: url)
        let now = Date()
        if var entry = cache[key], now.timeIntervalSince(entry.resolvedAt) < Self.cacheLifetime {
            entry.lastUsedAt = now
            cache[key] = entry
            return entry.applications
        }
        if let task = inFlight[key] { return await task.value }

        let task = Task.detached(priority: .utility) {
            Self.resolveApplications(for: url)
        }
        inFlight[key] = task
        let applications = await task.value
        inFlight[key] = nil
        cache[key] = CacheEntry(applications: applications, resolvedAt: Date(), lastUsedAt: Date())
        while cache.count > Self.cacheCapacity,
              let oldestKey = cache.min(by: { $0.value.lastUsedAt < $1.value.lastUsedAt })?.key {
            cache.removeValue(forKey: oldestKey)
        }
        revision &+= 1
        return applications
    }

    private func cacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private nonisolated static func resolveApplications(for url: URL) -> [OpenWithResolvedApplication] {
        let workspace = NSWorkspace.shared
        let fileManager = FileManager.default
        var seenPaths = Set<String>()
        var seenNames = Set<String>()
        let applications = workspace.urlsForApplications(toOpen: url)
            .map(\.standardizedFileURL)
            .filter { seenPaths.insert($0.path).inserted }
            .map { url in
                let displayName = fileManager.displayName(atPath: url.path)
                return (url: url, name: displayName.isEmpty ? url.lastPathComponent : displayName)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .filter { seenNames.insert($0.name).inserted }
            .prefix(20)

        return applications.map { application in
            let icon = workspace.icon(forFile: application.url.path)
            icon.size = NSSize(width: 16, height: 16)
            return OpenWithResolvedApplication(
                url: application.url,
                name: application.name,
                icon: icon
            )
        }
    }
}

struct OpenWithMenu: View {
    let url: URL
    let action: (URL) -> Void

    @ObservedObject private var resolver = OpenWithResolver.shared

    var body: some View {
        Menu("Open With") {
            Group {
                if let applications = resolver.cachedApplications(for: url) {
                    if applications.isEmpty {
                        Button("No Compatible Applications") {}
                            .disabled(true)
                    } else {
                        ForEach(applications) { application in
                            Button {
                                action(application.url)
                            } label: {
                                Label {
                                    Text(application.name)
                                } icon: {
                                    Image(nsImage: application.icon)
                                }
                            }
                        }
                    }
                } else {
                    Button("Loading Applications…") {}
                        .disabled(true)
                }
            }
            .task(id: url) {
                await resolver.loadApplications(for: url)
            }
        }
    }
}
