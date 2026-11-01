import XCTest
@testable import ExplorerCore

final class TransferVerificationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransferVerificationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        try super.tearDownWithError()
    }

    func testLogicalByteTotals() throws {
        try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("a.bin"))
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 50).write(to: nested.appendingPathComponent("b.bin"))
        XCTAssertEqual(TransferMetrics.totalLogicalBytes(at: root), 150)
    }

    func testFingerprintMatchesCopyAndDetectsChanges() throws {
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("beta".utf8).write(to: source.appendingPathComponent("b.txt"))
        let target = root.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.copyItem(at: source, to: target)

        let sourceHash = try XCTUnwrap(TransferVerifier.fingerprint(at: source))
        XCTAssertEqual(sourceHash, TransferVerifier.fingerprint(at: target))
        XCTAssertTrue(TransferVerifier.verify(source: source, target: target))

        try Data("changed".utf8).write(to: target.appendingPathComponent("a.txt"))
        XCTAssertNotEqual(sourceHash, TransferVerifier.fingerprint(at: target))
        XCTAssertFalse(TransferVerifier.verify(source: source, target: target))
    }

    func testFingerprintIncludesRelativePaths() throws {
        let one = root.appendingPathComponent("One", isDirectory: true)
        let two = root.appendingPathComponent("Two", isDirectory: true)
        try FileManager.default.createDirectory(at: one, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)
        try Data("same".utf8).write(to: one.appendingPathComponent("file.txt"))
        try Data("same".utf8).write(to: two.appendingPathComponent("other.txt"))
        XCTAssertNotEqual(TransferVerifier.fingerprint(at: one), TransferVerifier.fingerprint(at: two))
    }
}
