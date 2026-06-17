import XCTest
@testable import GameCore

/// Exporters tests — run-directory isolation and timestamp collisions (audit BH-02).
final class ExporterTests: XCTestCase {

    private func makeTempExporters() throws -> (Exporters, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aoecard-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (Exporters(outputRoot: tmp), tmp)
    }

    // MARK: - BH-02: run-dir timestamp collision must not overwrite prior runs

    /// Two `makeRunDir` calls with the SAME minute-granularity timestamp must
    /// return DIFFERENT directories so the second run does not overwrite the
    /// first. Before the fix, both calls returned the same path and the second
    /// run's games.csv clobbered the first (silent data loss).
    func testMakeRunDirCollidesSafelyWithSuffix() throws {
        let (exporters, root) = try makeTempExporters()
        let ts = "20260101_1200"

        let dir1 = try exporters.makeRunDir(timestamp: ts)
        // Plant a marker file to prove the first run survives the second.
        let marker1 = dir1.appendingPathComponent("games.csv")
        try "run-1-data".write(to: marker1, atomically: true, encoding: .utf8)

        let dir2 = try exporters.makeRunDir(timestamp: ts)
        let marker2 = dir2.appendingPathComponent("games.csv")
        try "run-2-data".write(to: marker2, atomically: true, encoding: .utf8)

        // The two directories MUST differ.
        XCTAssertNotEqual(dir1.path, dir2.path,
            "makeRunDir collision: same-timestamp runs returned the same path; second would overwrite first")
        // Both run data must survive.
        let survived1 = try String(contentsOf: marker1, encoding: .utf8)
        XCTAssertEqual(survived1, "run-1-data",
            "first run's data was overwritten by the second run")
        // The second dir lives under the same root.
        XCTAssertTrue(dir2.path.hasPrefix(root.path))

        // Cleanup
        try? FileManager.default.removeItem(at: root)
    }

    /// Different timestamps still produce their natural paths (no spurious suffix).
    func testMakeRunDirDifferentTimestampsNoSuffix() throws {
        let (exporters, root) = try makeTempExporters()
        let dirA = try exporters.makeRunDir(timestamp: "20260101_1200")
        let dirB = try exporters.makeRunDir(timestamp: "20260101_1201")
        XCTAssertNotEqual(dirA.path, dirB.path)
        XCTAssertTrue(dirA.lastPathComponent == "run_20260101_1200")
        XCTAssertTrue(dirB.lastPathComponent == "run_20260101_1201")
        try? FileManager.default.removeItem(at: root)
    }
}
