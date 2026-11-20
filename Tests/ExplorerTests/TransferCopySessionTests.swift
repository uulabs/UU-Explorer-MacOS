import Darwin
import XCTest
@testable import Explorer

@MainActor
final class TransferCopySessionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransferCopySessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    func testParserReadsNumericTokenImmediatelyBeforeBytesMarker() {
        let source = root.appendingPathComponent("source")
        let output = """
        copying file ./a.txt ... 6 bytes for ./a.txt
        12 bytes for ./b.txt
        hardlinked ./c.txt ... 18 bytes for ./c.txt
        cloned ./d.txt ... 24 bytes for ./d.txt

        """

        let result = parse(output, source: source)

        XCTAssertEqual(result.copiedBytes, 60)
        XCTAssertEqual(result.diagnostics, "")
    }

    func testParserHandlesRecordsSplitAcrossReads() {
        let source = root.appendingPathComponent("source")
        var parser = DittoOutputParser(source: source, sourceIsDirectory: false)
        let data = Data("copying file ./a.txt ... 12345 bytes for ./a.txt\n".utf8)

        for offset in stride(from: 0, to: data.count, by: 7) {
            let end = min(offset + 7, data.count)
            _ = parser.consume(data.subdata(in: offset..<end))
        }
        parser.finish()

        XCTAssertEqual(parser.result.copiedBytes, 12_345)
        XCTAssertEqual(parser.result.diagnostics, "")
    }

    func testParserCountsHardLinkAndCloneRecordsFromRegularSourceFiles() throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("abcdef".utf8).write(to: source.appendingPathComponent("a.txt"))

        let result = parse(
            "hardlinked ./a.txt\ncloned ./a.txt\n",
            source: source,
            sourceIsDirectory: true
        )

        XCTAssertEqual(result.copiedBytes, 12)
        XCTAssertEqual(result.diagnostics, "")
    }

    func testParserRecognizesOrdinaryAndSymlinkProgressWithoutDiagnostics() throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("abcdef".utf8).write(to: source.appendingPathComponent("a.txt"))
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("link"),
            withDestinationURL: source.appendingPathComponent("a.txt")
        )

        let result = parse(
            ">>> Copying /tmp/source \ncopying file ./a.txt ... \ncopying symlink ./link ... \nlinked ./link\n",
            source: source,
            sourceIsDirectory: true
        )

        XCTAssertEqual(result.copiedBytes, 0)
        XCTAssertEqual(result.diagnostics, "")
    }

    func testParserPreservesDiagnosticsWithStatusPrefixes() {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let lines = [
            "copying file ./a.txt ... invalid bytes for ./a.txt",
            "copying file ./a.txt: Permission denied",
            "hardlinked ./missing.txt",
            "cloned ./missing.txt",
            "linked ./missing.txt"
        ]

        let result = parse(lines.joined(separator: "\n"), source: source, sourceIsDirectory: true)

        XCTAssertEqual(result.copiedBytes, 0)
        XCTAssertEqual(result.diagnostics, lines.joined(separator: "\n"))
    }

    func testParserPreservesSingleFileLinkErrors() throws {
        let source = root.appendingPathComponent("a.txt")
        try Data("abcdef".utf8).write(to: source)
        let lines = [
            "hardlinked ./a.txt: Permission denied",
            "cloned ./a.txt: Permission denied",
            "linked ./a.txt: Permission denied"
        ]

        let result = parse(lines.joined(separator: "\n"), source: source)

        XCTAssertEqual(result.copiedBytes, 0)
        XCTAssertEqual(result.diagnostics, lines.joined(separator: "\n"))
    }

    func testRealCopyReportsFinalBytesAndVerificationOrdering() async throws {
        let source = root.appendingPathComponent("source.txt")
        let target = root.appendingPathComponent("target.txt")
        let data = Data(repeating: 0x5a, count: 1_000_000)
        try data.write(to: source)
        let session = TransferCopySession(
            source: source,
            target: target,
            totalBytes: Int64(data.count),
            verifyAfterCopy: true
        )
        var progress: [Int64] = []
        var verification: [Bool] = []

        try await session.start(
            onProgress: { progress.append($0) },
            onVerification: { verification.append($0) }
        )

        XCTAssertEqual(try Data(contentsOf: target), data)
        XCTAssertEqual(progress.last, Int64(data.count))
        XCTAssertEqual(verification, [true, false])
    }

    func testSingleFileCopySamplesIntermediateTargetSize() async throws {
        let source = root.appendingPathComponent("large-source.bin")
        let target = root.appendingPathComponent("large-target.bin")
        let chunkCount = 8
        let chunkSize = 65_536
        let byteCount = chunkCount * chunkSize
        try Data(repeating: 0xa5, count: byteCount).write(to: source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            : > "$1"
            index=0
            while [ "$index" -lt \(chunkCount) ]; do
                /bin/dd if=/dev/zero bs=\(chunkSize) count=1 >> "$1" 2>/dev/null
                /bin/sleep 0.02
                index=$((index + 1))
            done
            """,
            "sh",
            target.path
        ]
        let session = TransferCopySession(
            source: source,
            target: target,
            totalBytes: Int64(byteCount),
            verifyAfterCopy: false,
            progressPollIntervalNanoseconds: 1_000_000,
            processOverride: process
        )
        var progress: [Int64] = []

        try await session.start(
            onProgress: { progress.append($0) },
            onVerification: { _ in }
        )

        XCTAssertTrue(
            progress.contains { $0 > 0 && $0 < Int64(byteCount) },
            "Expected an intermediate byte sample, got \(progress)"
        )
        XCTAssertEqual(progress.last, Int64(byteCount))
        XCTAssertEqual(try target.resourceValues(forKeys: [.fileSizeKey]).fileSize, byteCount)
    }

    func testCancellationBeforeStartDoesNotCreateTarget() async throws {
        let source = root.appendingPathComponent("source.txt")
        let target = root.appendingPathComponent("target.txt")
        try Data("contents".utf8).write(to: source)
        let session = TransferCopySession(
            source: source,
            target: target,
            totalBytes: 8,
            verifyAfterCopy: false
        )
        session.cancel()

        await assertCancelled(session)

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testCancellationStopsRealCopyProcess() async throws {
        let source = root.appendingPathComponent("source.fifo")
        let target = root.appendingPathComponent("target.fifo")
        XCTAssertEqual(mkfifo(source.path, 0o600), 0)
        let session = TransferCopySession(
            source: source,
            target: target,
            totalBytes: 1,
            verifyAfterCopy: false,
            progressPollIntervalNanoseconds: 10_000_000
        )

        let copy = Task {
            try await session.start(onProgress: { _ in }, onVerification: { _ in })
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        session.cancel()

        do {
            try await copy.value
            XCTFail("Expected cancellation")
        } catch let error as TransferCopyError {
            guard case .cancelled = error else {
                return XCTFail("Expected cancellation, got \(error)")
            }
        }
    }

    private func parse(
        _ output: String,
        source: URL,
        sourceIsDirectory: Bool = false
    ) -> DittoOutputParser.Result {
        var parser = DittoOutputParser(source: source, sourceIsDirectory: sourceIsDirectory)
        _ = parser.consume(Data(output.utf8))
        parser.finish()
        return parser.result
    }

    private func assertCancelled(_ session: TransferCopySession) async {
        do {
            try await session.start(onProgress: { _ in }, onVerification: { _ in })
            XCTFail("Expected cancellation")
        } catch let error as TransferCopyError {
            guard case .cancelled = error else {
                return XCTFail("Expected cancellation, got \(error)")
            }
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }
    }
}
