import AppKit
import Combine
import ExplorerCore
import ImageIO

@MainActor
final class ThumbnailStore: ObservableObject {
    typealias Decoder = @Sendable (URL, Int) -> CGImage?

    @Published private(set) var revision = 0

    private struct Load {
        let id: UUID
        let url: URL
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
        var isQueued = false
        var activeTaskID: UUID?
        var retryTask: Task<Void, Never>?
        var failureCount = 0
    }

    private struct PendingLoad {
        let key: String
        let loadID: UUID
    }

    private let cache = NSCache<NSString, NSImage>()
    private let decoder: Decoder
    private let maximumConcurrentDecodes: Int
    private let initialRetryDelay: TimeInterval
    private let maximumRetryDelay: TimeInterval
    private var loads: [String: Load] = [:]
    private var pending: [PendingLoad] = []
    private var pendingOffset = 0
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var generation = 0
    private var revisionTask: Task<Void, Never>?

    init(
        maximumConcurrentDecodes: Int = 4,
        decodedByteBudget: Int = 128 * 1024 * 1024,
        initialRetryDelay: TimeInterval = 0.5,
        maximumRetryDelay: TimeInterval = 30,
        decoder: Decoder? = nil
    ) {
        precondition(maximumConcurrentDecodes > 0)
        self.maximumConcurrentDecodes = maximumConcurrentDecodes
        self.initialRetryDelay = initialRetryDelay
        self.maximumRetryDelay = maximumRetryDelay
        self.decoder = decoder ?? { url, maxPixelSize in
            Self.downsample(url: url, maxPixelSize: maxPixelSize)
        }
        cache.countLimit = 700
        cache.totalCostLimit = decodedByteBudget
    }

    func key(for item: FileItem) -> String {
        let stamp = item.dateModified?.timeIntervalSince1970 ?? 0
        return "\(item.url.path)|\(stamp)"
    }

    func image(for item: FileItem) -> NSImage? {
        guard item.isImage, !item.isDirectory else { return nil }
        return cache.object(forKey: key(for: item) as NSString)
    }

    func request(for item: FileItem) async {
        guard item.isImage, !item.isDirectory, !item.isPackage else { return }
        let key = key(for: item)
        guard cache.object(forKey: key as NSString) == nil else { return }
        let waiterID = UUID()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || cache.object(forKey: key as NSString) != nil {
                    continuation.resume()
                    return
                }
                addWaiter(waiterID, continuation: continuation, for: item, key: key)
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelWaiter(waiterID, for: key)
            }
        }
    }

    func invalidate() {
        generation &+= 1
        cache.removeAllObjects()
        for load in loads.values {
            load.retryTask?.cancel()
            if let taskID = load.activeTaskID {
                activeTasks[taskID]?.cancel()
            }
            for continuation in load.waiters.values {
                continuation.resume()
            }
        }
        loads.removeAll()
        pending.removeAll()
        pendingOffset = 0
        scheduleRevisionPublication()
    }

    private func addWaiter(
        _ waiterID: UUID,
        continuation: CheckedContinuation<Void, Never>,
        for item: FileItem,
        key: String
    ) {
        if var load = loads[key] {
            load.waiters[waiterID] = continuation
            loads[key] = load
            if load.activeTaskID == nil, load.retryTask == nil, !load.isQueued {
                enqueue(key: key, load: &load)
            }
        } else {
            var load = Load(id: UUID(), url: item.url)
            load.waiters[waiterID] = continuation
            loads[key] = load
            enqueue(key: key, load: &load)
        }
        pump()
    }

    private func cancelWaiter(_ waiterID: UUID, for key: String) {
        guard var load = loads[key], let continuation = load.waiters.removeValue(forKey: waiterID) else {
            return
        }
        continuation.resume()
        guard load.waiters.isEmpty else {
            loads[key] = load
            return
        }

        load.retryTask?.cancel()
        load.retryTask = nil
        load.isQueued = false
        if let taskID = load.activeTaskID {
            activeTasks[taskID]?.cancel()
            loads[key] = load
        } else {
            loads.removeValue(forKey: key)
        }
        pump()
    }

    private func enqueue(key: String, load: inout Load) {
        load.isQueued = true
        loads[key] = load
        pending.append(PendingLoad(key: key, loadID: load.id))
    }

    private func pump() {
        while activeTasks.count < maximumConcurrentDecodes, pendingOffset < pending.count {
            let next = pending[pendingOffset]
            pendingOffset += 1
            guard var load = loads[next.key],
                  load.id == next.loadID,
                  load.isQueued,
                  !load.waiters.isEmpty else { continue }
            load.isQueued = false
            loads[next.key] = load
            start(next.key, load: load)
        }
        compactPendingIfNeeded()
    }

    private func start(_ key: String, load: Load) {
        let taskID = UUID()
        var load = load
        load.activeTaskID = taskID
        loads[key] = load

        let generation = generation
        let decoder = decoder
        let task = Task { [weak self] in
            let cgImage = await Task.detached(priority: .utility) {
                decoder(load.url, 512)
            }.value
            self?.finish(
                key: key,
                loadID: load.id,
                taskID: taskID,
                generation: generation,
                cgImage: cgImage
            )
        }
        activeTasks[taskID] = task
    }

    private func finish(
        key: String,
        loadID: UUID,
        taskID: UUID,
        generation: Int,
        cgImage: CGImage?
    ) {
        guard activeTasks.removeValue(forKey: taskID) != nil else { return }
        guard generation == self.generation,
              var load = loads[key],
              load.id == loadID,
              load.activeTaskID == taskID else {
            pump()
            return
        }

        load.activeTaskID = nil
        guard !load.waiters.isEmpty else {
            loads.removeValue(forKey: key)
            pump()
            return
        }

        if let cgImage {
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            cache.setObject(
                image,
                forKey: key as NSString,
                cost: cgImage.bytesPerRow * cgImage.height
            )
            loads.removeValue(forKey: key)
            for continuation in load.waiters.values {
                continuation.resume()
            }
            scheduleRevisionPublication()
        } else {
            load.failureCount += 1
            loads[key] = load
            scheduleRetry(for: key, loadID: loadID)
        }
        pump()
    }

    private func scheduleRetry(for key: String, loadID: UUID) {
        guard var load = loads[key], load.id == loadID, !load.waiters.isEmpty else { return }
        let exponent = min(max(load.failureCount - 1, 0), 16)
        let delay = min(initialRetryDelay * pow(2, Double(exponent)), maximumRetryDelay)
        load.retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled,
                  let self,
                  var load = self.loads[key],
                  load.id == loadID,
                  !load.waiters.isEmpty else { return }
            load.retryTask = nil
            self.loads[key] = load
            self.enqueue(key: key, load: &load)
            self.pump()
        }
        loads[key] = load
    }

    private func scheduleRevisionPublication() {
        guard revisionTask == nil else { return }
        revisionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self else { return }
            self.revisionTask = nil
            self.revision &+= 1
        }
    }

    private func compactPendingIfNeeded() {
        if pendingOffset == pending.count {
            pending.removeAll(keepingCapacity: true)
            pendingOffset = 0
        } else if pendingOffset >= 64, pendingOffset * 2 >= pending.count {
            pending.removeFirst(pendingOffset)
            pendingOffset = 0
        }
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
