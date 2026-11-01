import XCTest
@testable import ExplorerCore

final class ArchiveServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testArchiveFormatDetection() {
        XCTAssertEqual(ArchiveService.format(for: URL(fileURLWithPath: "/tmp/photos.zip")), .zip)
        XCTAssertEqual(ArchiveService.format(for: URL(fileURLWithPath: "/tmp/backup.tar")), .tar)
        XCTAssertEqual(ArchiveService.format(for: URL(fileURLWithPath: "/tmp/backup.tar.gz")), .tarGz)
        XCTAssertEqual(ArchiveService.format(for: URL(fileURLWithPath: "/tmp/backup.tgz")), .tarGz)
        XCTAssertEqual(ArchiveService.format(for: URL(fileURLWithPath: "/tmp/backup.rar")), .rar)
        XCTAssertEqual(ArchiveService.format(for: URL(fileURLWithPath: "/tmp/backup.7z")), .sevenZip)
        XCTAssertNil(ArchiveService.format(for: URL(fileURLWithPath: "/tmp/notes.txt")))
    }

    func testZipFolderRoundTripPreservesNestedFiles() throws {
        let source = tempDirectory.appendingPathComponent("Project", isDirectory: true)
        let nested = source.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: source.appendingPathComponent("alpha.txt"))
        try Data("beta".utf8).write(to: nested.appendingPathComponent("beta.txt"))

        let archive = tempDirectory.appendingPathComponent("Project.zip")
        try ArchiveService.compress(source, to: archive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))

        let destination = tempDirectory.appendingPathComponent("Extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try ArchiveService.extract(archive, to: destination)

        let extractedAlpha = destination.appendingPathComponent("Project/alpha.txt")
        let extractedBeta = destination.appendingPathComponent("Project/Sub/beta.txt")
        XCTAssertEqual(try String(contentsOf: extractedAlpha, encoding: .utf8), "alpha")
        XCTAssertEqual(try String(contentsOf: extractedBeta, encoding: .utf8), "beta")
    }

    func testZipFileRoundTripKeepsRootFilename() throws {
        let source = tempDirectory.appendingPathComponent("solo.txt")
        try Data("solo".utf8).write(to: source)

        let archive = tempDirectory.appendingPathComponent("solo.txt.zip")
        try ArchiveService.compress(source, to: archive)

        let destination = tempDirectory.appendingPathComponent("ExtractedFile", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try ArchiveService.extract(archive, to: destination)

        let extracted = destination.appendingPathComponent("solo.txt")
        XCTAssertEqual(try String(contentsOf: extracted, encoding: .utf8), "solo")
    }

    func testTopLevelDirectoryDetection() throws {
        let source = tempDirectory.appendingPathComponent("Project", isDirectory: true)
        let nested = source.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: source.appendingPathComponent("alpha.txt"))
        try Data("beta".utf8).write(to: nested.appendingPathComponent("beta.txt"))

        let folderArchive = tempDirectory.appendingPathComponent("Project.zip")
        try ArchiveService.compress(source, to: folderArchive)
        XCTAssertEqual(ArchiveService.topLevelDirectoryName(folderArchive), "Project")

        let file = tempDirectory.appendingPathComponent("solo.txt")
        try Data("solo".utf8).write(to: file)
        let fileArchive = tempDirectory.appendingPathComponent("solo.txt.zip")
        try ArchiveService.compress(file, to: fileArchive)
        XCTAssertNil(ArchiveService.topLevelDirectoryName(fileArchive))
    }

    func testEncryptedZipRoundTrip() throws {
        let source = tempDirectory.appendingPathComponent("Secret", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("classified".utf8).write(to: source.appendingPathComponent("note.txt"))

        let archive = tempDirectory.appendingPathComponent("Secret.zip")
        try ArchiveService.compressEncrypted(source, to: archive, password: "correct horse battery staple")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-P", "correct horse battery staple", "-t", archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testSevenZipExtractionWithSystemBsdtar() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/bsdtar") else {
            throw XCTSkip("bsdtar is unavailable")
        }
        let source = tempDirectory.appendingPathComponent("Seven", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("seven".utf8).write(to: source.appendingPathComponent("seven.txt"))
        let archive = tempDirectory.appendingPathComponent("Seven.7z")

        let create = Process()
        create.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        create.arguments = ["-cf", archive.path, "--format", "7zip", source.lastPathComponent]
        create.currentDirectoryURL = tempDirectory
        create.standardOutput = FileHandle.nullDevice
        create.standardError = FileHandle.nullDevice
        try create.run()
        create.waitUntilExit()
        guard create.terminationStatus == 0 else {
            throw XCTSkip("bsdtar cannot write 7-Zip archives here")
        }

        let destination = tempDirectory.appendingPathComponent("SevenOut", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try ArchiveService.extract(archive, to: destination)
        let extracted = destination.appendingPathComponent("Seven/seven.txt")
        XCTAssertEqual(try String(contentsOf: extracted, encoding: .utf8), "seven")
    }

    func testUnsupportedArchiveIsRejected() throws {
        let archive = tempDirectory.appendingPathComponent("notes.txt")
        try Data("not an archive".utf8).write(to: archive)
        XCTAssertFalse(ArchiveService.isArchive(archive))
        XCTAssertThrowsError(try ArchiveService.extract(archive, to: tempDirectory))
    }
}
