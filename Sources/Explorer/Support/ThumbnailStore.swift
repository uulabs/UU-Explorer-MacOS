import AppKit
import Combine
import ExplorerCore
import ImageIO

@MainActor
final class ThumbnailStore: ObservableObject {
    @Published private(set) var revision = 0

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight = Set<String>()
    private var failed = Set<String>()

    init() {
        cache.countLimit = 700
    }

    func key(for item: FileItem) -> String {
        let stamp = item.dateModified?.timeIntervalSince1970 ?? 0
        return "\(item.url.path)|\(stamp)"
    }

    func image(for item: FileItem) -> NSImage? {
        guard item.isImage, !item.isDirectory else { return nil }
        return cache.object(forKey: key(for: item) as NSString)
    }

    func request(for item: FileItem) {
        guard item.isImage, !item.isDirectory, !item.isPackage else { return }
        let key = key(for: item)
        guard cache.object(forKey: key as NSString) == nil,
              !inFlight.contains(key),
              !failed.contains(key) else { return }

        inFlight.insert(key)
        let url = item.url
        Task { [weak self] in
            let cgImage = await Task.detached(priority: .utility) {
                Self.downsample(url: url, maxPixelSize: 512)
            }.value
            guard let self else { return }
            self.inFlight.remove(key)
            guard let cgImage else {
                self.failed.insert(key)
                return
            }
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            self.cache.setObject(image, forKey: key as NSString)
            self.revision &+= 1
        }
    }

    func invalidate() {
        cache.removeAllObjects()
        failed.removeAll()
        revision &+= 1
    }

    private nonisolated static func downsample(url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
