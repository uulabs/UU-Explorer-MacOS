import AppKit
import ImageIO
import XCTest
import ExplorerCore
@testable import Explorer

@MainActor
final class ThumbnailStoreTests: XCTestCase {
    func testDecodeConcurrencyIsBounded() async {
        let decoder = TestDecoder()
        decoder.delay = 0.02
        let store = ThumbnailStore(maximumConcurrentDecodes: 2, decoder: { url, maxPixelSize in
            decoder.decode(url: url, maxPixelSize: maxPixelSize)
        })
        let items = (0..<6).map { makeItem(name: "image-\($0)") }

        await withTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask { await store.request(for: item) }
            }
        }

        XCTAssertEqual(decoder.calls, 6)
        XCTAssertLessThanOrEqual(decoder.maximumActive, 2)
        for item in items {
            XCTAssertNotNil(store.image(for: item))
        }
    }

    func testTransientFailureRetriesWithBackoff() async {
        let decoder = TestDecoder()
        decoder.failuresRemaining = 1
        let store = ThumbnailStore(
            initialRetryDelay: 0.01,
            maximumRetryDelay: 0.02,
            decoder: { url, maxPixelSize in
                decoder.decode(url: url, maxPixelSize: maxPixelSize)
            }
        )
        let item = makeItem()

        await store.request(for: item)

        XCTAssertEqual(decoder.calls, 2)
        XCTAssertNotNil(store.image(for: item))
    }

    func testCancellingWaitingViewRemovesQueuedDecode() async {
        let decoder = TestDecoder()
        decoder.gate = DispatchSemaphore(value: 0)
        let store = ThumbnailStore(maximumConcurrentDecodes: 1, decoder: { url, maxPixelSize in
            decoder.decode(url: url, maxPixelSize: maxPixelSize)
        })
        let first = makeItem(name: "first")
        let second = makeItem(name: "second")

        let firstRequest = Task { await store.request(for: first) }
        await waitUntil { decoder.calls == 1 }
        let secondRequest = Task { await store.request(for: second) }
        await Task.yield()
        secondRequest.cancel()
        decoder.gate?.signal()
        decoder.gate?.signal()

        await firstRequest.value
        await secondRequest.value

        XCTAssertEqual(decoder.calls, 1)
        XCTAssertNotNil(store.image(for: first))
        XCTAssertNil(store.image(for: second))
    }

    func testInvalidationIgnoresInFlightCompletion() async {
        let decoder = TestDecoder()
        decoder.gate = DispatchSemaphore(value: 0)
        let store = ThumbnailStore(decoder: { url, maxPixelSize in
            decoder.decode(url: url, maxPixelSize: maxPixelSize)
        })
        let item = makeItem()

        let request = Task { await store.request(for: item) }
        await waitUntil { decoder.calls == 1 }
        store.invalidate()
        decoder.gate?.signal()
        await request.value
        await waitUntil { decoder.completed == 1 }
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertNil(store.image(for: item))
    }

    func testRealImageIODecodePopulatesCache() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailStoreTests-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try XCTUnwrap(TestDecoder.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let item = makeItem(url: url)
        let store = ThumbnailStore()

        await store.request(for: item)

        XCTAssertNotNil(store.image(for: item))
    }

    private func makeItem(name: String = "image", url: URL? = nil) -> FileItem {
        FileItem(
            url: url ?? URL(fileURLWithPath: "/tmp/\(name).png"),
            name: url?.lastPathComponent ?? "\(name).png",
            isDirectory: false,
            isPackage: false,
            isHidden: false,
            isSymbolicLink: false,
            isApplication: false,
            dateModified: Date(timeIntervalSince1970: 1),
            byteSize: 1,
            kind: "PNG image",
            isImage: true
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Condition was not met before timeout")
    }
}

private final class TestDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var _maximumActive = 0
    private var _calls = 0
    private var _completed = 0

    var delay: TimeInterval = 0
    var failuresRemaining = 0
    var gate: DispatchSemaphore?

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    var completed: Int {
        lock.lock()
        defer { lock.unlock() }
        return _completed
    }

    var maximumActive: Int {
        lock.lock()
        defer { lock.unlock() }
        return _maximumActive
    }

    func decode(url: URL, maxPixelSize: Int) -> CGImage? {
        lock.lock()
        _calls += 1
        active += 1
        _maximumActive = max(_maximumActive, active)
        let shouldFail = failuresRemaining > 0
        if shouldFail {
            failuresRemaining -= 1
        }
        let delay = delay
        let gate = gate
        lock.unlock()

        gate?.wait()
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }

        lock.lock()
        active -= 1
        _completed += 1
        lock.unlock()

        return shouldFail ? nil : Self.makeImage()
    }

    static func makeImage() -> CGImage? {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }
}
